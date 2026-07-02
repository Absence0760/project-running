import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /social?tab=people — a blocked account must not leak into discovery.
 *
 * Every other social surface (kudos, comments, follows, leaderboards,
 * profile) gates on the block predicate, but People search + "Suggested for
 * you" hydrated their rows straight off user_profiles with no block filter —
 * so a runner who blocked a harasser still saw them by name + avatar in
 * search. hydratePeopleSuggestions now drops any candidate the viewer has
 * blocked (the client-readable viewer→target direction, via user_blocks
 * owner-read RLS). This pins that: the same search that surfaces a runner
 * stops surfacing them the moment a block row exists.
 */
test.describe('people search — block filter', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a runner the viewer has blocked disappears from name search', async ({ page }) => {
		const admin = getAdminClient();
		// Clean slate: make sure no stale block row exists from a prior run.
		await admin
			.from('user_blocks')
			.delete()
			.eq('blocker_id', USER_A.id)
			.eq('blocked_id', USER_B.id);

		const search = () => page.getByPlaceholder('Search runners by name');
		const alexRow = page.locator('.person-row', { hasText: 'Alex Chen' });

		try {
			// Baseline: Alex Chen is discoverable by name before any block.
			await page.goto('/social?tab=people');
			await expect(search()).toBeVisible({ timeout: 10_000 });
			await search().fill('Alex');
			await expect(alexRow).toBeVisible({ timeout: 5_000 });

			// The viewer blocks Alex (direct insert = the viewer→target row the
			// client can read; block_user's follow-drain is irrelevant here).
			const { error } = await admin
				.from('user_blocks')
				.insert({ blocker_id: USER_A.id, blocked_id: USER_B.id });
			expect(error).toBeNull();

			// Reload and repeat the exact same search — Alex must no longer
			// appear even though search_user_profiles still returns the match
			// (the block filter is applied client-side during hydration).
			await page.reload();
			await expect(search()).toBeVisible({ timeout: 10_000 });
			await search().fill('Alex');
			// Give the debounced search + hydration time to resolve, then
			// assert the row is absent.
			await expect(
				page.getByRole('heading', { name: /No runners match/ })
			).toBeVisible({ timeout: 5_000 });
			await expect(alexRow).toHaveCount(0);
		} finally {
			await admin
				.from('user_blocks')
				.delete()
				.eq('blocker_id', USER_A.id)
				.eq('blocked_id', USER_B.id);
		}
	});
});
