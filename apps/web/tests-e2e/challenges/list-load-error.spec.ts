import { expect, test } from '@playwright/test';

import { USER_B } from '../fixtures/users';

/**
 * /challenges (My challenges) — a failed fetchChallenges({ mine: true }) must
 * surface a distinct error + retry, NOT the friendly "No challenges yet."
 * empty state.
 *
 * Before the fix loadMine did `.catch(() => { mine = []; })`, so a real
 * network / RLS failure rendered the empty My-challenges copy — telling a
 * user they're in no challenges when the fetch actually failed. The page
 * now tracks `mineError` and renders an alert with a retry.
 */

test.describe('/challenges — My-challenges load failure', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('a failed challenges fetch shows the error strip, not the empty state', async ({
		page
	}) => {
		await page.route('**/rest/v1/challenges?*', async (route) => {
			if (route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated challenges failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto('/challenges');

		const banner = page.getByRole('alert').filter({ hasText: "Couldn't load challenges." });
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner.getByRole('button', { name: 'Retry' })).toBeVisible();
		// The genuinely-empty copy must NOT be what the user sees.
		await expect(page.getByText('No challenges yet.')).toHaveCount(0);
	});

	test('Retry re-fetches and clears the error on a healthy response', async ({ page }) => {
		let failNext = true;
		await page.route('**/rest/v1/challenges?*', async (route) => {
			if (route.request().method() !== 'GET') {
				await route.continue();
				return;
			}
			if (failNext) {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated challenges failure' })
				});
			} else {
				await route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify([])
				});
			}
		});

		await page.goto('/challenges');
		const banner = page.getByRole('alert').filter({ hasText: "Couldn't load challenges." });
		await expect(banner).toBeVisible({ timeout: 10_000 });

		await banner.getByRole('button', { name: 'Retry' }).click();

		// The retry succeeds (empty result): the error clears and the friendly
		// empty state takes its place.
		await expect(banner).toHaveCount(0, { timeout: 10_000 });
		await expect(page.getByText('No challenges yet.')).toBeVisible({ timeout: 10_000 });
	});
});
