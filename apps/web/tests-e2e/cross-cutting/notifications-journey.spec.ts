import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { clearNotifications, deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Notifications journey — cross-user engagement drives ONE notification
 * lifecycle through every surface it appears on, end to end:
 *
 *   1. USER_A owns a fresh PUBLIC run (planted via simulate.insertRun so
 *      it carries a unique title and doesn't disturb the seeded pinned
 *      run's distance-based assertions elsewhere).
 *   2. As a SECOND user (USER_C_PRO / morgan, a separate browser
 *      context), open USER_A's run at /share/run/[id] and engage via the
 *      real UI: give kudos (.kudos-btn in RunSocial) + post a comment
 *      (.composer in RunSocial) + follow USER_A (the profile Follow
 *      toggle on /u/[USER_A]). Each write fires a notify_* trigger
 *      (migration 20260528000001_notifications.sql): kudos + comment →
 *      the run owner, follow → the followee. All three land as unread
 *      notification rows for USER_A.
 *   3. As USER_A, the sidebar NotificationBell shows the unread badge
 *      incremented by the delta, and the bell popover lists the
 *      kudos / comment / follow entries by their composed verbs.
 *   4. Open the full inbox at /u/[USER_A]?tab=notifications
 *      (NotificationsList) — the rows render under All, and the Unread
 *      filter shows them as unread.
 *   5. Mark all read — the bell badge clears (unreadCount === 0, the
 *      .badge element unmounts) and the Unread tab empties to its
 *      "all caught up" state.
 *   6. Cleanup: deleteRun cascades the kudos + comments + their
 *      notifications; the follow edge + USER_A's notifications are wiped
 *      so the shared seed user starts clean for the next spec.
 *
 * How the badge updates (grounded in notifications.svelte.ts):
 *   The store exposes `unreadCount` and refreshes it on three triggers —
 *   auth-ready (initial paint), window-focus, and a Supabase Realtime
 *   subscription (INSERT bumps the count live, UPDATE/DELETE re-read the
 *   authoritative count via fetchUnreadNotificationCount). Cross-context
 *   realtime delivery is not deterministic in a headless run, so this
 *   journey drives the REFETCH path: USER_A navigates (goto /dashboard,
 *   then reload) AFTER USER_C_PRO's writes have landed, so the auth-ready
 *   refresh re-reads the count. No sleeps — every step is an auto-waiting
 *   assertion, and the badge delta is asserted against a measured
 *   baseline (the seed user may already carry notifications), never an
 *   absolute count from zero.
 *
 * Distinct from cross-user/notifications.spec.ts (bell popover only, alex
 * as writer, per-kind isolation) and u/notifications.spec.ts (inbox only,
 * service-role plants): this is the single bell → inbox → mark-read
 * WORKFLOW, driven by USER_C_PRO entirely through the UI, exercising
 * kudos + comment + follow together.
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

test.describe('notifications journey — engagement → bell → inbox → read', () => {
	test.describe.configure({ timeout: 90_000 });

	let runId: string | null = null;

	test.beforeEach(async () => {
		// Start USER_A's inbox empty so the badge delta is unambiguous and
		// the bell can't already read "9+" (which would defeat the numeric
		// delta assertion). The seed accumulates notifications across runs;
		// clearing is the deterministic baseline used by every notification
		// spec.
		await clearNotifications(USER_A.id);
		// Defence in depth: a prior failed run may have left morgan's
		// engagement on a previous run id, but morgan's follow edge to
		// USER_A could linger — drop it so the UI Follow toggle starts in
		// the not-following state and the insert fires a fresh trigger.
		await getAdminClient()
			.from('user_follows')
			.delete()
			.eq('follower_id', USER_C_PRO.id)
			.eq('followee_id', USER_A.id);

		runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(Date.now() - 15 * 60 * 1000).toISOString(),
			distance_m: 8_000,
			duration_s: 2_400,
			is_public: true,
			metadata: { activity_type: 'run', title: `E2E notify-journey ${Date.now()}` }
		});
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		// deleteRun cascades run_kudos + run_comments (FK ON DELETE
		// CASCADE), and their notifications cascade off run_id — so the
		// kudos + comment rows + their notifications all vanish.
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
		// The follow notification is keyed by actor, not by the run, so it
		// doesn't cascade with the run delete — wipe the follow edge and
		// USER_A's remaining notifications so the shared seed user is clean.
		await admin
			.from('user_follows')
			.delete()
			.eq('follower_id', USER_C_PRO.id)
			.eq('followee_id', USER_A.id);
		await clearNotifications(USER_A.id);
	});

	test('morgan kudos + comments + follows → runner bell badge, popover, inbox, then mark-all-read clears it', async ({
		browser
	}) => {
		const ctxMorgan = await browser.newContext({
			storageState: USER_C_PRO.storageStatePath
		});
		const ctxRunner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		// Pre-accept the consent banner in both contexts so the fixed
		// dialog can't intercept pointer events on the kudos button,
		// composer, Follow toggle, or bell/inbox controls.
		await ctxMorgan.addInitScript(setConsentAccepted);
		await ctxRunner.addInitScript(setConsentAccepted);
		const morgan = await ctxMorgan.newPage();
		const runner = await ctxRunner.newPage();

		const commentBody = `e2e-journey strong session ${Date.now()}`;

		try {
			// ── Baseline: runner's bell badge before any engagement ──
			await test.step('snapshot runner unread baseline (cleared = 0)', async () => {
				await runner.goto('/dashboard');
				// The bell badge only renders when unreadCount > 0. After the
				// beforeEach clear it should be absent — but read defensively
				// so the journey survives a stray concurrent notification.
				const badge = runner.locator('.bell-wrap .badge');
				// Auto-waiting on the bell button proves the shell mounted +
				// the auth-ready refresh ran before we count the badge.
				await expect(runner.locator('.bell-wrap .bell-btn')).toBeVisible({
					timeout: 10_000
				});
				await expect(badge).toHaveCount(0, { timeout: 10_000 });
			});

			// ── Morgan engages via the real UI ──
			await test.step('morgan gives kudos + comments on the run', async () => {
				// The share page asks the clip-public-track Edge Function to
				// redact the (absent) track for a non-owner viewer; stub it so
				// the page renders without the function running locally.
				await morgan.route('**/functions/v1/clip-public-track', (route) =>
					route.fulfill({
						status: 200,
						contentType: 'application/json',
						body: JSON.stringify({ points: [] })
					})
				);
				await morgan.goto(`/share/run/${runId}`);

				const kudosBtn = morgan.locator('.kudos-btn');
				await expect(kudosBtn).toBeVisible({ timeout: 10_000 });
				// Fresh run → morgan has not kudosed it; the button is enabled
				// (she is not the owner) and in the not-given state.
				await expect(kudosBtn).not.toHaveClass(/given/);
				await kudosBtn.click();
				await expect(kudosBtn).toHaveClass(/given/, { timeout: 10_000 });

				// Post a top-level comment via the RunSocial composer. The
				// notify_run_comment trigger fans this out to the run owner.
				const composer = morgan.locator('.composer textarea');
				await expect(composer).toBeVisible({ timeout: 10_000 });
				await composer.fill(commentBody);
				await morgan.locator('.composer button[type="submit"]').click();
				// load() re-runs after postRunComment resolves; the comment
				// appears in the list — proves the write committed before we
				// pivot to the runner's bell.
				await expect(morgan.getByText(commentBody)).toBeVisible({
					timeout: 10_000
				});
			});

			await test.step('morgan follows runner from the profile page', async () => {
				await morgan.goto(`/u/${USER_A.id}`);
				const followBtn = morgan.getByRole('button', { name: 'Follow', exact: true });
				await expect(followBtn).toBeVisible({ timeout: 10_000 });
				await followBtn.click();
				// Optimistic flip to the Following state confirms followUser
				// resolved (and the notify_user_follow trigger fired). The
				// button's accessible name is its aria-label, which flips to
				// "Unfollow" once following — so assert on the rendered text
				// span (m('profile.following')) via .btn-follow, not the role
				// name.
				await expect(morgan.locator('.btn-follow')).toContainText('Following', {
					timeout: 10_000
				});
			});

			// Confirm all three notification rows exist server-side before
			// asserting the badge — so a UI-timing flake can't be confused
			// with a missing trigger. Auto-retries until the trigger fan-out
			// (kudos + comment + follow) has landed exactly three rows.
			await test.step('three unread notifications landed for runner', async () => {
				const admin = getAdminClient();
				await expect(async () => {
					const { count } = await admin
						.from('notifications')
						.select('*', { count: 'exact', head: true })
						.eq('user_id', USER_A.id)
						.is('read_at', null);
					expect(count).toBe(3);
				}).toPass({ timeout: 10_000 });
			});

			// ── Runner's bell reflects the +3 delta on refetch ──
			await test.step('runner bell badge shows the unread count', async () => {
				// Navigate (not sleep) to force the auth-ready refetch path in
				// notifications.svelte.ts — the badge re-reads the
				// authoritative count via fetchUnreadNotificationCount.
				await runner.reload();
				const badge = runner.locator('.bell-wrap .badge');
				await expect(badge).toBeVisible({ timeout: 10_000 });
				// Baseline was 0 (cleared) + 3 engagement rows.
				await expect(badge).toHaveText('3', { timeout: 10_000 });
			});

			// ── Bell popover lists the three notifications by verb ──
			await test.step('bell popover lists kudos + comment + follow', async () => {
				await runner.locator('.bell-wrap .bell-btn').click();
				const popover = runner.locator('.bell-wrap [role="dialog"]');
				await expect(popover).toBeVisible({ timeout: 5_000 });
				// verbFor() composes morgan's display name into each entry.
				// Distance is the planted 8_000 m → "8.0 km" (km/mi-agnostic
				// match so the test survives runner's unit preference).
				await expect(popover).toContainText(/Morgan .* gave kudos to your/i);
				await expect(popover).toContainText(/Morgan .* commented on your/i);
				await expect(popover).toContainText(/Morgan .* started following you/i);
				// Close the popover before navigating away.
				await runner.keyboard.press('Escape');
			});

			// ── Full inbox renders the rows under All + Unread ──
			await test.step('inbox lists the rows and the Unread filter shows them', async () => {
				await runner.goto(`/u/${USER_A.id}?tab=notifications`);
				await expect(runner.getByRole('heading', { level: 1 })).toBeVisible({
					timeout: 10_000
				});

				const items = runner.locator('.item-wrap');
				await expect(items.first()).toBeVisible({ timeout: 10_000 });
				await expect(items).toHaveCount(3);
				// All three arrived unread (trigger inserts with read_at=null).
				await expect(runner.locator('.item-wrap.unread')).toHaveCount(3);

				// The Unread filter keeps all three visible.
				await runner.getByRole('button', { name: /Unread/ }).click();
				await expect(runner.locator('.item-wrap')).toHaveCount(3);
			});

			// ── Mark all read clears the inbox + the bell badge ──
			await test.step('mark all read empties Unread and clears the badge', async () => {
				// Back on All so the Mark-all-read button (gated on an unread
				// item existing) is present.
				await runner.getByRole('button', { name: 'All', exact: true }).click();
				await runner.getByRole('button', { name: 'Mark all read' }).click();

				// Unread filter → the "all caught up" empty state.
				await runner.getByRole('button', { name: /Unread/ }).click();
				await expect(
					runner.locator('.empty', { hasText: "You're all caught up" })
				).toBeVisible({ timeout: 5_000 });

				// All rows survive but none retain the unread class.
				await runner.getByRole('button', { name: 'All', exact: true }).click();
				await expect(runner.locator('.item-wrap')).toHaveCount(3);
				await expect(runner.locator('.item-wrap.unread')).toHaveCount(0);

				// The sidebar bell badge has cleared (unreadCount === 0 →
				// the .badge element unmounts). markAllNotificationsRead +
				// notificationStore.clear() drove this without a reload.
				await expect(runner.locator('.bell-wrap .badge')).toHaveCount(0, {
					timeout: 5_000
				});
			});
		} finally {
			await ctxMorgan.close();
			await ctxRunner.close();
		}
	});
});
