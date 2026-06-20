import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /nutrition — meal templates (docs/features/multi_modal.md § Nutrition mid
 * tier; migration 20270218_001).
 *
 * The save-as-meal → one-tap-log loop end to end: log a food item, save the
 * day as a named template (the templates section self-hides until one exists),
 * confirm the meal_templates + meal_template_items rows landed owner-scoped,
 * log the template with one tap (a new food_log row appears), then delete the
 * template behind the confirm dialog (and confirm the already-logged entries
 * stay in the diary — the link is a parallel plan, not an FK).
 *
 * A unique name per run keeps assertions + cleanup from colliding in the
 * shared seed DB.
 */
test.describe('/nutrition — meal templates', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('save a meal as a template → one-tap log → delete', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const item = `E2E Template Oats ${stamp}`;
		const templateName = `E2E Breakfast ${stamp}`;

		// Seed one logged entry today so "Save as meal" has something to capture.
		const { data: seedEntry } = await admin
			.from('food_log')
			.insert({
				user_id: USER_A.id,
				started_at: new Date().toISOString(),
				item_name: item,
				calories: 300,
				protein_g: 10,
				meal_slot: 'breakfast',
			})
			.select('id')
			.single();

		let templateId: string | null = null;
		try {
			await page.goto('/nutrition');
			const row = page.locator('.meal-list li', { hasText: item });
			await expect(row).toBeVisible({ timeout: 10_000 });

			// Save today's meals as a named template.
			await page.getByTestId('save-as-meal').click();
			const saveModal = page.getByRole('dialog');
			await expect(saveModal).toBeVisible();
			await saveModal.getByTestId('meal-name').fill(templateName);
			await saveModal.getByTestId('confirm-save-meal').click();
			await expect(saveModal).toBeHidden({ timeout: 10_000 });

			// The template row appears in the self-hiding templates section.
			const templateRow = page
				.getByTestId('meal-templates')
				.locator('.template-row', { hasText: templateName });
			await expect(templateRow).toBeVisible({ timeout: 10_000 });

			// Backend rows landed owner-scoped, with the item nested.
			const { data: tmpl } = await admin
				.from('meal_templates')
				.select('id, name, item_count, meal_slot, user_id')
				.eq('user_id', USER_A.id)
				.eq('name', templateName);
			expect(tmpl?.length).toBe(1);
			templateId = tmpl![0].id;
			expect(tmpl![0].item_count).toBe(1);
			expect(tmpl![0].meal_slot).toBe('breakfast');
			const { data: items } = await admin
				.from('meal_template_items')
				.select('item_name, calories, meal_slot')
				.eq('template_id', templateId);
			expect(items?.length).toBe(1);
			expect(items![0].item_name).toBe(item);
			expect(Number(items![0].calories)).toBe(300);

			// One-tap log: the template's items become new food_log rows.
			const beforeCount = (
				await admin
					.from('food_log')
					.select('id')
					.eq('user_id', USER_A.id)
					.eq('item_name', item)
			).data!.length;
			await templateRow.getByTestId('log-template').click();
			await expect
				.poll(
					async () =>
						(
							await admin
								.from('food_log')
								.select('id')
								.eq('user_id', USER_A.id)
								.eq('item_name', item)
						).data!.length,
					{ timeout: 10_000 },
				)
				.toBe(beforeCount + 1);

			// Delete the template behind the confirm dialog.
			await templateRow.getByRole('button', { name: `Delete ${templateName}` }).click();
			const delDialog = page.locator('.modal', { hasText: 'Delete this meal template?' });
			await expect(delDialog).toBeVisible({ timeout: 5_000 });
			await delDialog.getByRole('button', { name: 'Delete', exact: true }).click();
			await expect(templateRow).toHaveCount(0, { timeout: 10_000 });

			// The template (and its items, by cascade) is gone…
			const { data: afterTmpl } = await admin
				.from('meal_templates')
				.select('id')
				.eq('id', templateId);
			expect(afterTmpl?.length ?? 0).toBe(0);
			templateId = null;
			// …but the food_log entries it logged remain (parallel plan, no FK).
			const { data: stillLogged } = await admin
				.from('food_log')
				.select('id')
				.eq('user_id', USER_A.id)
				.eq('item_name', item);
			expect((stillLogged?.length ?? 0)).toBeGreaterThanOrEqual(1);
		} finally {
			if (templateId) await admin.from('meal_templates').delete().eq('id', templateId);
			await admin.from('food_log').delete().eq('user_id', USER_A.id).eq('item_name', item);
			if (seedEntry) await admin.from('food_log').delete().eq('id', seedEntry.id);
		}
	});
});
