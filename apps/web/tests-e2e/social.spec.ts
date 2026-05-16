import { expect, test } from '@playwright/test';

import { getAdminClient } from './fixtures/local-supabase';
import { USER_A, USER_B, USER_C_PRO } from './fixtures/users';

/**
 * /social — top-level social hub hosting Feed · People · Clubs as ARIA
 * tabs. Replaces the old standalone /clubs + /feed top-level pages;
 * both URLs now redirect here.
 */

test.describe('/social — tab strip + redirects', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('default lands on Feed tab; clicking People updates ?tab and aria-selected', async ({
		page
	}) => {
		await page.goto('/social');
		await expect(page.getByRole('heading', { level: 1, name: 'Social' })).toBeVisible({
			timeout: 10_000
		});
		const feedTab = page.getByRole('tab', { name: /Feed/ });
		const peopleTab = page.getByRole('tab', { name: /People/ });
		const clubsTab = page.getByRole('tab', { name: /Clubs/ });
		await expect(feedTab).toHaveAttribute('aria-selected', 'true');
		await expect(peopleTab).toHaveAttribute('aria-selected', 'false');
		await expect(clubsTab).toHaveAttribute('aria-selected', 'false');

		await peopleTab.click();
		await expect(page).toHaveURL(/\/social\?tab=people/, { timeout: 5_000 });
		await expect(peopleTab).toHaveAttribute('aria-selected', 'true');
		await expect(feedTab).toHaveAttribute('aria-selected', 'false');

		await clubsTab.click();
		await expect(page).toHaveURL(/\/social\?tab=clubs/, { timeout: 5_000 });
		await expect(clubsTab).toHaveAttribute('aria-selected', 'true');
	});

	test('/clubs (top-level) redirects to /social?tab=clubs', async ({ page }) => {
		await page.goto('/clubs');
		await expect(page).toHaveURL(/\/social\?tab=clubs/, { timeout: 10_000 });
	});

	test('/clubs?tab=browse redirects to /social?tab=clubs&clubs-sub=browse (deep link preserved)', async ({
		page
	}) => {
		await page.goto('/clubs?tab=browse');
		await expect(page).toHaveURL(/\/social\?tab=clubs&clubs-sub=browse/, {
			timeout: 10_000
		});
	});

	test('/feed redirects to /social?tab=feed', async ({ page }) => {
		await page.goto('/feed');
		await expect(page).toHaveURL(/\/social\?tab=feed/, { timeout: 10_000 });
	});

	test('/social?tab=clubs renders the My-clubs sub-tab (canary: club card visible)', async ({
		page
	}) => {
		await page.goto('/social?tab=clubs');
		// Runner owns / admins Sydney Run Club in the seed.
		await expect(
			page.locator('.card', { hasText: 'Sydney Run Club' }).first()
		).toBeVisible({ timeout: 10_000 });
	});
});

test.describe('/social?tab=people — search', () => {
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

test.describe('/social?tab=people — suggested', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test('viewer with no clubs sees the "Browse clubs" empty-state CTA', async ({
		page
	}) => {
		// USER_C_PRO (morgan) is in no clubs by seed → suggestion query
		// has no source, so the People tab shows the "Browse clubs"
		// empty-state CTA.
		const admin = getAdminClient();
		const { data: rows } = await admin
			.from('club_members')
			.select('club_id')
			.eq('user_id', USER_C_PRO.id)
			.eq('status', 'active');
		test.skip((rows ?? []).length > 0, 'morgan has joined clubs already in this DB; skip the no-clubs branch');

		await page.goto('/social?tab=people');
		await expect(
			page.getByRole('heading', { name: 'No suggestions yet' })
		).toBeVisible({ timeout: 10_000 });
		await expect(
			page.getByRole('link', { name: /Browse clubs/ })
		).toHaveAttribute('href', '/social?tab=clubs');
	});
});

test.describe('/social?tab=feed — feed surface', () => {
	test.use({ storageState: USER_B.storageStatePath });

	// Plant a fresh runner-authored public run inside the 14-day window
	// so the feed has at least one entry, regardless of how far the
	// clock has drifted past the seed's fixed run dates.
	let plantedRunId: string | null = null;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.upsert(
				{ follower_id: USER_B.id, followee_id: USER_A.id },
				{ onConflict: 'follower_id,followee_id' }
			);
		const { data: row, error } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
				duration_s: 1800,
				distance_m: 7000,
				source: 'app',
				is_public: true,
				metadata: { activity_type: 'run' }
			})
			.select('id')
			.single();
		if (error) throw error;
		plantedRunId = (row as { id: string }).id;
	});

	test.afterEach(async () => {
		if (plantedRunId) {
			const admin = getAdminClient();
			await admin.from('runs').delete().eq('id', plantedRunId);
			plantedRunId = null;
		}
	});

	test('renders at least one feed entry from followed runner', async ({ page }) => {
		await page.goto('/social?tab=feed');
		await expect(page.getByText(/Jared/).first()).toBeVisible({
			timeout: 10_000
		});
	});

	test('activity-type filter narrows to a no-match empty state on Cycle', async ({
		page
	}) => {
		await page.goto('/social?tab=feed');
		await page.getByRole('button', { name: 'Cycle' }).click();
		await expect(
			page.getByRole('heading', { name: 'No matches' })
		).toBeVisible({ timeout: 10_000 });
	});
});
