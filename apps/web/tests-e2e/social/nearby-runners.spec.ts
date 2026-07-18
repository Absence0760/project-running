import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Opt-in "runners nearby" discovery (issue #466) is gated behind the default-
 * OFF `PUBLIC_ENABLE_NEARBY_RUNNERS` feature flag pending owner + CISO/counsel
 * sign-off (person-location is Art 9-adjacent data). The test build does not
 * set the flag, so the whole person-location surface must be absent — no
 * "Runners nearby" section on the People tab, no coarse-area setter in
 * Settings → Preferences. This pins the fail-closed render gate.
 */
test.describe('runners nearby — default-off gate', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the nearby section is absent on the People tab by default', async ({ page }) => {
		await page.goto('/social?tab=people');
		await expect(page.getByPlaceholder('Search runners by name')).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByRole('heading', { name: 'Runners nearby' })).toHaveCount(0);
	});

	test('the coarse-area setter is absent in Preferences by default', async ({ page }) => {
		await page.goto('/settings/preferences');
		// The existing search opt-out row must render (proves the section loaded)…
		await expect(page.getByText('Show me in name search')).toBeVisible({ timeout: 10_000 });
		// …while the nearby opt-in + area setter stay gated off.
		await expect(page.getByText('Show me in Runners nearby')).toHaveCount(0);
		await expect(page.getByTestId('nearby-area-status')).toHaveCount(0);
	});
});
