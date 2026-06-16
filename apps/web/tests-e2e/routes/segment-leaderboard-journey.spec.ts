import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRoute, insertRun, deleteRoute, deleteRun } from '../fixtures/simulate';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Segment-leaderboard journey — one segment on a saved route, threaded
 * through the two seams that turn a raw GPS track into a ranked
 * leaderboard. Heavier than routes/segments.spec.ts (which seeds the
 * segment_efforts rows directly and asserts one surface) because it
 * exercises the *auto-effort generation* pipeline end-to-end: a run's
 * track is walked client-side on the owner's run-detail page, an effort
 * is INSERTed, the per-run chip renders it, and the route's
 * SegmentsPanel ranks it against a second user's faster effort.
 *
 *   1. USER_A creates a PUBLIC route + a segment on it (service-role
 *      setup — neither is the test subject). The segment spans
 *      distance-along-route 200 m → 1000 m.
 *   2. USER_A seeds a run linked to that route whose gzipped track (with
 *      per-point timestamps) covers the segment window, traversing the
 *      800 m at a constant ~2.0 m/s so the interpolated effort time is a
 *      deterministic 400 s. No effort exists yet — the track is the only
 *      input.
 *   3. USER_A opens /runs/[id]. RunSegmentEfforts mounts, walks the
 *      track via computeSegmentEffortsForRun (auth.user must equal the
 *      run owner — it does), INSERTs USER_A's effort, then renders the
 *      effort chip: segment name + #1 .gold rank pill + 6:40 time. This
 *      is the auto-generation seam — the effort is born here, not seeded.
 *   4. /routes/[id] SegmentsPanel: open the segment → USER_A sits alone
 *      on the leaderboard as the crown holder (.crown-banner + the rank-1
 *      crown glyph + the .viewer highlight on USER_A's own row).
 *   5. USER_C_PRO (second browser context) seeds a FASTER run over the
 *      same route+segment (800 m at ~2.5 m/s → 320 s) and opens THEIR own
 *      /runs/[id]. Their RunSegmentEfforts generates USER_C's effort the
 *      same way (the owner-match guard means each user generates only
 *      their own effort, on their own detail page).
 *   6. Back as USER_A, /routes/[id] re-ranks: USER_C is now rank 1 (crown
 *      + 5:20) and USER_A drops to rank 2 (6:40). USER_A no longer holds
 *      the crown — the .crown-banner is gone, and the .viewer row is the
 *      rank-2 row. Backend cross-check: exactly two segment_efforts rows,
 *      USER_C's time strictly less than USER_A's.
 *
 * Teardown removes the route (cascades the segment → segment_efforts via
 * ON DELETE CASCADE) plus both runs and their Storage tracks.
 */

const uniq = (prefix: string) => `${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

// One degree of latitude ≈ this many metres (close enough for a synthetic
// straight-line test track at the latitudes used here).
const M_PER_DEG_LAT = 111_320;

/**
 * Build a straight, due-north test track of `lengthM` total length,
 * sampled every `stepM` metres, starting at `startedAtMs` and advancing
 * the per-point timestamp so the runner holds a constant `speedMps`.
 *
 * The auto-effort compute (segments.ts#computeEffortFromTrack) walks the
 * track's OWN cumulative haversine distance against the segment's
 * (start_distance_m, end_distance_m) — it does not require the track to
 * geometrically trace the saved route — so a clean straight line whose
 * length comfortably exceeds end_distance_m yields a deterministic
 * effort time of (end - start) / speed. stepM is kept far below
 * segLen / 5 so the sparsity guard passes.
 */
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

test.describe('segment leaderboard journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('segment + auto-generated efforts → per-run chip → ranked leaderboard re-orders on a faster effort', async ({
		page,
		browser
	}) => {
		const admin = getAdminClient();
		const routeName = uniq('e2e-seg-journey-route');
		const segmentName = uniq('e2e-seg-journey-seg');

		// Segment window along the route. 200 m → 1000 m (800 m span,
		// clears the ≥100 m CHECK). The track is 1200 m so cumulative
		// distance comfortably reaches the 1000 m end crossing.
		const SEG_START_M = 200;
		const SEG_END_M = 1000;
		const SEG_SPAN_M = SEG_END_M - SEG_START_M; // 800 m

		// USER_A: 800 m at 2.0 m/s → 400 s effort → 6:40.
		// USER_C: 800 m at 2.5 m/s → 320 s effort → 5:20 (strictly faster).
		const A_SPEED = 2.0;
		const C_SPEED = 2.5;
		const A_EFFORT_S = SEG_SPAN_M / A_SPEED; // 400
		const C_EFFORT_S = SEG_SPAN_M / C_SPEED; // 320

		// Rural Victoria, well clear of any seeded CBD privacy zone (which
		// only affects live pings anyway, not a stored run track).
		const BASE_LAT = -37.5;
		const LNG = 144.5;
		const TRACK_LEN_M = 1200;
		const STEP_M = 20; // median step 20 m ≪ 800/5 = 160 m → sparsity guard passes

		let routeId = '';
		let runAId = '';
		let runCId = '';
		let segmentId = '';

		try {
			// ── 1. USER_A creates a public route + a segment on it ──────
			await test.step('USER_A plants a public route with a segment', async () => {
				routeId = await insertRoute({
					user_id: USER_A.id,
					name: routeName,
					// Two waypoints are enough for the route row; the segment's
					// effort window is resolved off the run track, not these.
					waypoints: [
						{ lat: BASE_LAT, lng: LNG },
						{ lat: BASE_LAT + TRACK_LEN_M / M_PER_DEG_LAT, lng: LNG }
					],
					distance_m: TRACK_LEN_M,
					is_public: true
				});

				const { data: segRow, error: segErr } = await admin
					.from('segments')
					.insert({
						route_id: routeId,
						name: segmentName,
						start_distance_m: SEG_START_M,
						end_distance_m: SEG_END_M,
						author_id: USER_A.id
					})
					.select('id')
					.single();
				if (segErr) throw segErr;
				segmentId = (segRow as { id: string }).id;
			});

			// ── 2. USER_A seeds a route-linked run with a timed track ───
			await test.step('USER_A seeds a route-linked run whose track covers the segment', async () => {
				runAId = await insertRun({
					user_id: USER_A.id,
					started_at: '2026-04-20T08:00:00Z',
					duration_s: 1200,
					distance_m: TRACK_LEN_M,
					is_public: true,
					route_id: routeId,
					track: buildTrack({
						baseLat: BASE_LAT,
						lng: LNG,
						lengthM: TRACK_LEN_M,
						stepM: STEP_M,
						speedMps: A_SPEED,
						startedAtMs: Date.parse('2026-04-20T08:00:00Z')
					})
				});

				// No effort exists yet — the track is the only input.
				const { data: pre } = await admin
					.from('segment_efforts')
					.select('id')
					.eq('segment_id', segmentId);
				expect(pre?.length ?? 0).toBe(0);
			});

			// ── 3. /runs/[id] auto-generates USER_A's effort + chip ─────
			await test.step('opening /runs/[id] auto-generates the effort and renders the chip', async () => {
				await page.goto(`/runs/${runAId}`);

				// RunSegmentEfforts mounts inside the Segments section (gated
				// on run.route_id) and walks the track on mount. The first
				// pass INSERTs the effort, then re-fetches and renders it.
				await expect(
					page.locator('section h2', { hasText: /^Segments$/ })
				).toBeVisible({ timeout: 10_000 });

				// The chip: segment name + rank-1 .gold pill + 6:40 time.
				const row = page.locator('.efforts li .effort-row').first();
				await expect(row).toBeVisible({ timeout: 15_000 });
				await expect(row.locator('.effort-meta strong')).toHaveText(segmentName);
				const goldPill = row.locator('.rank-pill.gold');
				await expect(goldPill).toBeVisible();
				await expect(goldPill).toHaveText('#1');
				// 400 s → 6:40 (formatDuration mm:ss for sub-1h).
				await expect(row.locator('.time')).toHaveText('6:40');

				// The row links to the route's leaderboard anchor.
				await expect(
					page.locator(
						`.efforts a.effort-row[href="/routes/${routeId}#segment-${segmentId}"]`
					)
				).toBeVisible();

				// Backend: exactly one effort now exists, USER_A's, ~400 s.
				const { data: eff } = await admin
					.from('segment_efforts')
					.select('user_id, time_seconds')
					.eq('segment_id', segmentId);
				expect(eff?.length ?? 0).toBe(1);
				expect(eff?.[0]?.user_id).toBe(USER_A.id);
				expect(Math.round(Number(eff?.[0]?.time_seconds))).toBe(A_EFFORT_S);
			});

			// ── 4. /routes/[id] leaderboard: USER_A holds the crown ─────
			await test.step('SegmentsPanel ranks USER_A alone as the crown holder', async () => {
				await page.goto(`/routes/${routeId}`);
				await expect(page.locator('.segments-panel')).toBeVisible({
					timeout: 10_000
				});
				await page.locator('.seg-row', { hasText: segmentName }).click();

				const rows = page.locator('.seg.open .leaderboard ol li');
				await expect(rows).toHaveCount(1, { timeout: 10_000 });
				// Caller holds rank 1 → crown banner + the .viewer highlight on
				// the only row.
				await expect(page.locator('.crown-banner')).toBeVisible();
				await expect(rows.nth(0)).toHaveClass(/viewer/);
				await expect(rows.nth(0).locator('.time')).toHaveText('6:40');
				// Rank-1 renders the crown glyph (emoji_events) instead of "#1".
				await expect(rows.nth(0).locator('.rank .crown-icon')).toBeVisible();
			});

			// ── 5. USER_C_PRO records a FASTER run + generates its effort ─
			await test.step('USER_C_PRO seeds a faster run and generates their own effort', async () => {
				runCId = await insertRun({
					user_id: USER_C_PRO.id,
					started_at: '2026-04-21T08:00:00Z',
					duration_s: 1100,
					distance_m: TRACK_LEN_M,
					is_public: true,
					route_id: routeId,
					track: buildTrack({
						baseLat: BASE_LAT,
						lng: LNG,
						lengthM: TRACK_LEN_M,
						stepM: STEP_M,
						speedMps: C_SPEED,
						startedAtMs: Date.parse('2026-04-21T08:00:00Z')
					})
				});

				const ctx = await browser.newContext({
					storageState: USER_C_PRO.storageStatePath
				});
				const guestPage = await ctx.newPage();
				try {
					await guestPage.addInitScript(() => {
						localStorage.setItem(
							'cookie_consent',
							JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
						);
					});
					await guestPage.goto(`/runs/${runCId}`);

					// USER_C's RunSegmentEfforts generates USER_C's effort
					// (the owner-match guard means C can only write C's effort,
					// on C's own detail page). Wait for the chip → 5:20.
					const cRow = guestPage.locator('.efforts li .effort-row').first();
					await expect(cRow).toBeVisible({ timeout: 15_000 });
					await expect(cRow.locator('.time')).toHaveText('5:20');
				} finally {
					await ctx.close();
				}

				// Backend: two efforts now, C strictly faster than A.
				const { data: eff } = await admin
					.from('segment_efforts')
					.select('user_id, time_seconds')
					.eq('segment_id', segmentId);
				expect(eff?.length ?? 0).toBe(2);
				const byUser = new Map(
					(eff ?? []).map((e) => [e.user_id, Number(e.time_seconds)])
				);
				expect(Math.round(byUser.get(USER_C_PRO.id)!)).toBe(C_EFFORT_S);
				expect(byUser.get(USER_C_PRO.id)!).toBeLessThan(byUser.get(USER_A.id)!);
			});

			// ── 6. Leaderboard re-ranks: C ahead of A ───────────────────
			await test.step('the leaderboard re-ranks with USER_C ahead of USER_A', async () => {
				await page.goto(`/routes/${routeId}`);
				await page.locator('.seg-row', { hasText: segmentName }).click();

				const rows = page.locator('.seg.open .leaderboard ol li');
				await expect(rows).toHaveCount(2, { timeout: 10_000 });
				// Ordered by time ascending: C (5:20) then A (6:40).
				await expect(rows.nth(0).locator('.time')).toHaveText('5:20');
				await expect(rows.nth(1).locator('.time')).toHaveText('6:40');
				// Rank-1 is USER_C (the crown glyph row); rank-2 is the caller.
				await expect(rows.nth(0).locator('.rank .crown-icon')).toBeVisible();
				await expect(rows.nth(0).locator('a.athlete')).toHaveAttribute(
					'href',
					`/u/${USER_C_PRO.id}`
				);
				// USER_A no longer holds the crown → banner gone; the .viewer
				// highlight is now on the rank-2 row.
				await expect(page.locator('.crown-banner')).toHaveCount(0);
				await expect(rows.nth(0)).not.toHaveClass(/viewer/);
				await expect(rows.nth(1)).toHaveClass(/viewer/);
				await expect(rows.nth(1).locator('a.athlete')).toHaveAttribute(
					'href',
					`/u/${USER_A.id}`
				);
			});
		} finally {
			// Route delete cascades segment → segment_efforts (ON DELETE
			// CASCADE). Runs (+ their Storage tracks) are swept explicitly.
			if (runAId) await deleteRun(runAId).catch(() => {});
			if (runCId) await deleteRun(runCId).catch(() => {});
			if (routeId) await deleteRoute(routeId).catch(() => {});
		}
	});
});
