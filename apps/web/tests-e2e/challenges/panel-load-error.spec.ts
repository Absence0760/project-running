import { expect, test } from '@playwright/test';

import { USER_B } from '../fixtures/users';

/**
 * ChallengesPanel (/dashboard) — a failed my_active_challenges fetch must
 * surface a distinct error, NOT silently coerce to the self-hiding
 * "not in any challenge" state.
 *
 * Before the fix the panel did `.catch(() => { challenges = []; })`, so a
 * real failure rendered nothing — identical to a genuinely un-joined user.
 * The component now tracks `loadError` and shows an alert with a retry.
 */

test.describe('ChallengesPanel — load failure', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('a failed my_active_challenges fetch shows the error strip with a retry', async ({
		page
	}) => {
		await page.route('**/rest/v1/rpc/my_active_challenges*', async (route) => {
			await route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated my_active_challenges failure' })
			});
		});

		await page.goto('/dashboard');

		const strip = page.locator('section.challenges-strip', { hasText: "Couldn't load challenges." });
		await expect(strip).toBeVisible({ timeout: 10_000 });
		await expect(strip.getByRole('button', { name: 'Retry' })).toBeVisible();
	});
});
