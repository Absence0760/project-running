import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Accessible-name pins for icon-only controls surfaced by a UX-hunt round:
 *   - the shared Modal close button (was a hardcoded English aria-label)
 *   - the RouteExplorer clear-search button (was unlabelled)
 * Both must expose a localized accessible name so screen-reader users can
 * find them.
 */
test.describe('icon-only control accessible names', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the shared Modal close button has an accessible name', async ({ page }) => {
		await page.goto('/plans');
		await page.getByRole('button', { name: /New plan/ }).first().click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		// The close button is reachable by its accessible name ("Close").
		await expect(modal.getByRole('button', { name: 'Close' })).toBeVisible();
	});

	test('the RouteExplorer clear-search button has an accessible name', async ({ page }) => {
		await page.goto('/routes?tab=explore');
		const search = page.getByPlaceholder(/Search routes by name/);
		await expect(search).toBeVisible({ timeout: 10_000 });
		await search.fill('park');
		const clear = page.getByRole('button', { name: 'Clear search' });
		await expect(clear).toBeVisible();
		await clear.click();
		await expect(search).toHaveValue('');
	});
});
