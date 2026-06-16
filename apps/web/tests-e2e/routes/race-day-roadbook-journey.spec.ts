import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
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
 * Race-day roadbook — the full life of ONE race course threaded across
 * every surface a crew touches on the day, from the route's course
 * markers + cutoffs through the printable crew sheet to the live
 * spectator's next-cut-off ETA. Heavier than the single-surface specs it
 * leans on (routes/markers.spec.ts pins the course-schedule list,
 * routes/roadbook.spec.ts pins the crew table + cutoff verdict,
 * live/next_cutoff.spec.ts pins the spectator card), because it carries
 * ONE route id (and a derived live run) through:
 *
 *   1. SEED — a public race course with real geometry (a flat first half
 *      then a steep climb, so the effort model has terrain to bite on)
 *      plus two course markers: an aid station early and a cut-off gate
 *      at mid-course with a 30-min elapsed limit. Inserted via the
 *      service-role admin client (markers + position_m need the geom
 *      trigger; routes have no UI delete — markers.spec.ts/roadbook.spec.ts
 *      both seed this way). Backend cross-check: the route + its two
 *      markers exist and are owned by USER_A, with the gate carrying its
 *      cutoff_elapsed_s.
 *   2. ROUTE DETAIL — /routes/[id] renders the ordered course-schedule
 *      list (.markers-list): the gate (near start) sorts before the aid
 *      station (later), each with its kind label + detail line (the aid's
 *      Water/Food services).
 *   3. ROADBOOK (in-UI navigation) — the route-detail "Roadbook (crew
 *      sheet)" link carries the crew onto /routes/[id]/roadbook. With a
 *      deliberately slow 2h goal, the per-checkpoint schedule renders
 *      (start, Aid, Gate, finish) and the mid-course gate is flagged a
 *      MISS (red .cut-miss). Tightening the goal to 30 min clears the
 *      miss and the goal rides in the shareable URL.
 *   4. LIVE NEXT-CUT-OFF (the cross-surface payoff) — a public run is
 *      tied to this same public course and a fresh ping is planted ~20%
 *      along the line, leaving the gate ahead. An ANONYMOUS spectator
 *      opens /live/[id] and the Next-cut-off card names the gate and
 *      shows a real margin chip (a generous live limit ⇒ the green "on"
 *      treatment) — never a fabricated ETA. Same Supabase-Realtime
 *      transport live/next_cutoff.spec.ts uses, so this runs under the
 *      DEFAULT playwright.config.ts (NOT playwright.livehub.config.ts).
 *
 * Teardown removes the live run (its pings cascade) and the route (its
 * markers cascade) via the admin client in a finally block.
 *
 * Geometry note: the route-detail + roadbook half uses a London-area
 * climbing line (same shape roadbook.spec.ts uses, so the effort model
 * has vert), while the live half plants its position on a separate
 * due-east Melbourne line clear of the Sydney seed privacy zone (mirrors
 * next_cutoff.spec.ts) — the live_run_pings_drop_in_zone trigger would
 * otherwise silently drop an in-zone ping and the spectator would see no
 * position. The two halves are independent courses on purpose: the
 * route-detail/roadbook assertions don't depend on ping geometry, and
 * the live card needs its own out-of-zone line with a cutoff ahead.
 */

// London-area climbing course for the route-detail + roadbook half:
// flat first half, steep second half. ~0.001° lat ≈ 111 m.
const COURSE_WAYPOINTS: Array<{ lat: number; lng: number; elevation_m?: number }> = [];
for (let i = 0; i <= 18; i++) {
	COURSE_WAYPOINTS.push({
		lat: 51.5 + i * 0.001,
		lng: -0.12,
		elevation_m: i > 9 ? (i - 9) * 30 : 0
	});
}

// Melbourne due-east line for the live half (well clear of the Sydney
// seed's 200 m privacy zone). The cutoff sits ~90% along; the runner's
// latest ping ~20% along, so a cutoff is always ahead.
const LIVE_WAYPOINTS = [
	{ lat: -37.8, lng: 144.95 },
	{ lat: -37.8, lng: 145.0 }
];
const RUNNER_NEAR_START = { lat: -37.8, lng: 144.96 };
const CUTOFF_NEAR_END = { lat: -37.8, lng: 144.99 };

