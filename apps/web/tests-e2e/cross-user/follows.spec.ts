import { expect, test } from '@playwright/test';

import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * Cross-user follow flows. USER_C_PRO (morgan) has no outgoing
 * follows in the seed, so they make a clean toggle subject — visit
 * runner's profile, click Follow, click again to Unfollow, leaves
 * the seed state untouched.
 *
 * Future depth: alex (already follows runner) toggling Unfollow,
 * /u/[id] follower-list pagination, follow → feed entry appears,
 * unfollow → feed entry disappears.
 */

test.describe('cross-user follows', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test('morgan follows runner, counter increments, then unfollow restores', async ({
		page
	}) => {
		await page.goto(`/u/${USER_A.id}`);

		// Header h1 confirms we landed on runner's page (display_name
		// from seed).
		await expect(
			page.getByRole('heading', { name: 'Jared Howard', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		// Capture the starting follower count (alex already follows
		// runner, so it's at least 1) — the test asserts a delta, not
		// an absolute, so it's robust to other tests adding seeds.
		const followerCountText = page
			.locator('button.count', { hasText: 'Followers' })
			.locator('.count-num');
		const before = parseInt((await followerCountText.textContent()) ?? '0', 10);

		// The follow button has a Material Symbols icon span whose
		// ligature text ("person_add" / "check") becomes part of the
		// accessible name — `getByRole({ name: 'Follow', exact: true })`
		// would never match. Target by the dedicated `.btn-follow`
		// class instead, and assert state via the "Following" suffix.
		const followBtn = page.locator('button.btn-follow');
		await expect(followBtn).toBeVisible({ timeout: 10_000 });
		await expect(followBtn).not.toContainText('Following');
		await followBtn.click();

		// After follow: button label flips to "Following", counter +1.
		await expect(followBtn).toContainText('Following', { timeout: 5_000 });
		await expect(followerCountText).toHaveText(String(before + 1));

		// Unfollow restores both.
		await followBtn.click();
		await expect(followBtn).not.toContainText('Following', { timeout: 5_000 });
		await expect(followerCountText).toHaveText(String(before));
	});

	test('unfollowing from the own-profile row updates the Following header count live', async ({
		page
	}) => {
		// First, make morgan follow runner so the own-profile Following list
		// has a row to toggle. Restored at the end of the test.
		await page.goto(`/u/${USER_A.id}`);
		const followBtn = page.locator('button.btn-follow');
		await expect(followBtn).toBeVisible({ timeout: 10_000 });
		if (!(await followBtn.textContent())?.includes('Following')) {
			await followBtn.click();
			await expect(followBtn).toContainText('Following', { timeout: 5_000 });
		}

		// Now open morgan's OWN profile, Following tab.
		await page.goto(`/u/${USER_C_PRO.id}?tab=following`);
		const followingCount = page
			.locator('button.count', { hasText: 'Following' })
			.locator('.count-num');
		const before = parseInt((await followingCount.textContent()) ?? '0', 10);
		expect(before).toBeGreaterThanOrEqual(1);

		// Unfollow runner via the row toggle. The header count must decrement
		// immediately, with no reload — the bug was that viewerFollows flipped
		// but profile.following_count stayed frozen.
		const runnerRow = page.locator('.person-row', {
			has: page.locator(`a[href="/u/${USER_A.id}"]`)
		});
		await runnerRow.locator('button.person-toggle').click();
		await expect(followingCount).toHaveText(String(before - 1), { timeout: 5_000 });
	});
});
