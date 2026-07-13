import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun, deleteRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Global / famous-segment catalogue journey (decisions §232) — the
 * free-standing catalogue layer that matches a run END-TO-END against its
 * OWN geometry, with NO linked route. This is the seam that fixes the
 * chicken-and-egg gap for imported runs (route_id null never matched any
 * route-slice segment): a Strava-migrant's route-less run now backfills
 * catalogue efforts on its own detail page and lands on a public
 * per-segment leaderboard.
 *
 *   1. A curator-grade catalogue segment is planted directly (service
 *      role) — a straight 800 m line in rural Victoria, far from every
 *      seeded geometry so no other catalogue row matches the track.
 *   2. USER_A seeds a ROUTE-LESS run whose timed track traces that line at
 *      a constant 2.0 m/s → a deterministic 400 s (6:40) effort. No effort
 *      exists yet; the track is the only input.
 *   3. USER_A opens /runs/[id]. The Segments section renders even though
 *      route_id is null; RunSegmentEfforts walks the track via
 *      computeGlobalSegmentEffortsForRun (owner-match guard holds),
 *      INSERTs the catalogue effort, then renders the "Famous segments"
 *      chip → segment name, #1 gold pill, 6:40, linking to /segments/[id].
 *   4. Following that link, /segments/[id] shows the catalogue detail
 *      (name + distance) and the block-guarded leaderboard: USER_A alone,
 *      rank 1 (crown glyph), 6:40, the .viewer highlight on their own row.
 *   5. Backend cross-check: exactly one global_segment_efforts row,
 *      USER_A's, ~400 s.
 *
 * Teardown removes the run (+ its Storage track) and the catalogue segment
 * (cascades the effort via ON DELETE CASCADE).
 */

const uniq = (prefix: string) => `${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

const M_PER_DEG_LAT = 111_320;

function buildTrack(opts: {
	baseLat: number;
	lng: number;
	lengthM: number;
	stepM: number;
	speedMps: number;
	startedAtMs: number;
}): { lat: number; lng: number; ts: string }[] {
	const { baseLat, lng, lengthM, stepM, speedMps, startedAtMs } = opts;
	const pts: { lat: number; lng: number; ts: string }[] = [];
	for (let d = 0; d <= lengthM + 1e-6; d += stepM) {
		const lat = baseLat + d / M_PER_DEG_LAT;
		const ts = new Date(startedAtMs + (d / speedMps) * 1000).toISOString();
		pts.push({ lat, lng, ts });
	}
	return pts;
}

test.describe('global segment catalogue journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('route-less run backfills a catalogue effort → chip links to the segment detail leaderboard', async ({
		page
	}) => {
		const admin = getAdminClient();
		const segmentName = uniq('e2e-global-seg');

		const BASE_LAT = -37.5;
		const LNG = 144.5;
		const SEG_LEN_M = 800; // segment geometry length + stored distance_m
		const TRACK_LEN_M = 900; // track over-runs the segment end for a clean crossing
		const STEP_M = 20; // median step 20 m ≪ 800/5 = 160 m → sparsity guard passes
		const SPEED = 2.0; // 800 m / 2.0 m/s = 400 s → 6:40

		let segmentId = '';
		let runId = '';

		try {
			await test.step('a curator plants a free-standing catalogue segment', async () => {
				const { data, error } = await admin
					.from('global_segments')
					.insert({
						name: segmentName,
						description: 'Straight synthetic test line, rural Victoria.',
						waypoints: [
							{ lat: BASE_LAT, lng: LNG },
							{ lat: BASE_LAT + SEG_LEN_M / M_PER_DEG_LAT, lng: LNG }
						],
						distance_m: SEG_LEN_M,
						elevation_m: 12,
						surface: 'road',
						region: 'Rural Victoria, AU',
						country_code: 'AU'
					})
					.select('id')
					.single();
				if (error) throw error;
				segmentId = (data as { id: string }).id;
			});

			await test.step('USER_A seeds a route-less run tracing the segment line', async () => {
				runId = await insertRun({
					user_id: USER_A.id,
					started_at: '2026-05-01T08:00:00Z',
					duration_s: 900,
					distance_m: TRACK_LEN_M,
					is_public: true,
					// No route_id — this is the imported-run shape the catalogue exists for.
					track: buildTrack({
						baseLat: BASE_LAT,
						lng: LNG,
						lengthM: TRACK_LEN_M,
						stepM: STEP_M,
						speedMps: SPEED,
						startedAtMs: Date.parse('2026-05-01T08:00:00Z')
					})
				});

				const { data: pre } = await admin
					.from('global_segment_efforts')
					.select('id')
					.eq('global_segment_id', segmentId);
				expect(pre?.length ?? 0).toBe(0);
			});

			await test.step('opening /runs/[id] backfills the catalogue effort and renders the chip', async () => {
				await page.goto(`/runs/${runId}`);

				// The Segments section renders despite route_id being null.
				await expect(page.locator('section h2', { hasText: /^Segments$/ })).toBeVisible({
					timeout: 10_000
				});

				// Catalogue "Famous segments" chip links to /segments/[id].
				const row = page.locator(`.efforts a.effort-row[href="/segments/${segmentId}"]`);
				await expect(row).toBeVisible({ timeout: 15_000 });
				await expect(row.locator('.effort-meta strong')).toHaveText(segmentName);
				const goldPill = row.locator('.rank-pill.gold');
				await expect(goldPill).toBeVisible();
				await expect(goldPill).toHaveText('#1');
				await expect(row.locator('.time')).toHaveText('6:40');

				// Backend: exactly one catalogue effort, USER_A's, ~400 s.
				const { data: eff } = await admin
					.from('global_segment_efforts')
					.select('user_id, time_seconds')
					.eq('global_segment_id', segmentId);
				expect(eff?.length ?? 0).toBe(1);
				expect(eff?.[0]?.user_id).toBe(USER_A.id);
				expect(Math.round(Number(eff?.[0]?.time_seconds))).toBe(400);
			});

			await test.step('the chip navigates to the segment detail leaderboard', async () => {
				await page.locator(`.efforts a.effort-row[href="/segments/${segmentId}"]`).click();
				await page.waitForURL(`**/segments/${segmentId}`);

				// Detail header: name + distance stat.
				await expect(page.locator('h1', { hasText: segmentName })).toBeVisible({
					timeout: 10_000
				});
				await expect(page.locator('.key-stat-label', { hasText: 'Distance' })).toBeVisible();

				// Block-guarded leaderboard: USER_A alone, rank 1 (crown), 6:40.
				const rows = page.locator('.section ol li');
				await expect(rows).toHaveCount(1, { timeout: 10_000 });
				await expect(page.locator('.crown-banner')).toBeVisible();
				await expect(rows.nth(0)).toHaveClass(/viewer/);
				await expect(rows.nth(0).locator('.rank .crown-icon')).toBeVisible();
				await expect(rows.nth(0).locator('.time')).toHaveText('6:40');
				await expect(rows.nth(0).locator('a.athlete')).toHaveAttribute(
					'href',
					`/u/${USER_A.id}`
				);
			});
		} finally {
			if (runId) await deleteRun(runId).catch(() => {});
			// Catalogue delete cascades global_segment_efforts (ON DELETE CASCADE).
			if (segmentId) {
				await admin
					.from('global_segments')
					.delete()
					.eq('id', segmentId)
					.then(() => {})
					.catch(() => {});
			}
		}
	});
});
