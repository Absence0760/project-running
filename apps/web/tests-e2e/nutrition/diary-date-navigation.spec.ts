import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /nutrition day navigation — the diary is no longer today-only.
 *
 * `/nutrition` used to resolve every window from `new Date()`, so a forgotten
 * yesterday could never be back-filled and no past day could be reviewed. This
 * spec pins the three halves of the fix: the URL owns the day (`?date=`), a
 * past day shows that day's entries rather than today's, and a food logged
 * while a past day is showing is written onto THAT day — the part a unit test
 * cannot reach, because it is the composer's write timestamp travelling
 * through `createFoodEntry`.
 *
 * The fail-closed resolution (future / malformed `?date=` → today) is unit
 * tested in `diary_day.test.ts`; one case is re-checked here to prove the page
 * actually routes through it.
 */
test.describe('/nutrition — diary day navigation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	/// Local `YYYY-MM-DD`, `offsetDays` calendar days from today. Stepped
	/// through the calendar, never by 24 h (decisions.md § 589).
	function localDate(offsetDays: number): string {
		const n = new Date();
		const d = new Date(n.getFullYear(), n.getMonth(), n.getDate() + offsetDays);
		const mm = String(d.getMonth() + 1).padStart(2, '0');
		const dd = String(d.getDate()).padStart(2, '0');
		return `${d.getFullYear()}-${mm}-${dd}`;
	}

	/// Local noon on the day `offsetDays` from today, as an instant.
	function noonOn(offsetDays: number): string {
		const n = new Date();
		return new Date(n.getFullYear(), n.getMonth(), n.getDate() + offsetDays, 12, 0).toISOString();
	}

	test('stepping back shows that day only, and the URL carries it', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const todayItem = `E2E Today ${stamp}`;
		const pastItem = `E2E Yesterday ${stamp}`;

		const { data: created } = await admin
			.from('food_log')
			.insert([
				{ user_id: USER_A.id, started_at: noonOn(0), item_name: todayItem, calories: 300, meal_slot: 'lunch' },
				{ user_id: USER_A.id, started_at: noonOn(-1), item_name: pastItem, calories: 400, meal_slot: 'lunch' },
			])
			.select('id');
		const ids = (created ?? []).map((r) => r.id);

		try {
			await page.goto('/nutrition');
			await expect(page.getByTestId('diary-day')).toHaveText('Today', { timeout: 10_000 });
			await expect(page.getByText(todayItem)).toBeVisible();
			await expect(page.getByText(pastItem)).toBeHidden();

			// Forward is the boundary: today is as far as the diary goes.
			await expect(page.getByTestId('diary-next-day')).toBeDisabled();
			await expect(page.getByTestId('diary-backfill-hint')).toBeHidden();

			await page.getByTestId('diary-prev-day').click();

			await expect(page).toHaveURL(new RegExp(`\\?date=${localDate(-1)}$`));
			await expect(page.getByTestId('diary-day')).toHaveText('Yesterday');
			await expect(page.getByText(pastItem)).toBeVisible();
			await expect(page.getByText(todayItem)).toBeHidden();
			// A past day announces that logging back-fills rather than adds today.
			await expect(page.getByTestId('diary-backfill-hint')).toBeVisible();
			// The per-meal deep link follows the viewed day, not today. Matched on
			// the date prefix only — the seed account may carry other slots on
			// that day, and which one sorts first is not this test's business.
			await expect(page.locator('.meal-head-link').first()).toHaveAttribute(
				'href',
				new RegExp(`^/nutrition/${localDate(-1)}/`),
			);

			// Back to today drops the query string entirely.
			await page.getByTestId('diary-today').click();
			await expect(page).toHaveURL(/\/nutrition$/);
			await expect(page.getByTestId('diary-day')).toHaveText('Today');
			await expect(page.getByText(todayItem)).toBeVisible();
		} finally {
			if (ids.length) await admin.from('food_log').delete().in('id', ids);
		}
	});

	test('a future or malformed ?date= falls back to today', async ({ page }) => {
		await page.goto(`/nutrition?date=${localDate(3)}`);
		await expect(page.getByTestId('diary-day')).toHaveText('Today', { timeout: 10_000 });
		await expect(page.getByTestId('diary-next-day')).toBeDisabled();

		await page.goto('/nutrition?date=2026-02-30');
		await expect(page.getByTestId('diary-day')).toHaveText('Today');
	});

	test('food logged while a past day is showing is written onto that day', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const item = `E2E Backfill ${stamp}`;
		const twoDaysAgo = localDate(-2);

		await page.goto(`/nutrition?date=${twoDaysAgo}`);
		await expect(page.getByTestId('diary-day')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('diary-backfill-hint')).toBeVisible();

		await page.getByTestId('log-food').click();
		const modal = page.getByRole('dialog');
		await expect(modal).toBeVisible();
		await modal.getByTestId('meal-slot').selectOption('dinner');
		await modal.getByRole('button', { name: 'Enter manually' }).click();
		await modal.getByTestId('manual-name').fill(item);
		await modal.getByTestId('manual-entry').locator('input[type="number"]').nth(0).fill('510');
		await modal.getByTestId('manual-entry').getByRole('button', { name: 'Add' }).click();

		await expect(modal).toBeHidden();
		// Still on the day that was being viewed, with the new item on it.
		await expect(page.getByTestId('diary-day')).toBeVisible();
		await expect(page.getByText(item)).toBeVisible();

		const { data: created } = await admin
			.from('food_log')
			.select('id, started_at')
			.eq('user_id', USER_A.id)
			.eq('item_name', item);
		expect(created?.length).toBe(1);
		const at = new Date(created![0].started_at);
		const localOf = `${at.getFullYear()}-${String(at.getMonth() + 1).padStart(2, '0')}-${String(at.getDate()).padStart(2, '0')}`;
		expect(localOf).toBe(twoDaysAgo);

		// And today's view does not show it.
		await page.goto('/nutrition');
		await expect(page.getByTestId('diary-day')).toHaveText('Today');
		await expect(page.getByText(item)).toBeHidden();

		await admin.from('food_log').delete().eq('id', created![0].id);
	});
});
