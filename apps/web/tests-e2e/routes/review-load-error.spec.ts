import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

/**
 * /routes/[id] — when the reviews query fails, the reviews section
 * shows an explicit "couldn't load" line instead of silently
 * rendering the empty "No reviews yet" state (which used to make a
 * load failure indistinguishable from a route that genuinely has no
 * reviews). The route fetch itself is left untouched so the page
 * still renders.
 */

test.describe('/routes/[id] reviews — load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed reviews fetch shows the error line, not the empty state', async ({
		page
	}) => {
		await page.route('**/rest/v1/route_reviews*', (route) =>
			route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated reviews failure' })
			})
		);

		await page.goto(`/routes/${RUNNER_PUBLIC_ROUTE_ID}`);

		await expect(page.locator('.reviews-error')).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.reviews-error')).toHaveText(
			"Couldn't load reviews. Try refreshing."
		);
		await expect(page.getByText('No reviews yet')).toHaveCount(0);
	});
});
