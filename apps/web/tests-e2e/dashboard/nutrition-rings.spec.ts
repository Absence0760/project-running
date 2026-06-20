import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /dashboard — today's-nutrition rings card (multi_modal.md § Home; the
 * remaining piece of the Home-redesign roadmap row).
 *
 * The card is a "today's modality" surface mirroring the today's-lift card +
 * the mobile NutritionRingsCard: it self-hides when no food was logged today,
 * and renders when there is. This pins both halves of that self-hiding
 * contract by controlling the seed user's TODAY window directly.
 *
 * USER_A is the seed user (runner@test.com), whose seed food_log carries
 * today-relative items — so the absent case must first clear today's window.
 */
test.describe('/dashboard — today nutrition rings', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('card hides with no food today, appears once a meal is logged', async ({ page }) => {
		const admin = getAdminClient();
		// The test browser runs in UTC (playwright.config timezoneId), so the
		// dashboard's local-day "today" window is the UTC day. Compute the same
		// window here in UTC so the seeded rows land inside it.
		const now = new Date();
		const todayStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
		const tomorrow = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1));
		const stamp = Date.now();
		const item = `E2E Dash Meal ${stamp}`;

		// Clear today's food so the card has nothing to show.
		await admin
			.from('food_log')
			.delete()
			.eq('user_id', USER_A.id)
			.gte('started_at', todayStart.toISOString())
			.lt('started_at', tomorrow.toISOString());

		let insertedId: string | null = null;
		try {
			// Absent: no food logged today → the rings card never renders.
			await page.goto('/dashboard');
			// Wait for the dashboard to finish loading (the source-filter row only
			// renders post-load) before asserting absence, so we don't pass on a
			// still-loading skeleton. loadTodaysNutrition runs after that paint.
			await expect(page.getByRole('button', { name: 'All', exact: true })).toBeVisible({
				timeout: 15_000,
			});
			await expect(page.getByTestId('dash-nutrition-rings')).toHaveCount(0);

			// Log a meal today (09:00 UTC, inside the dashboard's today window),
			// then reload: the card now appears.
			const at = new Date(
				Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 9, 0),
			).toISOString();
			const { data: created } = await admin
				.from('food_log')
				.insert({
					user_id: USER_A.id,
					started_at: at,
					item_name: item,
					calories: 420,
					protein_g: 18,
					carbs_g: 50,
					fat_g: 14,
					meal_slot: 'breakfast',
				})
				.select('id')
				.single();
			insertedId = created?.id ?? null;

			await page.goto('/dashboard');
			const card = page.getByTestId('dash-nutrition-rings');
			await expect(card).toBeVisible({ timeout: 15_000 });
			// The card links to the full Nutrition surface.
			await expect(card).toHaveAttribute('href', '/nutrition');
			// The calories ring shows today's consumed total.
			await expect(card).toContainText('420');
		} finally {
			if (insertedId) await admin.from('food_log').delete().eq('id', insertedId);
		}
	});
});
