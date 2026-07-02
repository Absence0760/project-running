import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] (RunSocial) — a failed kudos/comments fetch must render a
 * distinct error, but the comment composer must STAY usable (a fetch
 * failure shouldn't strip the signed-in user's ability to comment).
 *
 * Before the fix, load() Promise.all'd both fetches with no try/catch: on
 * rejection `loading` stuck true, so the composer never rendered while the
 * header still showed "0 kudos / 0 comments". The WithError variants +
 * component error state surface the failure and keep the composer.
 */

test.describe('/runs/[id] — RunSocial load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed comments fetch shows the error but keeps the composer usable', async ({
		page
	}) => {
		await page.route('**/rest/v1/run_comments*', async (route) => {
			if (route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated run_comments failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);

		const banner = page.locator('.error-banner', { hasText: "Couldn't load your runs." });
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner.getByRole('button', { name: 'Retry' })).toBeVisible();
		// The composer survives the failure — the signed-in user can still comment.
		await expect(page.getByPlaceholder('Add a comment…')).toBeVisible();
	});
});
