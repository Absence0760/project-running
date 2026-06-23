import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertLivePings, insertRun, setUserSetting } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /live/[id] depth coverage — gaps the spectator.spec.ts suite leaves
 * open:
 *
 *   - the freshness / staleness display (live_freshness.ts): a runner
 *     who lost signal must read DELAYED with an honest "Updated N ago",
 *     NOT a permanently-fresh green LIVE dot. This is the spectator /
 *     SAR "is my person OK?" honesty contract and the ENTIRE reason
 *     the helper exists — yet spectator.spec.ts never plants a stale
 *     ping.
 *   - the same path's negative: a just-now ping stays LIVE, never
 *     DELAYED.
 *   - unit-localised distance: a mi-preference viewer sees the headline
 *     distance in miles, not km.
 *   - the finished-run boundary: a run whose saved end is just under
 *     the 2-minute slack still reads LIVE-ish (not finished), and one
 *     just over reads Finished.
 *
 * Pings carry an explicit `at` timestamp so the page's freshness clock
 * is deterministic — the simulate helper back-dates `at` by default,
 * which is exactly what we exploit to manufacture a stale ping.
 */

const OUT_OF_ZONE: Array<{ lat: number; lng: number }> = [
	{ lat: -37.816, lng: 144.97 },
	{ lat: -37.8175, lng: 144.972 },
	{ lat: -37.82, lng: 144.975 }
];

test.describe('/live/[id] — freshness / staleness (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a ping older than the stale window flips the badge to DELAYED, not LIVE', async ({
		page
	}) => {
		// LIVE_STALE_AFTER_MS is 90s. Plant a single ping stamped 5
		// minutes ago: pings EXIST (so status flips connecting → live)
		// but the last one is far past the stale threshold, so the
		// derived `isStale` must be true and the badge must show the
		// DELAYED treatment — the lost-signal-runner honesty contract.
		const startedAt = new Date(Date.now() - 30 * 60 * 1000).toISOString();
		const staleAt = new Date(Date.now() - 5 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 8_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [{ ...OUT_OF_ZONE[0], distance_m: 4_200, elapsed_s: 1_500, at: staleAt }]
			});

			await page.goto(`/live/${runId}`);

			const badge = page.locator('.live-badge');
			// status is 'live' (pings exist) but stale → the `.stale`
			// class, NOT `.active`.
			await expect(badge).toHaveClass(/stale/, { timeout: 10_000 });
			await expect(badge).not.toHaveClass(/active/);
			// Copy: the stale badge reads DELAYED (live.badgeStale), and
			// the LIVE word must NOT appear — a regression that kept the
			// LIVE label while stale would re-open the false-fresh bug.
			await expect(badge).toContainText(/DELAYED/i);
			await expect(badge).not.toContainText(/^LIVE$/);

			// The runner sub-line shows an honest age, not "Live from the
			// runner's device". 5 min ago → "Updated 5 min ago".
			await expect(page.locator('.live-runner-sub')).toContainText(
				/Updated 5 min ago/i
			);
			await expect(page.locator('.live-runner-sub')).not.toContainText(
				/Live from/i
			);
		} finally {
			await deleteRun(runId);
		}
	});

	test('a just-now ping keeps the badge LIVE (the non-stale control)', async ({ page }) => {
		// The companion to the stale test: a ping stamped ~now must keep
		// the badge in the fresh `.active` LIVE state and NOT trip the
		// stale path. Without this pin a bug that always-staled (or
		// always-freshed) would only be half-caught.
		const startedAt = new Date(Date.now() - 5 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{
						...OUT_OF_ZONE[0],
						distance_m: 1_200,
						elapsed_s: 300,
						at: new Date(Date.now() - 1_000).toISOString()
					}
				]
			});

			await page.goto(`/live/${runId}`);

			const badge = page.locator('.live-badge');
			await expect(badge).toHaveClass(/active/, { timeout: 10_000 });
			await expect(badge).not.toHaveClass(/stale/);
			await expect(badge).toContainText(/LIVE/);
			await expect(badge).not.toContainText(/DELAYED/i);
		} finally {
			await deleteRun(runId);
		}
	});

	test('the stale badge recomputes live: a fresh ping ages into DELAYED on the page clock', async ({
		page
	}) => {
		// The page runs a 1Hz `freshnessTicker` so the badge transitions
		// to DELAYED even while no new ping arrives. Plant a ping aged so
		// it is fresh on load but crosses the 90s stale boundary shortly
		// after — then assert the badge transitions WITHOUT a reload.
		// This pins the ticker, not just the initial render. Start it at
		// 80s old so it's still LIVE on first paint, then the +1s/tick
		// clock carries it past 90s within ~12s.
		const startedAt = new Date(Date.now() - 20 * 60 * 1000).toISOString();
		const freshish = new Date(Date.now() - 80 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 6_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [{ ...OUT_OF_ZONE[1], distance_m: 3_000, elapsed_s: 900, at: freshish }]
			});

			await page.goto(`/live/${runId}`);

			const badge = page.locator('.live-badge');
			// Fresh on first paint (80s < 90s).
			await expect(badge).toHaveClass(/active/, { timeout: 10_000 });
			// The once-a-second clock advances `nowMs`; the ping crosses
			// 90s and the derived isStale flips with no new data and no
			// reload. Generous timeout for the ~10s the clock needs.
			await expect(badge).toHaveClass(/stale/, { timeout: 20_000 });
			await expect(badge).toContainText(/DELAYED/i);
		} finally {
			await deleteRun(runId);
		}
	});
});

