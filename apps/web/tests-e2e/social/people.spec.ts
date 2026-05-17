import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { USER_A, USER_B, USER_C_PRO } from '../fixtures/users';

/**
 * /social?tab=people — discover other runners.
 *
 * Two surfaces:
 *   - Search box: ILIKE on `user_profiles.display_name`, self-excluded.
 *   - Suggested-for-you: members of viewer's clubs they don't already
 *     follow, ranked by shared-club count.
 *
 * Each row has an inline Follow / Following toggle with optimistic
 * flip + rollback on error. Both `followUser` and `unfollowUser`
 * write to `user_follows`; the saga test below verifies the writes
 * actually persist across reload (not just an optimistic paint).
 */

test.describe('search — by name', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('search by name finds Alex Chen + flips the Follow toggle to Following', async ({
		page
	}) => {
		// Reset alex's follow state — defensive against state leak.
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.delete()
			.eq('follower_id', USER_A.id)
			.eq('followee_id', USER_B.id);

		try {
			await page.goto('/social?tab=people');
			const search = page.getByPlaceholder('Search runners by name');
			await expect(search).toBeVisible({ timeout: 10_000 });
			await search.fill('Alex');
			// Debounce is 300ms — wait briefly past it.
			await expect(
				page.locator('.person-row', { hasText: 'Alex Chen' })
			).toBeVisible({ timeout: 5_000 });
			// Self-row never appears in search even with a match on the
			// display_name (runner is signed in).
			await expect(
				page.locator('.person-row', { hasText: 'Jared Howard' })
			).toHaveCount(0);

			const alexRow = page.locator('.person-row', { hasText: 'Alex Chen' });
			const followBtn = alexRow.locator('.follow-btn');
			await expect(followBtn).toContainText('Follow');
			await expect(followBtn).not.toContainText('Following');

			await followBtn.click();
			await expect(followBtn).toContainText('Following', { timeout: 5_000 });
		} finally {
			await admin
				.from('user_follows')
				.delete()
				.eq('follower_id', USER_A.id)
				.eq('followee_id', USER_B.id);
		}
	});

	test('search with no matches renders the canonical empty state', async ({ page }) => {
		await page.goto('/social?tab=people');
		const search = page.getByPlaceholder('Search runners by name');
		await search.fill('zzzzzzz-no-such-runner');
		await expect(
			page.getByRole('heading', { name: /No runners match/ })
		).toBeVisible({ timeout: 5_000 });
	});

	test('Clear search button restores the suggested-for-you list', async ({ page }) => {
		await page.goto('/social?tab=people');
		const search = page.getByPlaceholder('Search runners by name');
		await search.fill('Alex');
		await expect(
			page.locator('.person-row', { hasText: 'Alex Chen' })
		).toBeVisible({ timeout: 5_000 });

		await page.getByRole('button', { name: 'Clear search' }).click();
		// After clearing, the search results disappear; the section
		// header flips from "Search results" to "Suggested for you".
		// The h2 is always rendered in the suggestion branch (the empty-
		// suggestions card is an h3 underneath, so the regex below
		// matches a single heading).
		await expect(
			page.getByRole('heading', { level: 2, name: /Suggested for you/ })
		).toBeVisible({ timeout: 5_000 });
	});
});

test.describe('suggested — empty state', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	// Morgan starts seeded with no clubs, but other tests in the suite
	// may join her into one and skip cleanup. Sweep + restore the
	// no-clubs invariant in beforeEach so this test is deterministic.
	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('club_members')
			.delete()
			.eq('user_id', USER_C_PRO.id);
	});

	test('viewer with no clubs sees the "Browse clubs" empty-state CTA', async ({
		page
	}) => {
		await page.goto('/social?tab=people');
		await expect(
			page.getByRole('heading', { name: 'No suggestions yet' })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByRole('link', { name: /Browse clubs/ })
		).toHaveAttribute('href', '/social?tab=clubs');
	});
});

