import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] (RunPhotos) — a failed photo fetch must render a distinct
 * error + retry state, NOT a gallery indistinguishable from an empty one.
 *
 * Before the fix, fetchRunPhotos swallowed the PostgREST error to [], so a
 * failed load rendered the same heading-only gallery as a run that simply
 * has no photos. fetchRunPhotosWithError now surfaces the error.
 */

test.describe('/runs/[id] — RunPhotos load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed run_photos fetch shows the error banner with a retry', async ({ page }) => {
		await page.route('**/rest/v1/run_photos*', async (route) => {
			if (route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated run_photos failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);

		const banner = page.locator('.error-banner', { hasText: "Couldn't load your runs." });
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner.getByRole('button', { name: 'Retry' })).toBeVisible();
		// The "No photos on this run." empty copy must NOT be shown.
		await expect(page.getByText('No photos on this run.')).toHaveCount(0);
	});
});