test.describe('/live/[id] — finished-run 2-minute boundary (anon)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a run whose saved end is just inside the 2-min slack is NOT treated as finished', async ({
		page
	}) => {
		// runIsFinished() treats a run finished only when its saved end
		// is >2 min in the past. A run that ended ~30s ago is inside the
		// slack, so the page must NOT show the Finished badge — it stays
		// on a live/connecting path. Boundary-pins the slack window so a
		// regression that dropped or widened it surfaces here.
		const duration = 1_800; // 30 min
		// Ended 30s ago → started 30:30 ago.
		const startedAt = new Date(Date.now() - (duration + 30) * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 5_000,
			duration_s: duration,
			is_public: true
		});
		try {
			await page.goto(`/live/${runId}`);
			const badge = page.locator('.live-badge');
			await expect(badge).toBeVisible();
			// Inside the slack — not finished.
			await expect(badge).not.toHaveClass(/finished/);
			await expect(page.locator('.live-runner-sub')).not.toContainText(
				/Run finished/i
			);
		} finally {
			await deleteRun(runId);
		}
	});

	test('a run whose saved end is just past the 2-min slack reads Finished with saved totals', async ({
		page
	}) => {
		// The other side of the boundary: ended ~3 min ago (> 2 min
		// slack) → Finished badge + the saved distance/elapsed frozen on
		// the strip, not a demo loop.
		const duration = 1_800; // 30 min → elapsed renders "30:00"
		const startedAt = new Date(
			Date.now() - (duration + 3 * 60) * 1000
		).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 7_500,
			duration_s: duration,
			is_public: true
		});
		try {
			await page.goto(`/live/${runId}`);
			const badge = page.locator('.live-badge');
			await expect(badge).toHaveClass(/finished/, { timeout: 10_000 });
			await expect(badge).toContainText(/Finished/i);
			await expect(page.locator('.live-runner-sub')).toContainText(
				/Run finished/i
			);
			// Saved totals frozen: 7.5 km / 30:00.
			await expect(page.locator('.live-stat-value').first()).toContainText('7.5');
			await expect(page.locator('.live-stat-value').nth(1)).toContainText('30:00');
		} finally {
			await deleteRun(runId);
		}
	});
});

test.describe('/live/[id] — mile-preference viewer sees miles (signed-in)', () => {
	// The headline distance honours the viewer's preferred_unit. An
	// anon viewer always reads km (no profile), so the mi path is only
	// reachable for a signed-in user whose profile says 'mi'.
	//
	// A real mi-preference user has the choice written at BOTH layers —
	// pickDistanceUnit on /settings/preferences dual-writes the universal
	// user_settings bag AND the legacy user_profiles column. The app
	// resolves the effective unit via effectivePreferredUnit, which reads
	// the universal bag FIRST (device → universal → column). The seed
	// pins runner's universal preferred_unit to 'km', so flipping only
	// the column leaves the universal 'km' winning and the live page
	// renders km — the auth-store setUnit('mi') from the column is
	// clobbered by the layout overlay applied on web startup (ff7ac686).
	// Stamp both layers so the test reflects a real mi user.
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeAll(async () => {
		await setUserSetting(USER_A.id, 'preferred_unit', 'mi');
		await getAdminClient()
			.from('user_profiles')
			.update({ preferred_unit: 'mi' })
			.eq('id', USER_A.id);
	});

	test.afterAll(async () => {
		await setUserSetting(USER_A.id, 'preferred_unit', 'km');
		await getAdminClient()
			.from('user_profiles')
			.update({ preferred_unit: 'km' })
			.eq('id', USER_A.id);
	});

	test('an in-progress run renders the headline distance in miles for a mi viewer', async ({
		page
	}) => {
		// 4828 m ≈ 3.00 mi. The km path would read "4.83 km", so the
		// "mi" suffix + the ~3.00 value is the unit-localisation pin.
		const startedAt = new Date(Date.now() - 5 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: USER_A.id,
			started_at: startedAt,
			distance_m: 9_000,
			duration_s: 3_600,
			is_public: true
		});
		try {
			await insertLivePings({
				run_id: runId,
				user_id: USER_A.id,
				points: [
					{
						...OUT_OF_ZONE[2],
						distance_m: 4_828,
						elapsed_s: 1_500,
						at: new Date(Date.now() - 2_000).toISOString()
					}
				]
			});

			await page.goto(`/live/${runId}`);

			await expect(page.locator('.live-badge')).toHaveClass(/active/, {
				timeout: 10_000
			});
			const distance = page.locator('.live-stat-value').first();
			await expect(distance).toContainText('mi');
			await expect(distance).toContainText('3.00');
			// Negative pin — the km label must not appear in the distance
			// tile for a mi viewer.
			await expect(distance).not.toContainText('km');
		} finally {
			await deleteRun(runId);
		}
	});
});
