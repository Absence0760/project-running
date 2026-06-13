import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /plans — a failed plans fetch must show a "couldn't load — retry" state,
 * NOT an empty "No plans yet" that's indistinguishable from a brand-new
 * account. Pins the fetchMyPlansWithError contract + the page's loadError
 * branch + retry recovery. Mirrors the existing /routes loadError pattern.
 */
test.describe('/plans load error', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed load shows an error + retry, and retry recovers', async ({ page }) => {
		let failNext = true;
		await page.route('**/rest/v1/training_plans**', async (route) => {
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

		await page.goto('/plans');

		// Error state, not the empty state.
		await expect(page.locator('.error-banner')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('heading', { name: 'No plans yet.' })).toHaveCount(0);

		// Retry re-fetches (now unblocked) → the seeded plan appears.
		await page.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByRole('heading', { name: 'Richmond Half 2026' })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.locator('.error-banner')).toHaveCount(0);
	});
});
