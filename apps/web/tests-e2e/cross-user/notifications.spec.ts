import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Cross-user notification fan-out. The notification triggers fire on
 * INSERT into run_kudos / run_comments / user_follows
 * (migration 20260528_001_notifications.sql) — recipient's bell
 * surfaces the unread on the next refresh-on-auth-ready (no realtime
 * subscription wired up yet, see docs/architecture.md).
 *
 * Each test uses two browser contexts (one writer, one recipient) and
 * cleans up the engagement at the end so the seed state is preserved.
 *
 * Future depth: comment-reply notification (parent author gets it),
 * follow notification, kudos popover deep-link to /share/run/[id],
 * inbox view at /u/<self>?tab=notifications shows the same items.
 */

test.describe('cross-user notifications', () => {
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
			await alex.waitForLoadState('networkidle');
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
			await runner.waitForLoadState('networkidle');
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
});
