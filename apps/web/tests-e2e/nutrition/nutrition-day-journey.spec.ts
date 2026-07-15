import { expect, test } from '@playwright/test';

import { waterStorageKey } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Nutrition day-in-the-life journey — one long, multi-step walk through the
 * whole /nutrition surface end to end, rather than a single-screen assertion.
 * Complements the focused specs (nutrition.spec.ts manual-log/water/over-budget,
 * daily-view.spec.ts grouping, meal-detail.spec.ts per-slot detail) by chaining
 * the surfaces a real user touches across one day in a single page session:
 *
 *   1. Body metrics present → the macro rings + calorie budget render with real
 *      targets (the untargeted "set your body metrics" hint — data-testid
 *      "no-targets" — is absent). computeNutritionTargets needs weight + height
 *      + age (nutrition_targets.ts § computeNutritionTargets returns null when
 *      any is missing); the shared seed user (runner@test.com) already carries
 *      height_cm + date_of_birth + gender on user_profiles, nutrition_activity_
 *      level + nutrition_goal in user_settings, and a body_metrics weight series
 *      (seed.sql) — so targets resolve from the seed alone, no extra seeding.
 *   2. Visit /nutrition → assert the macro rings + the calorie-budget headline
 *      chip render targeted (the "no-targets" hint absent, not the macro-rings-
 *      empty no-meals card — that one IS present until the meal is logged).
 *   3. Log a food via the in-place FoodLogEditor modal using the manual-macro
 *      fallback (NOT the Open Food Facts network search, which the focused specs
 *      stub — see nutrition.spec.ts) → the item shows under its meal slot and the
 *      consumed calorie total climbs by exactly the logged amount.
 *   4. Water tracker (localStorage per day): add one 250 ml unit → the "X ml
 *      left" budget chip drops by 250; seed the per-day counter to one unit below
 *      the bodyweight-derived target, reload, and the final add flips the chip to
 *      "Goal reached".
 *   5. The 7-day calorie-trend week-summary chip renders wired to the goal.
 *   6. Delete the logged food via its row Delete → confirm dialog → the consumed
 *      total reverts to its pre-log value and the row is gone from the DB.
 *
 * A unique food name per run keeps the assertions + cleanup isolated in the
 * shared seed DB. The water-tracker localStorage key is reset at the end so the
 * shared seed user starts clean on the next run.
 */
