import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /social — top-level social hub page chrome: ARIA tab strip with
 * Feed · People · Clubs in that order, ?tab= URL state, and the two
 * legacy URLs (/clubs, /feed) that redirect here. Per-tab specs live
 * in social/people.spec.ts and social/feed.spec.ts.
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
