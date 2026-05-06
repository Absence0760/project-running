import { expect, test } from '@playwright/test';

import { USER_A, USER_B } from '../fixtures/users';

/**
 * Feed journey — alex (USER_B) starts following only runner (USER_A,
 * per seed); the feed shows runner's recent public runs. Walk:
 *   1. /feed has entries from runner (initial seed state).
 *   2. /u/<runner-id> Following → click → unfollow.
 *   3. /feed shows the "Your feed is empty" state (alex now follows
 *      nobody — `followsAnyone` flips false).
 *   4. /u/<runner-id> Follow → click → re-follow.
 *   5. /feed has entries again.
 *
 * Pins the user_follows ↔ /feed render contract end-to-end. The
 * batch-2 cross-user/follows.spec.ts pins the toggle + counter;
 * this test pins the downstream feed visibility.
 *
 * The seed has runner ↔ alex bidirectional, so unfollowing here
 * leaves alex with zero follows. AfterAll guarantees the follow
 * state is restored (the test itself re-follows; afterEach is a
 * defensive backstop).
 */

test.describe('feed journey', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('alex unfollows runner → /feed empty → re-follow → /feed has entries again', async ({
		page
	}) => {
		// ── Initial: alex's feed has runner's runs ─────────────────
		await test.step('feed has at least one runner-authored entry', async () => {
			await page.goto('/feed');
			// Author chip on a feed card surfaces the display name. seed
			// runner's display_name is "Jared Howard" — match against
			// "Jared" prefix to stay tight to the seed.
			await expect(page.getByText(/Jared/).first()).toBeVisible({
				timeout: 10_000
			});
			// Empty-state heading must NOT be present.
			await expect(
				page.getByRole('heading', { name: 'Your feed is empty' })
			).toHaveCount(0);
		});

		// ── Unfollow runner ────────────────────────────────────────
		await test.step('unfollow runner via /u/<runner-id>', async () => {
			await page.goto(`/u/${USER_A.id}`);
			const followBtn = page.locator('.btn-follow');
			await expect(followBtn).toBeVisible({ timeout: 10_000 });
			// Pre-click: button reads "Following" (alex follows runner).
			await expect(followBtn).toContainText('Following');
			// Capture runner's follower count and wait for it to
			// decrement after the click — that's a stronger signal
			// the unfollowUser DB write committed than the local
			// button-text flip (which is set after the await but
			// before the followee's profile re-fetches).
			const followerCount = page
				.locator('button.count', { hasText: 'Followers' })
				.locator('.count-num');
			const before = parseInt((await followerCount.textContent()) ?? '0', 10);
			await followBtn.click();
			await expect(followBtn).toContainText('Follow');
			await expect(followerCount).toHaveText(String(Math.max(before - 1, 0)));
		});

		// ── Feed empty ─────────────────────────────────────────────
		await test.step('/feed shows the followsAnyone=false empty state', async () => {
			await page.goto('/feed');
			await expect(
				page.getByRole('heading', { name: 'Your feed is empty' })
			).toBeVisible({ timeout: 10_000 });
		});

		// ── Re-follow runner ───────────────────────────────────────
		await test.step('re-follow runner via /u/<runner-id>', async () => {
			await page.goto(`/u/${USER_A.id}`);
			const followBtn = page.locator('.btn-follow');
			await expect(followBtn).toBeVisible({ timeout: 10_000 });
			await expect(followBtn).toContainText('Follow');
			await followBtn.click();
			await expect(followBtn).toContainText('Following');
		});

		// ── Feed has entries again ────────────────────────────────
		await test.step('/feed has runner-authored entries again', async () => {
			await page.goto('/feed');
			await expect(page.getByText(/Jared/).first()).toBeVisible({
				timeout: 10_000
			});
			await expect(
				page.getByRole('heading', { name: 'Your feed is empty' })
			).toHaveCount(0);
		});
	});
});
