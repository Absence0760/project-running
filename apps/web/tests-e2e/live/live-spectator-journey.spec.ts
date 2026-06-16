import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { switchRunsToAllTime } from '../fixtures/helpers';
import { deleteRun, insertLivePings, insertRun } from '../fixtures/simulate';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Live-tracking journey — the full life of ONE live broadcast threaded
 * through every surface it touches, from the owner's in-progress run to
 * an anonymous spectator's public `/live/[id]` link to the finished,
 * normal completed run. Heavier than live/spectator.spec.ts's per-state
 * pins and live/spectator-depth.spec.ts's freshness-boundary pins
 * because it carries a single run id from broadcasting → fresh-spectator
 * → stale-spectator → finished → /runs row, exercising the SEAMS
 * between those surfaces (the same row's `started_at` + `duration_s`
 * being mutated by the recorder's final post is what flips
 * `runIsFinished`, the same pings that read LIVE age into DELAYED, the
 * same row that the owner then sees on /runs).
 *
 *   1. USER_A "starts" a live run — insertRun seeds the in-progress row
 *      the way the mobile recorder's first sync does (web can't record,
 *      decisions §24). started_at ~5 min ago + a long duration so the
 *      page does NOT treat it as already-finished (runIsFinished needs
 *      end > 2 min in the past). Backend cross-check: the row is public
 *      and owned by USER_A.
 *   2. A position update lands — insertLivePings plants the recorder's
 *      backlog on the Supabase Realtime path (the default-config
 *      transport; PUBLIC_LIVE_HUB_URL is unset so the page uses the
 *      `live_run_pings` postgres_changes channel, NOT the Go hub).
 *   3. An ANONYMOUS spectator (second browser context, logged-out)
 *      opens /live/[id] and sees a FRESH position: the `.active` LIVE
 *      badge, the runner's anonymised handle (anon viewers never see
 *      the display_name — privacy contract), and the planted distance /
 *      elapsed totals on the stat strip. The freshness sub-line reads
 *      "Updated …", proving the page consumed the ping's `at` clock.
 *   4. A LIVE position update is pushed while the spectator page is
 *      already open — a fresh admin-client INSERT into live_run_pings,
 *      which the page's realtime subscription receives and renders
 *      without a reload. The stat strip advances to the new totals.
 *   5. Signal drops: the runner's last ping ages past
 *      LIVE_STALE_AFTER_MS (90 s). We manufacture the gap by planting a
 *      ping stamped 5 min ago and reloading the spectator — the badge
 *      flips to `.stale` / DELAYED and the sub-line shows an honest
 *      "Updated 5 min ago", NOT a permanently-fresh LIVE dot. This is
 *      the spectator / SAR "is my person OK?" honesty contract.
 *   6. The run finishes — the recorder posts final totals, modelled as
 *      an admin-client UPDATE that moves the SAME row's computed end
 *      (started_at + duration_s) to > 2 min in the past. The spectator
 *      A final live_run_pings row carrying the completed odometer
 *      (7.5 km / 30:00) is posted too, the way a real recorder's last
 *      sync posts both the row and the final position — the
 *      finished-state path replays the ping backlog to rebuild the map
 *      trace, so the final ping must agree with the saved totals or
 *      pushPing() would clobber the strip back to the last live value.
 *      The spectator reloads and the badge reads `.finished` / Finished
 *      with the frozen saved totals and a "Run finished" sub-line.
 *   7. It's now a normal completed run: USER_A's /runs list shows the
 *      row, and /runs/[id] mounts as an ordinary run detail. Backend
 *      cross-check confirms the run is the same id throughout.
 *
 * Default-config safe: this spec uses ONLY the Supabase Realtime
 * transport (insertLivePings + a raw live_run_pings INSERT), the same
 * path live/spectator.spec.ts + live/spectator-depth.spec.ts run under
 * the default playwright.config.ts. It does NOT need
 * playwright.livehub.config.ts — that config is only for
 * live/spectator_websocket.spec.ts, which boots the real Go hub binary.
 */

// Melbourne CBD-adjacent coordinates, clear of the seed's 200 m privacy
// zone around runner's home — the live_run_pings_drop_in_zone
// BEFORE-INSERT trigger would silently drop in-zone points and the
// spectator would never see a position (see simulate.insertLivePings).
const OUT_OF_ZONE: Array<{ lat: number; lng: number }> = [
	{ lat: -37.816, lng: 144.97 },
	{ lat: -37.8175, lng: 144.972 },
	{ lat: -37.82, lng: 144.975 },
	{ lat: -37.8225, lng: 144.978 }
];

