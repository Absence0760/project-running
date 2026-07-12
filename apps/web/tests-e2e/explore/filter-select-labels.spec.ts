import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Accessible-name pins for the RouteExplorer filter selects (UX-hunt web #4):
 * the distance, surface, and sort `<select>` filters on /routes?tab=explore
 * had no label, so a screen reader announced three unnamed comboboxes. Each
 * now carries a localized aria-label; assert every filter is reachable by an
 * accessible name.
 */
test.describe('RouteExplorer filter selects have accessible names', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('distance, surface, and sort filters each expose an accessible name', async ({ page }) => {
		await page.goto('/routes?tab=explore');
		await expect(page.getByPlaceholder(/Search routes by name/)).toBeVisible({ timeout: 10_000 });

		await expect(page.getByRole('combobox', { name: 'Filter by distance' })).toBeVisible();
		await expect(page.getByRole('combobox', { name: 'Filter by surface' })).toBeVisible();
		await expect(page.getByRole('combobox', { name: 'Sort routes' })).toBeVisible();
	});

	test('no filter combobox is left without an accessible name', async ({ page }) => {
		await page.goto('/routes?tab=explore');
		await expect(page.getByPlaceholder(/Search routes by name/)).toBeVisible({ timeout: 10_000 });

		const unnamed = page.locator('.filters select:not([aria-label]):not([aria-labelledby])');
		await expect(unnamed).toHaveCount(0);
	});
});
