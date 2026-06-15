import { expect, test } from '@playwright/test';

import {
	deleteRoute,
	deleteRun,
	insertLivePings,
	insertRoute,
	insertRouteMarker,
	insertRun
} from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /live/[id] — the "Next cut-off" card (predictive-live-tracking item 3).
 *
 * The spectator sees the next cutoff ahead on the linked PUBLIC route plus a
 * margin verdict projected from the runner's live position + recent pace. The
 * two cases that matter:
 *
 *   1. Fresh pings + a cutoff ahead → the card renders with a coloured margin
 *      chip ("on pace" / ahead).
 *   2. Stale pings → the verdict is SUPPRESSED (the `unknown` path): the card
 *      still names the checkpoint + distance, but shows the muted
 *      "waiting for a fresh signal" line and NO chip. This is the staleness-
 *      honesty contract — never a fabricated ETA off an old fix.
 *
 * Geometry: a due-east two-point line at lat -37.80 (Melbourne, well clear of
 * the Sydney seed privacy zone). The cutoff marker sits ~90% along; the
 * runner's latest ping sits ~20% along, so a cutoff is always ahead. The
 * cutoff limit rides in meta.cutoff_elapsed_s so the verdict is independent of
 * the start clock / timezone.
 */

const ROUTE_WAYPOINTS = [
	{ lat: -37.8, lng: 144.95 },
	{ lat: -37.8, lng: 145.0 }
];
// ~20% along the line — leaves a cutoff (placed near the end) ahead.
const RUNNER_NEAR_START = { lat: -37.8, lng: 144.96 };
// ~90% along — the cutoff sits here.
const CUTOFF_NEAR_END = { lat: -37.8, lng: 144.99 };

async function seedCourse(opts: { publicRoute: boolean }): Promise<{
	routeId: string;
	cleanup: () => Promise<void>;
}> {
	const routeId = await insertRoute({
		user_id: USER_A.id,
		name: 'E2E cut-off course',
		waypoints: ROUTE_WAYPOINTS,
		distance_m: 4_400,
		is_public: opts.publicRoute
	});
	await insertRouteMarker({
		route_id: routeId,
		user_id: USER_A.id,
		kind: 'cutoff',
		label: 'Final gate',
		lat: CUTOFF_NEAR_END.lat,
		lng: CUTOFF_NEAR_END.lng,
		// Generous limit so a normally-paced runner reads "on pace" (green).
		meta: { cutoff_elapsed_s: 7_200 }
	});
	return {
		routeId,
		cleanup: async () => {
			try {
				await deleteRoute(routeId); // cascade clears route_markers
			} catch (_) {
				/* best-effort */
			}
		}
	};
}

test.describe('/live/[id] — Next cut-off card (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('fresh pings + cutoff ahead → card + margin chip render', async ({ page }) => {
		const { routeId, cleanup } = await seedCourse({ publicRoute: true });
		const startedAt = new Date(Date.now() - 12 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 4_400,
			duration_s: 3_600,
			is_public: true,
			route_id: routeId
		});
		try {
			// Two recent pings give the page a real recent-pace delta
			// (200 m over 60 s ≈ 5:00 /km). The latest fix sits ~20%
			// along the line, leaving the cutoff (~90%) ahead.
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ ...RUNNER_NEAR_START, distance_m: 700, elapsed_s: 540 },
					{ ...RUNNER_NEAR_START, distance_m: 900, elapsed_s: 600 }
				]
			});

			await page.goto(`/live/${runId}`);

			const card = page.locator('.cutoff-card');
			await expect(card).toBeVisible({ timeout: 10_000 });
			await expect(card.locator('.cutoff-checkpoint')).toHaveText('Final gate');
			// A real verdict: the margin chip is present (and NOT the
			// waiting/unknown copy).
			await expect(card.locator('.cutoff-chip')).toBeVisible();
			await expect(card.locator('.cutoff-waiting')).toHaveCount(0);
			// Generous cutoff + normal pace ⇒ "on pace" green treatment.
			await expect(card).toHaveClass(/on/);
		} finally {
			await deleteRun(runId);
			await cleanup();
		}
	});

	test('stale pings → checkpoint shows but the verdict/chip is suppressed', async ({ page }) => {
		const { routeId, cleanup } = await seedCourse({ publicRoute: true });
		const startedAt = new Date(Date.now() - 30 * 60 * 1000).toISOString();
		const staleAt = new Date(Date.now() - 5 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 4_400,
			duration_s: 3_600,
			is_public: true,
			route_id: routeId
		});
		try {
			// A single ping stamped 5 minutes ago — past the 90 s stale
			// window, so the page's isStale is true and nextCutoffEta
			// returns status 'unknown'. The card must NOT fabricate an ETA.
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [{ ...RUNNER_NEAR_START, distance_m: 900, elapsed_s: 600, at: staleAt }]
			});

			await page.goto(`/live/${runId}`);

			const card = page.locator('.cutoff-card');
			await expect(card).toBeVisible({ timeout: 10_000 });
			// Checkpoint name still shown — the spectator knows what's next.
			await expect(card.locator('.cutoff-checkpoint')).toHaveText('Final gate');
			// Honesty contract: no chip, the muted waiting line instead.
			await expect(card.locator('.cutoff-waiting')).toBeVisible();
			await expect(card.locator('.cutoff-chip')).toHaveCount(0);
			await expect(card.locator('.cutoff-eta')).toHaveCount(0);
		} finally {
			await deleteRun(runId);
			await cleanup();
		}
	});

	test('private linked route → no cut-off card (route_id is nulled by the view)', async ({
		page
	}) => {
		// public_runs nulls route_id when the linked route isn't public,
		// so a public run on a PRIVATE route must not surface the card —
		// the course (and its cutoffs) stay private to the owner.
		const { routeId, cleanup } = await seedCourse({ publicRoute: false });
		const startedAt = new Date(Date.now() - 12 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 4_400,
			duration_s: 3_600,
			is_public: true,
			route_id: routeId
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{ ...RUNNER_NEAR_START, distance_m: 700, elapsed_s: 540 },
					{ ...RUNNER_NEAR_START, distance_m: 900, elapsed_s: 600 }
				]
			});

			await page.goto(`/live/${runId}`);

			// The stat strip mounts (proves the page loaded), but no card.
			await expect(page.locator('.live-stat-label')).toHaveCount(3);
			await expect(page.locator('.cutoff-card')).toHaveCount(0);
		} finally {
			await deleteRun(runId);
			await cleanup();
		}
	});
});
