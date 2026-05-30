import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { clearNotifications } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Cross-user notification fan-out. The notification triggers fire on
 * INSERT into run_kudos / run_comments / user_follows
 * (migration 20260528000001_notifications.sql) — recipient's bell
 * surfaces the unread on the next refresh-on-auth-ready (no realtime
 * subscription wired up yet, see docs/architecture/architecture.md).
 *
 * Each test uses two browser contexts (one writer, one recipient) and
 * cleans up the engagement at the end so the seed state is preserved.
 *
 * Future depth: comment-reply notification (parent author gets it),
 * follow notification, kudos popover deep-link to /share/run/[id],
 * inbox view at /u/<self>?tab=notifications shows the same items.
 */

test.describe('cross-user notifications', () => {
	test.beforeEach(async () => {
		// Reset runner's notifications so the badge starts at 0. The
		// notifications table has no automatic cleanup and accumulates
		// across test runs — once unread count crosses 9 the bell shows
		// "9+" instead of the literal number, breaking the +1 assert
		// below. A clear at the start guarantees `before=0` and
		// `after=1` deterministically.
		await clearNotifications(USER_A.id);
	});

	test('alex kudos runner → runner sees bell badge increment + popover entry', async ({
		browser
	}) => {
		// Two browser contexts in one test — one as USER_B (alex),
		// one as USER_A (runner). The kudos write fires the
		// `notify_run_kudos` SECURITY DEFINER trigger which inserts
		// into `notifications` with kind='kudos'. The layout's
		// $effect on auth-ready refreshes the notification store on
		// next page-load.
		//
		// USER_A's seed already carries the cross-user kudos +
		// comment from alex (on a NON-pinned public run), so the
		// starting unread count is non-zero. The test asserts a
		// delta of +1 rather than an absolute 1.
		const ctxAlex = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const ctxRunner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		const alex = await ctxAlex.newPage();
		const runner = await ctxRunner.newPage();

		try {
			// ── Snapshot runner's starting unread count ──
			await runner.goto('/dashboard');
			// Needed: next read is .count() (snapshot — no auto-retry).
			// Without the wait, a 0 here can mean "no notifications" OR
			// "fetch hasn't landed yet" — false equivalence.
			await runner.waitForLoadState('networkidle');
			// The badge only renders when unreadCount > 0; if zero,
			// .badge is absent. Safe-read via count() then text.
			const badgeBefore = runner.locator('.bell-wrap .badge');
			const beforeText = (await badgeBefore.count()) > 0
				? (await badgeBefore.textContent())?.trim() ?? '0'
				: '0';
			const before = parseInt(beforeText, 10);

			// ── Alex kudos runner via /share/run/ ──
			await alex.route('**/functions/v1/clip-public-track', (route) =>
				route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ points: [] })
				})
			);
			await alex.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
			const kudosBtn = alex.locator('.kudos-btn');
			await expect(kudosBtn).toBeVisible({ timeout: 10_000 });
			// If the run already had alex's kudos given (left over from
			// a prior failed run), rescind first to start clean.
			if (await kudosBtn.evaluate((el) => el.classList.contains('given'))) {
				await kudosBtn.click();
				await expect(kudosBtn).not.toHaveClass(/given/);
			}
			await kudosBtn.click();
			await expect(kudosBtn).toHaveClass(/given/);

			// ── Runner reloads /dashboard — bell should reflect +1 ──
			await runner.reload();
			const badgeAfter = runner.locator('.bell-wrap .badge');
			await expect(badgeAfter).toBeVisible({ timeout: 10_000 });
			await expect(badgeAfter).toHaveText(String(before + 1), {
				timeout: 10_000
			});

			// ── Open popover; assert the kudos entry actually rendered
			//    with alex's identity in the verb. The popover is a
			//    role=dialog with the items list inside; verbFor
			//    composes "<display_name> gave kudos to your <km> km".
			//    Pinned public run is 9000m → "9.0 km".
			await runner.locator('.bell-wrap .bell-btn').click();
			const popover = runner.locator('.bell-wrap [role="dialog"]');
			await expect(popover).toBeVisible({ timeout: 5_000 });
			await expect(popover).toContainText('Alex Chen gave kudos to your 9.0 km');

			// "Mark all read" clears the badge.
			await runner.getByRole('button', { name: /Mark all read/ }).click();
			// After clear: badge element disappears (unreadCount === 0).
			await expect(runner.locator('.bell-wrap .badge')).toHaveCount(0, {
				timeout: 5_000
			});

			// ── Cleanup: alex rescinds the kudos so the seeded state
			// is preserved. ──
			await alex.locator('.kudos-btn').click();
			await expect(alex.locator('.kudos-btn')).not.toHaveClass(/given/);
		} finally {
			await ctxAlex.close();
			await ctxRunner.close();
		}
	});

	test('alex comments → runner sees a comment notification with the right verb', async ({
		browser
	}) => {
		// Companion to the kudos test: pins the `notify_run_comment`
		// trigger path. A regression in the trigger or the
		// notifications-list verb would surface here as a missing or
		// mis-rendered popover entry.
		const ctxRunner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		const runner = await ctxRunner.newPage();
		const admin = getAdminClient();
		let commentId: string | null = null;

		try {
			// Plant the comment via service-role — we already test the
			// /share writer path elsewhere.
			const { data, error } = await admin
				.from('run_comments')
				.insert({
					run_id: RUNNER_PUBLIC_RUN_ID,
					author_id: USER_B.id,
					body: 'e2e-notify-comment ' + Date.now()
				})
				.select('id')
				.single();
			if (error) throw error;
			commentId = data.id as string;

			await runner.goto('/dashboard');
			const badge = runner.locator('.bell-wrap .badge');
			await expect(badge).toBeVisible({ timeout: 10_000 });

			await runner.locator('.bell-wrap .bell-btn').click();
			const popover = runner.locator('.bell-wrap [role="dialog"]');
			await expect(popover).toBeVisible({ timeout: 5_000 });
			// verb for kind='comment' is "Alex Chen commented on your <km>".
			await expect(popover).toContainText(
				/Alex Chen commented on your/i
			);
		} finally {
			if (commentId) {
				await admin.from('run_comments').delete().eq('id', commentId);
			}
			await ctxRunner.close();
		}
	});

	test('alex follows runner → runner sees a follow notification', async ({
		browser
	}) => {
		// Migration 20260528000001 also installs `notify_user_follow` —
		// inserting into user_follows fans out to the followee. Pin the
		// popover entry shape ("X started following you").
		const ctxRunner = await browser.newContext({
			storageState: USER_A.storageStatePath
		});
		const runner = await ctxRunner.newPage();
		const admin = getAdminClient();

		// Seed already has alex(USER_B) following runner(USER_A) — remove
		// the edge first so we can re-insert and trigger a fresh
		// notification.
		await admin
			.from('user_follows')
			.delete()
			.eq('follower_id', USER_B.id)
			.eq('followee_id', USER_A.id);

		try {
			const { error } = await admin.from('user_follows').insert({
				follower_id: USER_B.id,
				followee_id: USER_A.id
			});
			if (error) throw error;

			await runner.goto('/dashboard');
			const badge = runner.locator('.bell-wrap .badge');
			await expect(badge).toBeVisible({ timeout: 10_000 });

			await runner.locator('.bell-wrap .bell-btn').click();
			const popover = runner.locator('.bell-wrap [role="dialog"]');
			await expect(popover).toBeVisible({ timeout: 5_000 });
			await expect(popover).toContainText(
				/Alex Chen started following you/i
			);
		} finally {
			// Re-establish the seeded follow edge (idempotent due to PK).
			await admin
				.from('user_follows')
				.delete()
				.eq('follower_id', USER_B.id)
				.eq('followee_id', USER_A.id);
			await admin.from('user_follows').insert({
				follower_id: USER_B.id,
				followee_id: USER_A.id
			});
			await ctxRunner.close();
		}
	});
});
