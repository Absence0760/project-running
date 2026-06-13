import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /coaching — a failed roster fetch must show a "couldn't load — retry"
 * state rather than an empty roster (or, worse, an infinite spinner when
 * the load rejected). Pins the fetchMyAthletesWithError contract + the
 * loadError branch + retry recovery.
 */
test.describe('/coaching load error', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed roster load shows an error + retry, and retry recovers', async ({ page }) => {
		let failNext = true;
		await page.route('**/rest/v1/coach_athletes**', async (route) => {
			if (route.request().method() === 'GET' && failNext) {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated failure' })
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/coaching');

		await expect(page.locator('.error-banner')).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: 'Retry' }).click();

		// Retry re-fetches (now unblocked) → the roster card renders (roster
		// or empty state), error gone.
		await expect(page.getByRole('heading', { name: 'My athletes' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.locator('.error-banner')).toHaveCount(0);
	});
});
