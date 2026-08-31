import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';
import { readRows } from '../fixtures/db-read';
import { browserDayAt, browserDayStart } from '../fixtures/dates';

/**
 * /nutrition — recipes (docs/features/multi_modal.md § Nutrition mid tier;
 * migration 20270221_001).
 *
 * The save-as-recipe → one-tap-log loop end to end, and the thing that
 * distinguishes a recipe from a meal template: logging a recipe adds ONE
 * food_log entry carrying the SUMMED ingredient macros (scaled by servings),
 * not one entry per ingredient. Two seeded items (300 + 200 kcal), saved as a
 * 2-serving recipe, log to a single entry of (300+200)/2 = 250 kcal under the
 * recipe's name. Then delete behind the confirm dialog and confirm the logged
 * meal stays (parallel plan, no FK).
 *
 * A unique name per run keeps assertions + cleanup from colliding in the
 * shared seed DB — but a recipe is built from EVERY entry on the diary's
 * current day, so a unique name cannot scope the ingredient list. `seed.sql`
 * places four meals for this same user at `now() - 8h/-5h/-4h/-1h`, and each
 * one that lands on the browser's UTC day is another ingredient: the count is
 * 2 only while the seed ran inside the 00:00–01:00 UTC hour, and 6 for any
 * seed after 08:00 UTC. That is not § 728's zone mismatch — the seed's rows are
 * on the browser's day legitimately, they are simply not this spec's — but it
 * is the same family, and `docs/testing/testing.md § Owning the day` holds the
 * rule. So this test owns today's meals for
 * its window — it clears them first, the way `meal-templates.spec.ts` does for
 * the same reason — seeds at fixed hours on the browser's own calendar day,
 * and names the two ingredients it expects rather than counting whatever is
 * there.
 */
test.describe('/nutrition — recipes', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('save ingredients as a recipe → one-tap log sums into one entry → delete', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const itemA = `E2E Recipe Beans ${stamp}`;
		const itemB = `E2E Recipe Mince ${stamp}`;
		const recipeName = `E2E Chilli ${stamp}`;

		// "Save as recipe" captures ALL of today's food_log for this user, and the
		// assertions below are about exactly two ingredients. Clear today's
		// entries first — the seed's own four meals, and anything a sibling spec
		// sharing USER_A left behind.
		await admin
			.from('food_log')
			.delete()
			.eq('user_id', USER_A.id)
			.gte('started_at', browserDayStart());

		// Seed two logged entries on the BROWSER's calendar day, at fixed hours
		// so the ingredient order is the seeding order whatever time it is.
		const { data: seedA } = await admin
			.from('food_log')
			.insert({
				user_id: USER_A.id,
				started_at: browserDayAt(0, 18),
				item_name: itemA,
				calories: 300,
				protein_g: 20,
				meal_slot: 'dinner',
			})
			.select('id')
			.single();
		const { data: seedB } = await admin
			.from('food_log')
			.insert({
				user_id: USER_A.id,
				started_at: browserDayAt(0, 19),
				item_name: itemB,
				calories: 200,
				protein_g: 30,
				meal_slot: 'dinner',
			})
			.select('id')
			.single();

		let recipeId: string | null = null;
		try {
			await page.goto('/nutrition');
			await expect(page.locator('.meal-list li', { hasText: itemA })).toBeVisible({
				timeout: 10_000,
			});

			// Save today's meals as a 2-serving recipe.
			await page.getByTestId('save-as-recipe').click();
			const saveModal = page.getByRole('dialog');
			await expect(saveModal).toBeVisible();
			await saveModal.getByTestId('recipe-name').fill(recipeName);
			await saveModal.getByTestId('recipe-servings').fill('2');
			await saveModal.getByTestId('confirm-save-recipe').click();
			await expect(saveModal).toBeHidden({ timeout: 10_000 });

			// The recipe row appears in the self-hiding recipes section.
			const recipeRow = page
				.getByTestId('recipes')
				.locator('.template-row', { hasText: recipeName });
			await expect(recipeRow).toBeVisible({ timeout: 10_000 });

			// Backend rows landed owner-scoped, with both ingredients nested.
			const rec = await readRows(
				'recipes by user_id+name',
				admin
					.from('recipes')
					.select('id, name, servings, ingredient_count, meal_slot, user_id')
					.eq('user_id', USER_A.id)
					.eq('name', recipeName)
			);
			expect(rec.length).toBe(1);
			recipeId = rec![0].id;
			expect(rec![0].ingredient_count).toBe(2);
			// A count of 2 is satisfied by any two rows; these two are the claim.

			expect(Number(rec![0].servings)).toBe(2);
			expect(rec![0].meal_slot).toBe('dinner');
			const ings = await readRows(
				'recipe_ingredients by recipe_id',
				admin
					.from('recipe_ingredients')
					.select('item_name, calories')
					.eq('recipe_id', recipeId)
			);
			expect(ings.map((r) => r.item_name).sort()).toEqual([itemA, itemB].sort());

			// One-tap log: a SINGLE food_log row appears under the recipe name,
			// carrying the per-serving summed macros — (300+200)/2 = 250 kcal,
			// (20+30)/2 = 25 g protein.
			await recipeRow.getByTestId('log-recipe').click();
			await expect
				.poll(
					async () =>
						(
							await admin
								.from('food_log')
								.select('id')
								.eq('user_id', USER_A.id)
								.eq('item_name', recipeName)
						).data!.length,
					{ timeout: 10_000 },
				)
				.toBe(1);
			const logged = await readRows(
				'food_log by user_id+item_name',
				admin
					.from('food_log')
					.select('calories, protein_g, meal_slot')
					.eq('user_id', USER_A.id)
					.eq('item_name', recipeName)
			);
			expect(Number(logged[0].calories)).toBe(250);
			expect(Number(logged[0].protein_g)).toBe(25);
			expect(logged[0].meal_slot).toBe('dinner');

			// Delete the recipe behind the confirm dialog.
			await recipeRow.getByRole('button', { name: `Delete ${recipeName}` }).click();
			const delDialog = page.locator('.modal', { hasText: 'Delete this recipe?' });
			await expect(delDialog).toBeVisible({ timeout: 5_000 });
			await delDialog.getByRole('button', { name: 'Delete', exact: true }).click();
			await expect(recipeRow).toHaveCount(0, { timeout: 10_000 });

			// The recipe (and its ingredients, by cascade) is gone…
			const afterRec = await readRows(
				'recipes by id',
				admin.from('recipes').select('id').eq('id', recipeId)
			);
			expect(afterRec.length).toBe(0);
			recipeId = null;
			// …but the logged summed entry remains (parallel plan, no FK).
			const stillLogged = await readRows(
				'food_log by user_id+item_name',
				admin
					.from('food_log')
					.select('id')
					.eq('user_id', USER_A.id)
					.eq('item_name', recipeName)
			);
			expect(stillLogged.length).toBe(1);
		} finally {
			if (recipeId) await admin.from('recipes').delete().eq('id', recipeId);
			await admin.from('food_log').delete().eq('user_id', USER_A.id).eq('item_name', recipeName);
			if (seedA) await admin.from('food_log').delete().eq('id', seedA.id);
			if (seedB) await admin.from('food_log').delete().eq('id', seedB.id);
		}
	});
});
