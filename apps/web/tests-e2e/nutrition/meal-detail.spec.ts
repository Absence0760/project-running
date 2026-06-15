import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /nutrition/[date]/[slot] — the per-meal detail route reached by tapping a
 * meal-slot header on /nutrition.
 *
 * The pure shaping (entriesForSlotOnDay + slotCalorieTrend) is unit-tested in
 * meal_detail*.test.ts; this pins the Svelte wiring end to end: the macro
 * roll-up for a single slot on a single day, the items list, the trailing
 * 7-day trend bars (which must come from the same fetch and zero-fill empty
 * days), the cross-slot isolation (a lunch entry must not bleed into the
 * breakfast detail), and the invalid-slot guard.
 *
 * Seed rows carry a unique stamp so assertions + cleanup never collide with
 * other rows in the shared seed DB.
 */
test.describe('/nutrition/[date]/[slot] — per-meal detail', () => {
	test.use({ storageState: USER_A.storageStatePath });

	function isoDate(d: Date): string {
		const mm = String(d.getMonth() + 1).padStart(2, '0');
		const dd = String(d.getDate()).padStart(2, '0');
		return `${d.getFullYear()}-${mm}-${dd}`;
	}

	test('breakfast detail rolls up only this slot, lists items, and renders a 7-day trend', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const today = new Date();
		const todayKey = isoDate(today);
		const yesterday = new Date(today.getTime() - 24 * 3600 * 1000);

		// USER_A is the seed user (runner@test.com), whose seed food_log carries
		// today-relative items in every slot across the trailing week — they'd
		// land in both the day roll-up and the 7-day trend and break the exact
		// assertions below. Clear the recent window first so the roll-up + trend
		// reflect only the items this test controls.
		const since = new Date(Date.now() - 8 * 24 * 3600 * 1000).toISOString();
		await admin.from('food_log').delete().eq('user_id', USER_A.id).gte('started_at', since);

		// Two breakfast items today + one breakfast item yesterday (in the 7-day
		// trend window but not the day roll-up) + a lunch item today that must be
		// excluded from the breakfast roll-up entirely.
		const rows = [
			{
				user_id: USER_A.id,
				started_at: new Date(today.getFullYear(), today.getMonth(), today.getDate(), 8, 0).toISOString(),
				item_name: `E2E Eggs ${stamp}`,
				calories: 200,
				protein_g: 18,
				carbs_g: 2,
				fat_g: 14,
				meal_slot: 'breakfast',
			},
			{
				user_id: USER_A.id,
				started_at: new Date(today.getFullYear(), today.getMonth(), today.getDate(), 8, 30).toISOString(),
				item_name: `E2E Toast ${stamp}`,
				calories: 150,
				protein_g: 5,
				carbs_g: 28,
				fat_g: 3,
				meal_slot: 'breakfast',
			},
			{
				user_id: USER_A.id,
				started_at: new Date(yesterday.getFullYear(), yesterday.getMonth(), yesterday.getDate(), 8, 0).toISOString(),
				item_name: `E2E Oatmeal ${stamp}`,
				calories: 300,
				meal_slot: 'breakfast',
			},
			{
				user_id: USER_A.id,
				started_at: new Date(today.getFullYear(), today.getMonth(), today.getDate(), 12, 0).toISOString(),
				item_name: `E2E Sandwich ${stamp}`,
				calories: 999,
				meal_slot: 'lunch',
			},
		];
		const { data: created } = await admin.from('food_log').insert(rows).select('id');
		const ids = (created ?? []).map((r) => r.id);

		try {
			await page.goto(`/nutrition/${todayKey}/breakfast`);

			await expect(page.getByRole('heading', { name: 'Breakfast' })).toBeVisible({
				timeout: 10_000,
			});

			// Macro roll-up = the two breakfast items only (200 + 150 = 350 kcal,
			// 23 g protein) — the lunch sandwich must NOT be counted.
			const macros = page.getByTestId('meal-macros');
			await expect(macros).toContainText('350');
			await expect(macros).toContainText('23g'); // protein 18 + 5

			// Both breakfast items render; the lunch item does not.
			await expect(page.getByText(`E2E Eggs ${stamp}`)).toBeVisible();
			await expect(page.getByText(`E2E Toast ${stamp}`)).toBeVisible();
			await expect(page.getByText(`E2E Sandwich ${stamp}`)).toHaveCount(0);

			// The 7-day trend renders exactly 7 day columns; yesterday's breakfast
			// (300) shows in the trend even though it is outside the day roll-up.
			const trend = page.getByTestId('meal-trend');
			await expect(trend).toBeVisible();
			await expect(trend.locator('.trend-col')).toHaveCount(7);
			await expect(trend).toContainText('350'); // today's breakfast bar value
			await expect(trend).toContainText('300'); // yesterday's breakfast bar value
		} finally {
			if (ids.length) await admin.from('food_log').delete().in('id', ids);
		}
	});

	test('a slot with nothing logged shows the empty items state but still a 7-day trend', async ({
		page,
	}) => {
		const today = new Date();
		// Dinner today is empty for the seed user on a fresh run; the day macros
		// read 0 kcal and the items list shows the empty hint, but the trend axis
		// is still seven stable columns.
		await page.goto(`/nutrition/${isoDate(today)}/dinner`);

		await expect(page.getByRole('heading', { name: 'Dinner' })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('meal-trend').locator('.trend-col')).toHaveCount(7);
	});

	test('an unknown slot renders the invalid-slot guard, not a crash', async ({ page }) => {
		const today = new Date();
		await page.goto(`/nutrition/${isoDate(today)}/brunch`);
		// validSlot is false → the invalid-slot copy renders; no meal heading.
		await expect(page.getByRole('heading', { name: 'Brunch' })).toHaveCount(0);
		await expect(page.getByText("That meal slot doesn't exist.")).toBeVisible({ timeout: 10_000 });
	});
});
