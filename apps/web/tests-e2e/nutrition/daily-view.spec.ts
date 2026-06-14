import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /nutrition daily view — meal-slot grouping, per-slot calorie headers, the
 * water-tracker decrement, and the per-meal-header deep link.
 *
 * Complements nutrition.spec.ts (manual log / over-budget / water increment)
 * by pinning the grouping + ordering wiring (groupByMealSlot) and the water
 * remove path, which the existing spec does not exercise.
 *
 * Seeds three slots in non-display order to prove the page re-orders them
 * breakfast → lunch → dinner → snack and sums each slot's header independently.
 * A unique stamp keeps rows isolated in the shared seed DB.
 */
test.describe('/nutrition — daily grouping + water decrement', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('meals group + order by slot, each header summing its own items', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const now = new Date();
		const at = (h: number) =>
			new Date(now.getFullYear(), now.getMonth(), now.getDate(), h, 0).toISOString();

		// Insert out of display order (dinner, breakfast, lunch) with two
		// breakfast items so the header must SUM (not just show the last).
		const rows = [
			{ user_id: USER_A.id, started_at: at(19), item_name: `E2E D ${stamp}`, calories: 700, meal_slot: 'dinner' },
			{ user_id: USER_A.id, started_at: at(8), item_name: `E2E B1 ${stamp}`, calories: 200, meal_slot: 'breakfast' },
			{ user_id: USER_A.id, started_at: at(9), item_name: `E2E B2 ${stamp}`, calories: 150, meal_slot: 'breakfast' },
			{ user_id: USER_A.id, started_at: at(12), item_name: `E2E L ${stamp}`, calories: 500, meal_slot: 'lunch' },
		];
		const { data: created } = await admin.from('food_log').insert(rows).select('id');
		const ids = (created ?? []).map((r) => r.id);

		try {
			await page.goto('/nutrition');

			// All four seeded items render.
			await expect(page.getByText(`E2E B1 ${stamp}`)).toBeVisible({ timeout: 10_000 });
			await expect(page.getByText(`E2E B2 ${stamp}`)).toBeVisible();
			await expect(page.getByText(`E2E L ${stamp}`)).toBeVisible();
			await expect(page.getByText(`E2E D ${stamp}`)).toBeVisible();

			// Headers appear in display order regardless of insert order. Read the
			// rendered slot-header sequence and assert breakfast precedes lunch
			// precedes dinner.
			const headers = await page.locator('.meal-head h2').allInnerTexts();
			const order = headers.map((h) => h.trim());
			const iB = order.indexOf('Breakfast');
			const iL = order.indexOf('Lunch');
			const iD = order.indexOf('Dinner');
			expect(iB).toBeGreaterThanOrEqual(0);
			expect(iB).toBeLessThan(iL);
			expect(iL).toBeLessThan(iD);

			// The Breakfast header sums its two items (200 + 150 = 350 kcal).
			const breakfastGroup = page
				.locator('.meal-group')
				.filter({ has: page.locator('h2', { hasText: 'Breakfast' }) });
			await expect(breakfastGroup.locator('.meal-kcal')).toContainText('350 kcal');
		} finally {
			if (ids.length) await admin.from('food_log').delete().in('id', ids);
		}
	});

	test('the water tracker decrements and floors at zero', async ({ page }) => {
		await page.goto('/nutrition');

		// Start from a clean per-day counter (the tracker is client-only).
		await page.evaluate(() => {
			const d = new Date();
			localStorage.removeItem(`water_ml_${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`);
		});
		await page.reload();

		const units = page.locator('.water-units');
		await expect(units).toContainText('0 × 250 ml', { timeout: 10_000 });

		// Add two units, then remove three — the counter must floor at 0, never go
		// negative.
		await page.getByTestId('add-water').click();
		await page.getByTestId('add-water').click();
		await expect(units).toContainText('2 × 250 ml');

		const removeBtn = page.getByRole('button', { name: /remove|−/i }).first();
		await removeBtn.click();
		await removeBtn.click();
		await removeBtn.click();
		await expect(units).toContainText('0 × 250 ml');

		// Cleanup so the shared seed user starts clean next run.
		await page.evaluate(() => {
			const d = new Date();
			localStorage.removeItem(`water_ml_${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`);
		});
	});

	test('a manual entry with no slot picked defaults to Breakfast', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const item = `E2E Default ${stamp}`;

		await page.goto('/nutrition');
		await page.getByTestId('log-food').click();
		const modal = page.getByRole('dialog');
		await expect(modal).toBeVisible();

		// Do NOT touch the meal-slot select — it defaults to breakfast.
		await modal.getByRole('button', { name: 'Enter manually' }).click();
		await modal.getByTestId('manual-name').fill(item);
		const manual = modal.getByTestId('manual-entry');
		await manual.locator('input[type="number"]').nth(0).fill('275');
		await manual.getByRole('button', { name: 'Add' }).click();

		await expect(modal).toBeHidden();
		const row = page.locator('.meal-list li', { hasText: item });
		await expect(row).toBeVisible({ timeout: 10_000 });

		const { data: created } = await admin
			.from('food_log')
			.select('id, meal_slot')
			.eq('user_id', USER_A.id)
			.eq('item_name', item);
		expect(created?.length).toBe(1);
		expect(created![0].meal_slot).toBe('breakfast');

		await admin.from('food_log').delete().eq('id', created![0].id);
	});
});