test.describe('full saga — freshly-planted users', () => {
	// Plant two real auth.users + user_profiles rows with unique display
	// names so search has unambiguous, isolated matches. createSagaUsers
	// signs each in once and persists their storageState; we attach the
	// follower's state per-test below.
	let users: SagaUser[];
	let stamp: string;

	test.beforeAll(async () => {
		stamp = Date.now().toString(36);
		users = await createSagaUsers(2, {
			displayNames: [`SearchSaga Alpha ${stamp}`, `SearchSaga Bravo ${stamp}`],
		});
	});

	test.afterAll(async () => {
		if (users) await deleteSagaUsers(users);
	});

	test('Alpha searches for Bravo by name → Follow → reload persists → Bravo lands in Following list → Unfollow restores', async ({
		browser,
	}) => {
		const [alpha, bravo] = users;
		const ctx = await browser.newContext({ storageState: alpha.storageStatePath });
		const page = await ctx.newPage();
		try {
			// 1. Open /social → People tab, search by Bravo's display name.
			await page.goto('/social?tab=people');
			await expect(page.getByRole('heading', { level: 1, name: 'Social' })).toBeVisible({
				timeout: 10_000,
			});
			const search = page.getByPlaceholder('Search runners by name');
			await expect(search).toBeVisible();
			await search.fill(bravo.displayName);

			// 2. Bravo's row appears with a Follow button (not Following).
			const bravoRow = page.locator('.person-row', { hasText: bravo.displayName });
			await expect(bravoRow).toBeVisible({ timeout: 5_000 });
			const followBtn = bravoRow.locator('.follow-btn');
			await expect(followBtn).toContainText('Follow');
			await expect(followBtn).not.toContainText('Following');

			// Self never appears in own search results, even with a match.
			await expect(
				page.locator('.person-row', { hasText: alpha.displayName })
			).toHaveCount(0);

			// 3. Click Follow → button flips to Following.
			await followBtn.click();
			await expect(followBtn).toContainText('Following', { timeout: 5_000 });

			// Wait for the user_follows INSERT to land before reloading.
			// The optimistic flip is immediate; without this poll, reload
			// can race the in-flight insert.
			const admin = getAdminClient();
			await expect(async () => {
				const { data: edge } = await admin
					.from('user_follows')
					.select('follower_id, followee_id')
					.eq('follower_id', alpha.id)
					.eq('followee_id', bravo.id)
					.maybeSingle();
				expect(edge).toBeTruthy();
			}).toPass({ timeout: 5_000 });

			// 4. Reload — the follow must have been committed server-side,
			//    not just optimistically painted. The post-reload state
			//    proves the user_follows write landed.
			await page.reload();
			await page.waitForLoadState('networkidle');
			await search.fill(bravo.displayName);
			const bravoRowAfterReload = page
				.locator('.person-row', { hasText: bravo.displayName });
			await expect(bravoRowAfterReload.locator('.follow-btn')).toContainText(
				'Following',
				{ timeout: 5_000 }
			);

			// 5. Bravo lands in Alpha's Following list on the profile page.
			await page.goto(`/u/${alpha.id}`);
			await page.getByRole('tab', { name: /^Following/ }).click();
			await expect(
				page.locator('.person-row', { hasText: bravo.displayName }).first()
			).toBeVisible({ timeout: 10_000 });

			// 6. DB sanity — user_follows row exists.
			const { data: edge } = await admin
				.from('user_follows')
				.select('follower_id, followee_id')
				.eq('follower_id', alpha.id)
				.eq('followee_id', bravo.id)
				.maybeSingle();
			expect(edge).toBeTruthy();

			// 7. Reverse: search again, click Following → flips to Follow.
			await page.goto('/social?tab=people');
			await page.getByPlaceholder('Search runners by name').fill(bravo.displayName);
			const reverseBtn = page
				.locator('.person-row', { hasText: bravo.displayName })
				.locator('.follow-btn');
			await expect(reverseBtn).toContainText('Following', { timeout: 5_000 });
			await reverseBtn.click();
			await expect(reverseBtn).toContainText('Follow', { timeout: 5_000 });
			await expect(reverseBtn).not.toContainText('Following');

			// 8. DB sanity — user_follows row is gone. The button flip is
			//    optimistic so the DELETE may still be in-flight; poll
			//    briefly until the row disappears.
			await expect(async () => {
				const { data: gone } = await admin
					.from('user_follows')
					.select('follower_id, followee_id')
					.eq('follower_id', alpha.id)
					.eq('followee_id', bravo.id)
					.maybeSingle();
				expect(gone).toBeNull();
			}).toPass({ timeout: 5_000 });
		} finally {
			await ctx.close();
		}
	});

	test('Bravo sees Alpha in Followers after Alpha follows Bravo', async ({ browser }) => {
		const [alpha, bravo] = users;
		// Plant the follow edge directly so the assertion isolates from
		// the UI saga above (which fully cleans up via Unfollow). This
		// test focuses on the Followers-list contract from Bravo's view.
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.upsert(
				{ follower_id: alpha.id, followee_id: bravo.id },
				{ onConflict: 'follower_id,followee_id' }
			);

		const ctx = await browser.newContext({ storageState: bravo.storageStatePath });
		const page = await ctx.newPage();
		try {
			await page.goto(`/u/${bravo.id}`);
			await page.getByRole('tab', { name: /^Followers/ }).click();
			await expect(
				page.locator('.person-row', { hasText: alpha.displayName }).first()
			).toBeVisible({ timeout: 10_000 });
		} finally {
			await ctx.close();
			await admin
				.from('user_follows')
				.delete()
				.eq('follower_id', alpha.id)
				.eq('followee_id', bravo.id);
		}
	});
});
