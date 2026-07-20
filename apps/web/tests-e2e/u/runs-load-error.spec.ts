import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /u/[id] — a failed runs fetch must scope to the Runs tab (its own error +
 * retry banner), leaving the header and the other sections (Followers /
 * Following) rendered — NOT blank the whole page with "Couldn't load this
 * profile.".
 *
 * The profile page used to bundle summary + runs + followers + following +
 * block-state into one Promise.all under a single loadError, so any one
 * rejecting rendered the whole-page error even for sections that loaded fine.
 * Each independent section now owns its own loading / error / retry; only the
 * header summary gates the page. Web counterpart of the mobile fix in #508.
 */

test.describe('/u/[id]?tab=runs — load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed runs fetch scopes to the Runs tab and leaves the rest rendered', async ({
		page
	}) => {
		await page.route('**/rest/v1/public_runs*', async (route) => {
			if (route.request().method() === 'GET') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated runs failure' })
				});
			} else {
				await route.continue();
			}
		});

		await page.goto(`/u/${USER_A.id}?tab=runs`);

		// The Runs tab surfaces a scoped error + retry.
		const banner = page.getByRole('alert').filter({ hasText: "Couldn't load this section." });
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner.getByRole('button', { name: 'Retry' })).toBeVisible();

		// The page did NOT blank: the header (tab strip) rendered and the
		// whole-page error is absent.
		await expect(page.getByRole('tab', { name: 'Runs' })).toBeVisible();
		await expect(page.getByText("Couldn't load this profile.")).toHaveCount(0);

		// A neighbouring section that loaded fine shows its content, not the
		// scoped error — proving the failure is isolated to Runs.
		await page.getByRole('tab', { name: 'Followers' }).click();
		await expect(page.getByText("Couldn't load this section.")).toHaveCount(0);
	});

	test('Retry re-fetches and clears the Runs error on a healthy response', async ({ page }) => {
		let failNext = true;
		await page.route('**/rest/v1/public_runs*', async (route) => {
			if (route.request().method() !== 'GET') {
				await route.continue();
				return;
			}
			if (failNext) {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated runs failure' })
				});
			} else {
				await route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify([])
				});
			}
		});

		await page.goto(`/u/${USER_A.id}?tab=runs`);
		const banner = page.getByRole('alert').filter({ hasText: "Couldn't load this section." });
		await expect(banner).toBeVisible({ timeout: 10_000 });

		await banner.getByRole('button', { name: 'Retry' }).click();

		// The retry succeeds (empty result): the error clears.
		await expect(banner).toHaveCount(0, { timeout: 10_000 });
	});
});
