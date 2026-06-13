import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] — a failed plan fetch must show a "couldn't load — retry"
 * state, NOT the not-found page (a query error otherwise reads as a
 * missing plan) and NOT a forever spinner (a network reject). Pins the
 * fetchPlan `error` surfacing + the loadError branch + retry recovery.
 */
const PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001'; // seeded "Richmond Half 2026"

test.describe('/plans/[id] load error', () => {
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

		await page.goto(`/plans/${PLAN_ID}`);

		// Error state — not the not-found page, not a stuck skeleton.
		await expect(page.locator('.error-banner')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByRole('heading', { name: /not found/i })).toHaveCount(0);

		await page.getByRole('button', { name: 'Retry' }).click();
		await expect(page.getByRole('heading', { name: /Richmond Half 2026/ })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.locator('.error-banner')).toHaveCount(0);
	});
});
