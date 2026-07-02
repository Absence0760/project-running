import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

/**
 * /routes/[id] (SegmentsPanel) — a failed segments fetch must render a
 * distinct error + retry state, NOT stick on the "Loading segments…"
 * spinner forever.
 *
 * Before the fix, load() had no try/catch/finally and fetchSegmentsForRoute
 * swallowed the error to []; a rejection left the spinner up permanently.
 * fetchSegmentsForRouteWithError + the component error state fix both.
 */

test.describe('/routes/[id] — SegmentsPanel load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed segments fetch shows the error banner, not the stuck spinner', async ({
		page
	}) => {
		await page.route('**/rest/v1/segments*', async (route) => {
			if (route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated segments failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);

		const banner = page.locator('.error-banner', { hasText: "Couldn't load your routes." });
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner.getByRole('button', { name: 'Retry' })).toBeVisible();
		// The perpetual "Loading segments…" must have cleared.
		await expect(page.getByText('Loading segments…')).toHaveCount(0);
	});
});
