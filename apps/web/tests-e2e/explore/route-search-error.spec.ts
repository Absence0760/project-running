import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /routes?tab=explore — when the public-route search RPC fails, the
 * Explore surface shows a retry affordance instead of the misleading
 * "no matches" empty state (which used to be indistinguishable from a
 * genuine load failure — searchPublicRoutes swallowed the error to []).
 */

test.describe('/routes?tab=explore — search failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('a failed search shows a retry card, not the empty state', async ({ page }) => {
		await page.route('**/rest/v1/rpc/search_public_routes*', (route) =>
			route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated search failure' })
			})
		);

		await page.goto('/routes?tab=explore');

		await expect(page.getByText("Couldn't load routes", { exact: true })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByRole('button', { name: 'Try again' })).toBeVisible();
		// Not the legitimately-empty state.
		await expect(page.getByText('No public routes here yet')).toHaveCount(0);
	});
});
