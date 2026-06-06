import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /nutrition — the Phase 4 nutrition module (docs/features/multi_modal.md
 * § Nutrition).
 *
 * Covers the manual-entry logging loop end to end (the Open Food Facts
 * search path needs the network and is unit-tested in food_search.test.ts)
 * via both entry points: the standalone /nutrition/log wrapper route, and
 * the canonical capture modal opened from /nutrition (§210 "Log → a sheet"
 * IA contract). Each enters a food manually with macros + a meal slot, saves,
 * and confirms it renders under its meal-slot group with the right calories.
 * The first also exercises the water tracker increment. The
 * /nutrition routes are always reachable (the Nutrition sidebar item is always
 * present now — decisions §63 amendment ungated it).
 *
 * A unique item name per run keeps assertions + cleanup from colliding with
 * previous rows in the shared seed DB.
 */
test.describe('/nutrition — manual log, render, water', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('log a meal manually → shows on the daily view → water increments', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const item = `E2E Oats ${stamp}`;

		await page.goto('/nutrition/log');

		// Pick the meal slot, then enter manually (no DB match needed).
		await page.getByTestId('meal-slot').selectOption('breakfast');
		await page.getByRole('button', { name: 'Enter manually' }).click();
		await page.getByTestId('manual-name').fill(item);
		const manual = page.getByTestId('manual-entry');
		await manual.locator('input[type="number"]').nth(0).fill('350'); // kcal
		await manual.locator('input[type="number"]').nth(1).fill('12'); // protein
		await manual.getByRole('button', { name: 'Add' }).click();

		// Lands on /nutrition with the item under Breakfast.
		await expect(page).toHaveURL(/\/nutrition$/, { timeout: 10_000 });
		const row = page.locator('.meal-list li', { hasText: item });
		await expect(row).toBeVisible();
		await expect(row.locator('.item-kcal')).toHaveText('350');

		// Backend row exists, owned by USER_A.
		const { data: created } = await admin
			.from('food_log')
			.select('id, item_name, calories, meal_slot')
			.eq('user_id', USER_A.id)
			.eq('item_name', item);
		expect(created?.length).toBe(1);
		expect(created![0].meal_slot).toBe('breakfast');

		// Water tracker increments by one 250 ml unit.
		await page.getByTestId('add-water').click();
		await expect(page.locator('.water-units')).toContainText('1 × 250 ml');

		// Cleanup.
		await admin.from('food_log').delete().eq('id', created![0].id);
	});

	test('log a meal from the /nutrition modal → no navigation, shows on the day view', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const item = `E2E Modal Oats ${stamp}`;

		// The canonical capture entry point is now a modal on /nutrition
		// (the IA contract: "Log → a bottom sheet, not a new screen"), not a
		// navigation to /nutrition/log.
		await page.goto('/nutrition');
		await page.getByTestId('log-food').click();

		const dialog = page.getByRole('dialog');
		await expect(dialog).toBeVisible();
		await dialog.getByTestId('meal-slot').selectOption('lunch');
		await dialog.getByRole('button', { name: 'Enter manually' }).click();
		await dialog.getByTestId('manual-name').fill(item);
		const manual = dialog.getByTestId('manual-entry');
		await manual.locator('input[type="number"]').nth(0).fill('420'); // kcal
		await manual.getByRole('button', { name: 'Add' }).click();

		// The modal closes in place — the URL never leaves /nutrition.
		await expect(dialog).toBeHidden();
		await expect(page).toHaveURL(/\/nutrition$/);
		const row = page.locator('.meal-list li', { hasText: item });
		await expect(row).toBeVisible();
		await expect(row.locator('.item-kcal')).toHaveText('420');

		const { data: created } = await admin
			.from('food_log')
			.select('id, meal_slot')
			.eq('user_id', USER_A.id)
			.eq('item_name', item);
		expect(created?.length).toBe(1);
		expect(created![0].meal_slot).toBe('lunch');

		await admin.from('food_log').delete().eq('id', created![0].id);
	});
});
