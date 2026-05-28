import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Comeback-persona finding #24: a returning runner types an old 5K PR and
 * the plan engine treats it as current fitness, prescribing paces that are
 * too fast (injury risk). The wizard must not anchor paces on the entered
 * time until the runner confirms it reflects current fitness.
 *
 * This drives only the PlanEditor modal (no plan is created), so there is
 * no server state to clean up.
 */
test.describe('/plans/new — recent-5K recency gate', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('entered-but-unconfirmed 5K time warns; confirming clears it', async ({ page }) => {
		await page.goto('/plans');
		await page.getByRole('button', { name: /New plan/ }).first().click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });

		const recentFieldset = modal.locator('fieldset', { hasText: 'Recent 5K time' });
		const confirm = modal.getByText('reflects my current fitness');
		const warning = modal.getByText('too fast for a returning runner');

		// Nothing shown until a time is entered.
		await expect(confirm).toBeHidden();
		await expect(warning).toBeHidden();

		// Enter a 5K minutes value -> confirm box + warning appear.
		await recentFieldset.locator('input[type="number"]').first().fill('22');
		await expect(confirm).toBeVisible();
		await expect(warning).toBeVisible();

		// Confirming current fitness clears the warning.
		await modal.getByRole('checkbox').check();
		await expect(warning).toBeHidden();
	});
});