test.describe('live-tracking journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('start live → anon spectator sees fresh → live update → goes stale → finishes → normal completed run', async ({
		page,
		browser
	}) => {
		const admin = getAdminClient();

		// One run id threaded through every surface; also drives teardown.
		let runId = '';
		// The anon spectator runs in its own logged-out context.
		const spectatorCtx = await browser.newContext({
			storageState: { cookies: [], origins: [] }
		});
		const spectator = await spectatorCtx.newPage();

		try {
			// ── 1. USER_A starts a live broadcast ───────────────────────
			await test.step('USER_A starts a public live run', async () => {
				// started_at 5 min ago, duration 60 min → end is ~55 min in
				// the FUTURE, so runIsFinished() is false and the page treats
				// the run as in-progress, not a stale finished link.
				runId = await insertRun({
					user_id: USER_A.id,
					started_at: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
					distance_m: 10_000,
					duration_s: 3_600,
					is_public: true
				});

				const { data: row } = await admin
					.from('runs')
					.select('user_id, is_public')
					.eq('id', runId)
					.single();
				expect(row?.user_id).toBe(USER_A.id);
				expect(row?.is_public).toBe(true);
			});

			// ── 2. A position update lands (the recorder's backlog) ─────
			await test.step('the recorder pushes a position backlog', async () => {
				await insertLivePings({
					run_id: runId,
					user_id: USER_A.id,
					points: [
						{
							...OUT_OF_ZONE[0],
							distance_m: 2_000,
							elapsed_s: 600,
							// Fresh — stamped ~now so the spectator reads LIVE,
							// not DELAYED, on first paint.
							at: new Date(Date.now() - 2_000).toISOString()
						},
						{
							...OUT_OF_ZONE[1],
							distance_m: 3_500,
							elapsed_s: 1_050,
							at: new Date(Date.now() - 1_000).toISOString()
						}
					]
				});
			});

			// ── 3. Anon spectator opens /live/[id] and sees FRESH ───────
			await test.step('an anonymous spectator sees a fresh LIVE position', async () => {
				await spectator.goto(`/live/${runId}`);

				// Pings exist + the newest is fresh → the green LIVE badge.
				await expect(spectator.locator('.live-badge')).toHaveClass(/active/, {
					timeout: 10_000
				});
				await expect(spectator.locator('.live-badge')).toContainText('LIVE');
				await expect(spectator.locator('.live-badge')).not.toHaveClass(/stale/);

				// Privacy: an anon viewer (no follow edge) sees the
				// anonymised handle derived from USER_A's uuid
				// (a1b2c3d4-… → "Runner #A1B2"), NEVER the display_name. A
				// regression here re-leaks the runner's real name on every
				// shared live URL.
				await expect(spectator.locator('.live-runner-name')).toContainText(
					'Runner #A1B2'
				);
				await expect(spectator.locator('.live-runner-name')).not.toContainText(
					'Jared Howard'
				);

				// Last backlog ping's totals: 3.5 km / 17:30.
				await expect(
					spectator.locator('.live-stat-value').first()
				).toContainText('3.5');
				await expect(
					spectator.locator('.live-stat-value').nth(1)
				).toContainText('17:30');

				// Freshness consumed the ping's `at` clock — the sub-line is
				// an "Updated …" age, not the static fallback copy.
				await expect(spectator.locator('.live-runner-sub')).toContainText(
					/Updated/i
				);
			});

			// ── 4. A live update arrives while the page is open ─────────
			await test.step('a live position update renders without a reload', async () => {
				// A fresh INSERT into live_run_pings: the spectator page's
				// postgres_changes subscription receives it and pushPing()
				// advances the stat strip in place — no navigation. This is
				// the realtime seam the backlog hydration alone can't prove.
				const { error } = await admin.from('live_run_pings').insert({
					run_id: runId,
					user_id: USER_A.id,
					lat: OUT_OF_ZONE[2].lat,
					lng: OUT_OF_ZONE[2].lng,
					distance_m: 5_000,
					elapsed_s: 1_500,
					at: new Date().toISOString()
				});
				expect(error).toBeNull();

				// 5.0 km / 25:00 — the new totals, arriving over the live
				// channel on the already-mounted page.
				await expect(
					spectator.locator('.live-stat-value').first()
				).toContainText('5', { timeout: 15_000 });
				await expect(
					spectator.locator('.live-stat-value').nth(1)
				).toContainText('25:00', { timeout: 15_000 });
				// Still LIVE + fresh — the new ping is current.
				await expect(spectator.locator('.live-badge')).toHaveClass(/active/);
			});

			// ── 5. Signal drops → the badge goes honestly STALE ─────────
			await test.step('the runner loses signal and the badge flips to DELAYED', async () => {
				// Manufacture the gap deterministically: replace the ping
				// history with a single point stamped 5 min ago (> the 90 s
				// LIVE_STALE_AFTER_MS). On reload the page's last-ping clock
				// is 5 min old, so isStale is true on first paint — no need
				// to wait out the 1 Hz freshnessTicker.
				const { error: delErr } = await admin
					.from('live_run_pings')
					.delete()
					.eq('run_id', runId);
				expect(delErr).toBeNull();
				await insertLivePings({
					run_id: runId,
					user_id: USER_A.id,
					points: [
						{
							...OUT_OF_ZONE[2],
							distance_m: 5_000,
							elapsed_s: 1_500,
							at: new Date(Date.now() - 5 * 60 * 1000).toISOString()
						}
					]
				});

				await spectator.goto(`/live/${runId}`);

				const badge = spectator.locator('.live-badge');
				// Pings still exist (status stays 'live') but the last one is
				// past the stale window → the `.stale` treatment, NOT
				// `.active`, and the LIVE word must NOT appear.
				await expect(badge).toHaveClass(/stale/, { timeout: 10_000 });
				await expect(badge).not.toHaveClass(/active/);
				await expect(badge).toContainText(/DELAYED/i);

				// Honest age, not "Live from the runner's device".
				await expect(spectator.locator('.live-runner-sub')).toContainText(
					/Updated 5 min ago/i
				);
				await expect(spectator.locator('.live-runner-sub')).not.toContainText(
					/Live from/i
				);
			});

			// ── 6. The run finishes → the spectator sees Finished ───────
			await test.step('the recorder posts final totals and the run reads Finished', async () => {
				// The recorder's final sync posts the completed run's saved
				// totals. Model it as the SAME row's started_at + duration_s
				// moving its computed end to > 2 min in the past, which is
				// exactly what flips runIsFinished(). started 35 min ago,
				// duration 30 min → ended 5 min ago (> the 2 min slack).
				const { error: updErr } = await admin
					.from('runs')
					.update({
						started_at: new Date(Date.now() - 35 * 60 * 1000).toISOString(),
						duration_s: 1_800,
						distance_m: 7_500
					})
					.eq('id', runId);
				expect(updErr).toBeNull();

				// A real recorder's final sync posts the LAST position with the
				// completed odometer too, not just the run row. Replace the
				// stale 5 km ping (planted in step 5) with a final 7.5 km /
				// 30:00 ping so the trace's last point agrees with the saved
				// totals. This matters because the finished-state path
				// (`runIsFinished` branch in +page.svelte) seeds the stat strip
				// from the saved row's distance_m/duration_s but then replays
				// the live_run_pings backlog through pushPing() to rebuild the
				// map trace — and pushPing() overwrites distance/elapsed from
				// each ping. A leftover lower ping would clobber the strip back
				// to 5 km. With the final ping matching the row, the displayed
				// distance is 7.5 km whether it's read from the row or the
				// replayed backlog.
				const { error: delErr } = await admin
					.from('live_run_pings')
					.delete()
					.eq('run_id', runId);
				expect(delErr).toBeNull();
				await insertLivePings({
					run_id: runId,
					user_id: USER_A.id,
					points: [
						{
							...OUT_OF_ZONE[3],
							distance_m: 7_500,
							elapsed_s: 1_800,
							at: new Date(Date.now() - 5 * 60 * 1000).toISOString()
						}
					]
				});

				await spectator.goto(`/live/${runId}`);

				const badge = spectator.locator('.live-badge');
				await expect(badge).toHaveClass(/finished/, { timeout: 10_000 });
				await expect(badge).toContainText(/Finished/i);
				await expect(spectator.locator('.live-runner-sub')).toContainText(
					/Run finished/i
				);
				// Frozen saved totals: 7.5 km / 30:00 — not a demo loop, not
				// the live tiles.
				await expect(
					spectator.locator('.live-stat-value').first()
				).toContainText('7.5');
				await expect(
					spectator.locator('.live-stat-value').nth(1)
				).toContainText('30:00');
			});

			// ── 7. It's now an ordinary completed run for the owner ─────
			await test.step('USER_A sees it as a normal completed run on /runs', async () => {
				await page.goto('/runs');
				await switchRunsToAllTime(page);
				await expect(
					page.locator(`.run-card[href$="${runId}"]`)
				).toBeVisible({ timeout: 10_000 });

				// The detail page mounts as a normal run detail (the live
				// surface was just a view over the same row).
				await page.goto(`/runs/${runId}`);
				await expect(
					page.getByRole('heading', { level: 1 })
				).toBeVisible({ timeout: 10_000 });
				await expect(
					page.locator('.key-stat-value').first()
				).toBeVisible({ timeout: 10_000 });

				// Backend: still the same single row, now with the final
				// saved totals.
				const { data: finalRow } = await admin
					.from('runs')
					.select('id, distance_m, duration_s')
					.eq('id', runId)
					.single();
				expect(finalRow?.id).toBe(runId);
				expect(finalRow?.distance_m).toBe(7_500);
				expect(finalRow?.duration_s).toBe(1_800);
			});
		} finally {
			await spectatorCtx.close();
			// deleteRun sweeps the row; its live_run_pings cascade via the
			// run_id FK ON DELETE CASCADE.
			if (runId) {
				await deleteRun(runId);
			}
		}
	});
});
