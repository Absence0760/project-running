import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /u/[id]?tab=achievements (BadgeGrid) — a failed fetchUserBadges must show a
 * distinct error + retry banner, NOT the friendly "No badges yet" empty grid.
 *
 * Before the fix loadBadges did `.catch(() => { badges = []; })`, so a real
 * network / RLS failure rendered the same empty grid a badge-less runner
 * sees — masking a broken fetch as "you have no achievements". The page now
 * tracks `badgesError` and renders an alert with a retry.
 */

test.describe('/u/[id]?tab=achievements — load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed achievements fetch shows the error banner, not the empty grid', async ({
		page
	}) => {
		await page.route('**/rest/v1/achievements?*', async (route) => {
			if (route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated achievements failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto(`/u/${USER_A.id}?tab=achievements`);

		const banner = page.getByRole('alert').filter({ hasText: "Couldn't load achievements." });
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner.getByRole('button', { name: 'Retry' })).toBeVisible();
		// The genuinely-empty copy must NOT be what the user sees.
		await expect(page.getByText('No badges yet', { exact: false })).toHaveCount(0);
	});

	test('Retry re-fetches and clears the error on a healthy response', async ({ page }) => {
		let failNext = true;
		await page.route('**/rest/v1/achievements?*', async (route) => {
			if (route.request().method() !== 'GET') {
				await route.continue();
				return;
			}
			if (failNext) {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated achievements failure' })
				});
			} else {
				await route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify([])
				});
			}
		});

		await page.goto(`/u/${USER_A.id}?tab=achievements`);
		const banner = page.getByRole('alert').filter({ hasText: "Couldn't load achievements." });
		await expect(banner).toBeVisible({ timeout: 10_000 });

		await banner.getByRole('button', { name: 'Retry' }).click();

		// The retry succeeds (empty result): the error clears and the empty grid
		// takes its place.
		await expect(banner).toHaveCount(0, { timeout: 10_000 });
	});
});