test.describe('/nutrition — day-in-the-life journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const admin = getAdminClient();
	const item = `E2E Journey Bowl ${Date.now()}`;
	const ITEM_KCAL = 540;

	// No body-metrics / profile / settings seeding: the targets resolve entirely
	// from the shared seed (height_cm + date_of_birth + gender on user_profiles,
	// nutrition_activity_level + nutrition_goal in user_settings, a body_metrics
	// weight series whose latest row fetchLatestWeightKg picks regardless of
	// date). fetchLatestWeightKg orders by recorded_at desc with no date filter,
	// so the seed's "1 day ago" row is enough — there is no drift window to guard.

	test.afterAll(async () => {
		// Clean up only what this spec created: the food_log row (the test deletes
		// it in-flow, but guard the path where an assertion threw before the
		// delete step). No seed rows are touched.
		await admin.from('food_log').delete().eq('user_id', USER_A.id).eq('item_name', item);
	});

	test('rings render → log a meal → water → trend → delete reverts', async ({ page }) => {
		// Read consumed calories off the calories ring's `.ring-val`
		// (`{consumed.calories}`). This is the always-present source: the
		// `.meals-card` consumed-total header only renders once ≥1 meal is
		// logged ({#if hasMeals} → else the macro-rings-empty card), so the
		// pre-log baseline read has to come from the ring, which is always
		// mounted whenever targets resolve. Used to prove the calorie total
		// climbs on log and reverts on delete.
		const consumedKcal = async (): Promise<number> => {
			const txt = await page.locator('.ring-hero .ring-val').first().innerText();
			return parseInt(txt.replace(/\D/g, ''), 10);
		};

		let baseKcal = 0;

		// ── 1+2. Rings + calorie budget render (targeted) ────────────────────
		await test.step('the macro rings + calorie budget render (body metrics present)', async () => {
			await page.goto('/nutrition');

			// The rings section renders with REAL targets: the "no-targets"
			// untargeted hint (shown only when computeNutritionTargets returns
			// null) is absent, proving the seed body metrics resolved into a goal.
			// (macro-rings-empty is the no-meals-logged card, not the untargeted
			// state — it's present here until step 3 logs a meal.)
			await expect(page.getByTestId('macro-rings')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('no-targets')).toHaveCount(0);

			// The hero (calorie) ring renders with a "/ target" readout, and the
			// headline calorie-budget chip is wired (left / on / over — any of the
			// three, the exact one depends on the seed user's day).
			const heroRing = page.locator('.ring-hero');
			await expect(heroRing).toBeVisible();
			await expect(heroRing.locator('.ring-target')).toBeVisible();
			await expect(page.getByTestId('calorie-budget')).toBeVisible();

			baseKcal = await consumedKcal();
		});

		// ── 3. Log a food via the in-place modal, manual-macro fallback ──────
		await test.step('log a food manually → it appears under its slot + the total climbs', async () => {
			// The primary action opens the shared FoodLogEditor in a modal in
			// place (the canonical create-flow pattern) — no navigation.
			await page.getByTestId('log-food').click();
			const modal = page.getByRole('dialog');
			await expect(modal).toBeVisible();

			await modal.getByTestId('meal-slot').selectOption('lunch');
			// Manual entry fallback — avoids the Open Food Facts network search.
			await modal.getByRole('button', { name: 'Enter manually' }).click();
			await modal.getByTestId('manual-name').fill(item);
			const manual = modal.getByTestId('manual-entry');
			await manual.locator('input[type="number"]').nth(0).fill(String(ITEM_KCAL)); // kcal
			await manual.locator('input[type="number"]').nth(1).fill('35'); // protein
			await manual.getByRole('button', { name: 'Add' }).click();

			// Modal closes, we stay on /nutrition, and the item renders under Lunch.
			await expect(modal).toBeHidden();
			await expect(page).toHaveURL(/\/nutrition$/);
			const row = page.locator('.meal-list li', { hasText: item });
			await expect(row).toBeVisible({ timeout: 10_000 });
			await expect(row.locator('.item-kcal')).toHaveText(String(ITEM_KCAL));

			// The consumed calorie total climbed by exactly the logged amount —
			// the ring/total is wired to the new entry, not just the list.
			await expect.poll(consumedKcal).toBe(baseKcal + ITEM_KCAL);

			// Backend row exists, owned by USER_A, in the chosen slot.
			const { data: created } = await admin
				.from('food_log')
				.select('id, meal_slot')
				.eq('user_id', USER_A.id)
				.eq('item_name', item);
			expect(created?.length).toBe(1);
			expect(created![0].meal_slot).toBe('lunch');
		});

		// ── 4. Water tracker (localStorage per user + day) ───────────────────
		await test.step('water: one add drops the remaining; crossing the goal flips to reached', async () => {
			// Start from a clean per-day counter (the tracker is client-only).
			await page.evaluate((key) => localStorage.removeItem(key), waterStorageKey(USER_A.id));
			await page.reload();

			const chip = page.getByTestId('water-budget');
			await expect(chip).toBeVisible({ timeout: 10_000 });
			await expect(chip).toContainText(/ml left/);
			const before = parseInt((await chip.innerText()).replace(/\D/g, ''), 10);

			// One 250 ml add reduces the remaining by exactly one unit.
			await page.getByTestId('add-water').click();
			await expect(chip).toContainText(`${before - 250} ml left`);

			// Seed the per-day counter to one unit below the bodyweight-derived
			// target (parsed from the "X / Y L" readout), reload, and the final
			// add flips the chip to the reached state.
			const amount = page.locator('.water-amount');
			const targetL = parseFloat((await amount.innerText()).split('/')[1].replace(/[^\d.]/g, ''));
			const targetMl = Math.round(targetL * 1000);
			await page.evaluate(
				({ key, ml }) => localStorage.setItem(key, String(ml)),
				{ key: waterStorageKey(USER_A.id), ml: targetMl - 250 },
			);
			await page.reload();
			await expect(chip).toContainText(/ml left/);
			await page.getByTestId('add-water').click();
			await expect(chip).toContainText('Goal reached');

			// Reset so the shared seed user starts clean on the next run.
			await page.evaluate((key) => localStorage.removeItem(key), waterStorageKey(USER_A.id));
		});

		// ── 5. 7-day calorie-trend week-summary chip ─────────────────────────
		await test.step('the 7-day calorie-trend week-summary chip renders wired to the goal', async () => {
			await page.goto('/nutrition');
			const weekDelta = page.getByTestId('week-delta');
			await expect(weekDelta).toBeVisible({ timeout: 10_000 });
			// One of the three goal-comparison states (under / on / over) — the
			// exact direction depends on the seed user's week of history; the math
			// is unit-tested precisely in nutrition_week.test.ts.
			await expect(weekDelta).toContainText(/goal/);
		});

		// ── 6. Delete the logged food → the total reverts ────────────────────
		await test.step('delete the logged entry → the consumed total reverts', async () => {
			const row = page.locator('.meal-list li', { hasText: item });
			await expect(row).toBeVisible({ timeout: 10_000 });

			await row.getByRole('button', { name: `Delete ${item}` }).click();
			const dialog = page.locator('.modal', { hasText: 'Delete this entry?' });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
			await expect(row).toHaveCount(0, { timeout: 10_000 });

			// The consumed total dropped back to the pre-log baseline.
			await expect.poll(consumedKcal).toBe(baseKcal);

			// And the row is gone from the DB.
			const { data: after } = await admin
				.from('food_log')
				.select('id')
				.eq('user_id', USER_A.id)
				.eq('item_name', item);
			expect(after?.length ?? 0).toBe(0);
		});
	});
});
