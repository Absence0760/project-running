import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /gym — a rejected read must not leave the page on its skeleton.
 *
 * `load()` put four reads in one Promise.all, and `fetchSessionPlans` rethrows
 * rather than returning an error field. Its rejection escaped the await, so
 * `loading = false` never ran and the page skeletoned indefinitely — while the
 * retry banner written for exactly this case sat unreachable below it.
 */
test.describe('/gym — a throwing read still resolves the page', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed session-plan read shows the retry banner, not a forever skeleton', async ({
		page,
	}) => {
		let failNext = true;
		await page.route('**/rest/v1/session_plans*', (route) => {
			if (failNext) {
				failNext = false;
				return route.fulfill({ status: 500, body: 'boom' });
			}
			return route.continue();
		});

		await page.goto('/gym');

		const banner = page.getByTestId('gym-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');

		// Recovering through the banner's own retry resolves the page.
		await banner.getByRole('button').click();
		await expect(page.getByTestId('gym-load-error')).toHaveCount(0, { timeout: 15_000 });
	});
});