test.describe('Race-day roadbook — markers → crew sheet → live next cut-off', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		// Keep the GDPR banner from floating over the map / share surfaces
		// and eating a click (same pattern as the other route specs).
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('a course with cut-offs produces a crew roadbook and a live next-cut-off ETA', async ({
		page,
		browser
	}) => {
		const admin = getAdminClient();

		let courseId = '';
		let liveRouteId = '';
		let runId = '';

		// The anon spectator runs in its own logged-out context.
		const spectatorCtx = await browser.newContext({
			storageState: { cookies: [], origins: [] }
		});
		await spectatorCtx.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		const spectator = await spectatorCtx.newPage();

		try {
			// ── 1. Seed the public race course + its two course markers ──
			await test.step('seed a public course with an aid station and a mid-course cut-off gate', async () => {
				courseId = await insertRoute({
					user_id: USER_A.id,
					name: `E2E race-day course ${Date.now()}`,
					waypoints: COURSE_WAYPOINTS,
					distance_m: 2000,
					is_public: true
				});

				// Aid station early (position_m small), cut-off gate mid-course
				// with a 30-min elapsed limit. position_m is derived from geom
				// by the route_markers_position_trigger.
				await insertRouteMarker({
					route_id: courseId,
					user_id: USER_A.id,
					kind: 'aid_station',
					label: 'Aid 1',
					lat: 51.5 + 4 * 0.001,
					lng: -0.12,
					meta: { services: ['water', 'food'] }
				});
				await insertRouteMarker({
					route_id: courseId,
					user_id: USER_A.id,
					kind: 'cutoff',
					label: 'Gate',
					lat: 51.5 + 9 * 0.001,
					lng: -0.12,
					meta: { cutoff_elapsed_s: 1800 }
				});

				// Backend cross-check: route owned by USER_A + public, and both
				// markers landed with the gate carrying its cutoff limit.
				const { data: routeRow } = await admin
					.from('routes')
					.select('user_id, is_public')
					.eq('id', courseId)
					.single();
				expect(routeRow?.user_id).toBe(USER_A.id);
				expect(routeRow?.is_public).toBe(true);

				const { data: markers } = await admin
					.from('route_markers')
					.select('kind, label, meta')
					.eq('route_id', courseId)
					.order('kind');
				expect(markers).toHaveLength(2);
				const gate = markers?.find((row) => row.kind === 'cutoff');
				expect((gate?.meta as { cutoff_elapsed_s?: number } | null)?.cutoff_elapsed_s).toBe(1800);
			});

			// ── 2. Route detail renders the ordered course schedule ──────
			await test.step('the route-detail course schedule lists the gate before the aid station', async () => {
				await page.goto(`/routes/${courseId}`);

				const list = page.locator('.markers-list');
				await expect(list).toBeVisible({ timeout: 10_000 });
				const rows = list.locator('.marker-row');
				await expect(rows).toHaveCount(2);

				// Distance ordering: schedule sorts by position_m ascending,
				// so the aid (4/18 along) comes before the gate (9/18 along).
				await expect(rows.nth(0).locator('.marker-label')).toHaveText('Aid 1');
				await expect(rows.nth(1).locator('.marker-label')).toHaveText('Gate');

				await expect(rows.nth(0).locator('.marker-kind')).toHaveText('Aid station');
				await expect(rows.nth(0).locator('.marker-detail')).toContainText('Water');
				await expect(rows.nth(0).locator('.marker-detail')).toContainText('Food');
				await expect(rows.nth(1).locator('.marker-kind')).toHaveText('Cut-off');
			});

			// ── 3. Crew roadbook via the in-UI route-detail link ─────────
			await test.step('the route-detail Roadbook link opens the crew sheet with a missed cut-off at a slow goal', async () => {
				// Thread through the real UI: the route-detail page carries a
				// "Roadbook (crew sheet)" link onto the roadbook surface.
				const roadbookLink = page.locator('a.roadbook-link');
				await expect(roadbookLink).toBeVisible({ timeout: 10_000 });
				await roadbookLink.click();
				await expect(page).toHaveURL(new RegExp(`/routes/${courseId}/roadbook`));

				// Set a deliberately slow 2h goal so the 30-min gate is a miss.
				await page.goto(`/routes/${courseId}/roadbook?goal=7200&start=06:00&model=even`);

				const rows = page.locator('.rb-table tbody tr');
				// start, Aid 1, Gate, finish.
				await expect(rows).toHaveCount(4, { timeout: 10_000 });
				await expect(rows.nth(1)).toContainText('Aid 1');
				await expect(rows.nth(1)).toContainText('Water');
				await expect(rows.nth(2)).toContainText('Gate');

				// The cut-off at the slow goal is flagged a MISS (red chip).
				await expect(rows.nth(2).locator('.cut-miss')).toBeVisible();

				// Tighten the goal to 30 min → the gate is no longer a miss, and
				// the new goal rides in the shareable URL.
				await page.getByLabel('Goal time').fill('0:30:00');
				await page.getByLabel('Goal time').blur();
				await expect(page).toHaveURL(/goal=1800/);
				await expect(rows.nth(2).locator('.cut-miss')).toHaveCount(0);
			});

			// ── 4. Live spectator sees the next cut-off ahead ────────────
			await test.step('a live run on a public course gives an anonymous spectator a next-cut-off ETA', async () => {
				// Build a SEPARATE out-of-zone public course for the live half
				// (the route-detail course is in a Sydney-seed-zone-free London
				// area, but the live pings need the Melbourne due-east line so
				// the position-drop trigger doesn't eat them, and a cutoff that
				// sits ahead of the planted fix).
				liveRouteId = await insertRoute({
					user_id: USER_A.id,
					name: `E2E race-day live course ${Date.now()}`,
					waypoints: LIVE_WAYPOINTS,
					distance_m: 4_400,
					is_public: true
				});
				await insertRouteMarker({
					route_id: liveRouteId,
					user_id: USER_A.id,
					kind: 'cutoff',
					label: 'Final gate',
					lat: CUTOFF_NEAR_END.lat,
					lng: CUTOFF_NEAR_END.lng,
					// Generous live limit so a normally-paced runner reads "on".
					meta: { cutoff_elapsed_s: 7_200 }
				});

				runId = await insertRun({
					user_id: USER_A.id,
					started_at: new Date(Date.now() - 12 * 60 * 1000).toISOString(),
					distance_m: 4_400,
					duration_s: 3_600,
					is_public: true,
					route_id: liveRouteId
				});

				// Two recent pings give a real recent-pace delta (200 m / 60 s);
				// the latest fix sits ~20% along, leaving the cutoff (~90%)
				// ahead. Default-config Supabase Realtime path (no live hub).
				await insertLivePings({
					run_id: runId,
					user_id: USER_A.id,
					points: [
						{ ...RUNNER_NEAR_START, distance_m: 700, elapsed_s: 540 },
						{ ...RUNNER_NEAR_START, distance_m: 900, elapsed_s: 600 }
					]
				});

				await spectator.goto(`/live/${runId}`);

				const card = spectator.locator('.cutoff-card');
				await expect(card).toBeVisible({ timeout: 10_000 });
				await expect(card.locator('.cutoff-checkpoint')).toHaveText('Final gate');
				// A real verdict: the margin chip is present (NOT the
				// waiting/unknown copy), with the green "on" treatment.
				await expect(card.locator('.cutoff-chip')).toBeVisible();
				await expect(card.locator('.cutoff-waiting')).toHaveCount(0);
				await expect(card).toHaveClass(/on/);
			});
		} finally {
			await spectatorCtx.close();
			// deleteRun sweeps the run (live_run_pings cascade via FK);
			// deleteRoute sweeps each route (route_markers cascade).
			if (runId) {
				await deleteRun(runId);
			}
			for (const id of [liveRouteId, courseId]) {
				if (id) {
					try {
						await deleteRoute(id);
					} catch (_) {
						/* cascade clears markers; best-effort */
					}
				}
			}
		}
	});
});
