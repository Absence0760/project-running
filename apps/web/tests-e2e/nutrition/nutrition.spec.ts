import { expect, test } from '@playwright/test';

import { browserDateOf, waterStorageKey } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';
import { readRows } from '../fixtures/db-read';

/**
 * /nutrition — the Phase 4 nutrition module (docs/features/multi_modal.md
 * § Nutrition).
 *
 * Covers the manual-entry logging loop end to end (the Open Food Facts
 * search path needs the network and is unit-tested in food_search.test.ts):
 * open the log surface, enter a food manually with macros + a meal slot, save,
 * and confirm it renders under its meal-slot group with the right calories.
 * Exercised through BOTH hosts of the shared FoodLogEditor — the in-place modal
 * opened from /nutrition (the canonical create-flow pattern, consistent with
 * Log workout / Log run) and the standalone /nutrition/log page wrapper kept
 * for deep links. Also exercises the water tracker increment. The /nutrition
 * routes are always reachable (the Nutrition sidebar item is always present
 * now — decisions §63 amendment ungated it).
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

	test('log food via the in-place modal on /nutrition (no navigation)', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const item = `E2E Modal Oats ${stamp}`;

		await page.goto('/nutrition');

		// The primary action opens a modal in place — consistent with the
		// gym/run create flows — rather than navigating to a separate page.
		await page.getByTestId('log-food').click();
		const modal = page.getByRole('dialog');
		await expect(modal).toBeVisible();

		await modal.getByTestId('meal-slot').selectOption('lunch');
		await modal.getByRole('button', { name: 'Enter manually' }).click();
		await modal.getByTestId('manual-name').fill(item);
		const manual = modal.getByTestId('manual-entry');
		await manual.locator('input[type="number"]').nth(0).fill('420'); // kcal
		await manual.getByRole('button', { name: 'Add' }).click();

		// Modal closes, we stay on /nutrition, and the item renders under Lunch.
		await expect(modal).toBeHidden();
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

	test('extended nutrients round-trip: OFF search → portion preview → logged row → meal detail', async ({
		page
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const item = `E2E Cereal ${stamp}`;

		// Open Food Facts stores mass nutriments per 100 g in GRAMS. sodium 0.5 g
		// and cholesterol 0.03 g must land as 500 mg / 30 mg in the food_log
		// columns; fibre / sugar / saturated fat stay in grams.
		await page.route('**/world.openfoodfacts.org/**', async (route) => {
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					products: [
						{
							code: `e2e-${stamp}`,
							product_name: item,
							brands: 'E2E Foods',
							nutriments: {
								'energy-kcal_100g': 380,
								proteins_100g: 8,
								carbohydrates_100g: 70,
								fat_100g: 6,
								fiber_100g: 4,
								sugars_100g: 10,
								sodium_100g: 0.5,
								'saturated-fat_100g': 2,
								cholesterol_100g: 0.03
							}
						}
					]
				})
			});
		});

		await page.goto('/nutrition/log');
		await page.getByTestId('meal-slot').selectOption('breakfast');
		await page.getByTestId('food-search').fill('cereal');

		// Pick the mocked result → the portion step previews the extended
		// nutrients at the default 100 g portion (with the g→mg conversion).
		await page.getByRole('button', { name: item }).click();
		const extended = page.getByTestId('portion-extended');
		await expect(extended).toBeVisible();
		await expect(extended).toContainText('4 g'); // fibre
		await expect(extended).toContainText('500 mg'); // sodium (0.5 g → 500 mg)
		await expect(extended).toContainText('30 mg'); // cholesterol (0.03 g → 30 mg)

		await page.getByTestId('confirm-log').click();
		await expect(page).toHaveURL(/\/nutrition$/, { timeout: 10_000 });

		// The logged row carries the extended nutrients with sodium/cholesterol
		// stored in mg.
		const { data: created } = await admin
			.from('food_log')
			.select('id, fiber_g, sugar_g, sodium_mg, saturated_fat_g, cholesterol_mg')
			.eq('user_id', USER_A.id)
			.eq('item_name', item);
		expect(created?.length).toBe(1);
		expect(Number(created![0].fiber_g)).toBe(4);
		expect(Number(created![0].sugar_g)).toBe(10);
		expect(Number(created![0].sodium_mg)).toBe(500);
		expect(Number(created![0].saturated_fat_g)).toBe(2);
		expect(Number(created![0].cholesterol_mg)).toBe(30);

		try {
			// Meal detail surfaces the per-item extended breakdown.
			await page.locator('.meal-head-link', { hasText: 'Breakfast' }).click();
			await expect(page).toHaveURL(/\/nutrition\/\d{4}-\d{2}-\d{2}\/breakfast$/, {
				timeout: 10_000
			});
			const detailItem = page.getByTestId('item-extended');
			await expect(detailItem.first()).toContainText('500 mg');
		} finally {
			await admin.from('food_log').delete().eq('id', created![0].id);
		}
	});

	test('a failed Open Food Facts search shows a retry state, not a misleading "no matches"', async ({
		page
	}) => {
		// Force the OFF search to fail; the editor must NOT present this as an
		// empty result set.
		let failNext = true;
		await page.route('**/world.openfoodfacts.org/**', async (route) => {
			if (failNext) {
				await route.fulfill({ status: 500, body: '' });
			} else {
				await route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ products: [] })
				});
			}
		});

		await page.goto('/nutrition/log');
		await page.getByTestId('food-search').fill('oats');

		// The distinct failure state appears (not the no-results empty state).
		await expect(page.getByTestId('search-failed')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('no-results')).toHaveCount(0);

		// Retry after the network recovers resolves to the genuine empty state.
		failNext = false;
		await page.getByRole('button', { name: 'Retry search' }).click();
		await expect(page.getByTestId('no-results')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('search-failed')).toHaveCount(0);
	});

	test('a failed food-log load shows an error + retry, not a misleading empty day', async ({
		page,
	}) => {
		// A transient food_log fetch failure must not render the empty "no food
		// logged" state — the user would think their meals vanished and re-log
		// them. fetchFoodLogWithError surfaces the error; the page shows a retry
		// banner. Fail the first food_log read, then fall back.
		let failNext = true;
		await page.route('**/rest/v1/food_log**', async (route) => {
			if (failNext && route.request().method() === 'GET') {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/nutrition');
		const banner = page.getByTestId('nutrition-load-error');
		await expect(banner).toBeVisible({ timeout: 10_000 });
		// Not the empty rings state masquerading as "nothing logged".
		await expect(page.getByTestId('macro-rings-empty')).toHaveCount(0);

		await page.getByRole('button', { name: 'Retry' }).click();
		await expect(banner).toHaveCount(0, { timeout: 10_000 });
	});

	test('water tracker shows a daily goal + remaining, and flips to reached', async ({ page }) => {
		await page.goto('/nutrition');

		// The water card now shows "consumed / target L" and a remaining chip
		// (the seed user has body metrics so the goal is bodyweight-derived;
		// even without them a flat 2 L baseline target renders).
		const amount = page.locator('.water-amount');
		await expect(amount).toBeVisible({ timeout: 10_000 });
		await expect(amount).toContainText(/\/\s*[\d.]+ L/);

		const chip = page.getByTestId('water-budget');
		await expect(chip).toBeVisible();
		await expect(chip).toContainText(/ml left/);
		const beforeText = await chip.innerText();
		const beforeRemaining = parseInt(beforeText.replace(/\D/g, ''), 10);

		// One 250 ml add reduces the remaining by exactly one unit.
		await page.getByTestId('add-water').click();
		await expect(chip).toContainText(`${beforeRemaining - 250} ml left`);

		// Drive the chip across the goal: seed the per-day counter to one unit
		// below the target (parsed from the "X / Y L" readout), reload, and the
		// final add must flip the chip + pips to the reached state.
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
		await expect(page.locator('.water-pips')).toHaveClass(/water-pips-reached/);

		// Reset the per-day localStorage counter so the shared seed user starts
		// clean on the next run (the tracker is client-only, not a DB row).
		await page.evaluate((key) => localStorage.removeItem(key), waterStorageKey(USER_A.id));
	});

	test('deleting a food entry defers the delete: Undo brings the row back', async ({
		page
	}) => {
		const admin = getAdminClient();
		const item = `E2E Undo ${Date.now()}`;
		const { data: created } = await admin
			.from('food_log')
			.insert({
				user_id: USER_A.id,
				started_at: new Date().toISOString(),
				item_name: item,
				calories: 200,
				meal_slot: 'snack',
			})
			.select('id')
			.single();

		try {
			await page.goto('/nutrition');
			const row = page.locator('.meal-list li', { hasText: item });
			await expect(row).toBeVisible({ timeout: 10_000 });

			// One click removes the row — no modal — and offers the undo.
			await row.getByRole('button', { name: `Delete ${item}` }).click();
			await expect(row).toHaveCount(0, { timeout: 5_000 });
			const bar = page.getByTestId('undo-bar');
			await expect(bar).toBeVisible();
			await expect(bar).toContainText(item);

			// Undo cancels the pending mutation, and the row really comes back.
			await page.getByTestId('undo-action').click();
			await expect(bar).toBeHidden({ timeout: 5_000 });
			await expect(row).toBeVisible();

			// The delete was DEFERRED, never performed: the backend row was
			// untouched the whole time. Checked after the undo so the assertion
			// can't race the window — once undone, nothing can delete it.
			const after = await readRows(
				'food_log by id',
				admin.from('food_log').select('id').eq('id', created!.id)
			);
			expect(after.length).toBe(1);
		} finally {
			await admin.from('food_log').delete().eq('id', created!.id);
		}
	});

	test('dismissing the undo bar commits the delete immediately', async ({ page }) => {
		const admin = getAdminClient();
		const item = `E2E Undo Dismiss ${Date.now()}`;
		const { data: created } = await admin
			.from('food_log')
			.insert({
				user_id: USER_A.id,
				started_at: new Date().toISOString(),
				item_name: item,
				calories: 200,
				meal_slot: 'snack',
			})
			.select('id')
			.single();

		try {
			await page.goto('/nutrition');
			const row = page.locator('.meal-list li', { hasText: item });
			await expect(row).toBeVisible({ timeout: 10_000 });

			await row.getByRole('button', { name: `Delete ${item}` }).click();
			await page.getByTestId('undo-dismiss').click();
			await expect(page.getByTestId('undo-bar')).toBeHidden({ timeout: 5_000 });

			await expect
				.poll(
					async () => {
						const { data } = await admin.from('food_log').select('id').eq('id', created!.id);
						return data?.length ?? 0;
					},
					{ timeout: 10_000 },
				)
				.toBe(0);
			await expect(row).toHaveCount(0);
		} finally {
			await admin.from('food_log').delete().eq('id', created!.id);
		}
	});

	test('an untouched undo window expires and the delete lands on its own', async ({ page }) => {
		// The default 8 s window plus the page load plus the confirmation poll
		// does not fit the suite-wide 30 s budget.
		test.setTimeout(60_000);
		const admin = getAdminClient();
		const item = `E2E Undo Expiry ${Date.now()}`;
		const { data: created } = await admin
			.from('food_log')
			.insert({
				user_id: USER_A.id,
				started_at: new Date().toISOString(),
				item_name: item,
				calories: 200,
				meal_slot: 'snack',
			})
			.select('id')
			.single();

		try {
			await page.goto('/nutrition');
			const row = page.locator('.meal-list li', { hasText: item });
			await expect(row).toBeVisible({ timeout: 10_000 });

			await row.getByRole('button', { name: `Delete ${item}` }).click();
			const bar = page.getByTestId('undo-bar');
			await expect(bar).toBeVisible();

			// Nothing is clicked: the default 8 s window closes by itself and the
			// held mutation fires. Deferring must not mean never deleting.
			await expect(bar).toBeHidden({ timeout: 15_000 });
			await expect
				.poll(
					async () => {
						const { data } = await admin.from('food_log').select('id').eq('id', created!.id);
						return data?.length ?? 0;
					},
					{ timeout: 10_000 },
				)
				.toBe(0);
		} finally {
			await admin.from('food_log').delete().eq('id', created!.id);
		}
	});

	test('eating past the calorie target shows an over-budget signal', async ({ page }) => {
		const admin = getAdminClient();
		// One enormous entry today guarantees the day is over any reasonable
		// target regardless of other rows already logged in the shared seed DB.
		const startedAt = new Date().toISOString();
		const { data: created } = await admin
			.from('food_log')
			.insert({
				user_id: USER_A.id,
				started_at: startedAt,
				item_name: `E2E Feast ${Date.now()}`,
				calories: 9000,
				meal_slot: 'dinner',
			})
			.select('id')
			.single();

		try {
			await page.goto('/nutrition');
			// Headline chip flips from "left" to "over" (the seed user has body
			// metrics, so targets — and therefore the budget chip — render).
			const chip = page.getByTestId('calorie-budget');
			await expect(chip).toBeVisible({ timeout: 10_000 });
			await expect(chip).toContainText(/kcal over/);
			await expect(chip).toHaveClass(/budget-over/);

			// The calorie (hero) ring recolours to the over-budget state, which
			// was previously indistinguishable from an exactly-on-target day.
			const heroRing = page.locator('.ring-hero');
			await expect(heroRing).toHaveClass(/ring-over/);
			await expect(heroRing.locator('.ring-pct-over')).toBeVisible();

			// The 7-day trend now compares the logged-day average to the goal.
			// Exact direction depends on the seed user's week of history, so
			// assert the chip renders wired (the math is unit-tested precisely);
			// it must show one of the three goal-comparison states.
			const weekDelta = page.getByTestId('week-delta');
			await expect(weekDelta).toBeVisible();
			await expect(weekDelta).toContainText(/goal/);
		} finally {
			await admin.from('food_log').delete().eq('id', created!.id);
		}
	});

	test("today's run raises the calorie goal (dynamic TDEE base + exercise)", async ({
		page,
	}) => {
		const admin = getAdminClient();

		// Seed a run "today" so the page computes exercise calories. The seed
		// user has body metrics, so targets are non-null and the breakdown line
		// renders.
		//
		// Seeded at the current instant rather than at a day offset: the page
		// buckets runs into "today" by the browser's calendar day, and a
		// past-offset timestamp ("2h ago") can cross that boundary — which is
		// exactly how this flaked on shard 7 of run 27585503400 at 00:31 UTC:
		// the run fell on the previous day, was filtered out of todayRuns,
		// exerciseKcal went to 0, and the breakdown never rendered. Now is the
		// one instant every zone agrees is today, and the page never excludes
		// it as future.
		const nowMs = Date.now();
		const startedAt = new Date(nowMs).toISOString();
		// Loud precondition: guard against a future edit reintroducing an offset
		// that crosses the day boundary — the seed must fall on the browser's
		// "today" the page filters on, or fail here with a clear message instead
		// of a confusing 10s element-not-found timeout below.
		expect(
			browserDateOf(startedAt),
			'seeded run must fall on the browser "today" the page buckets exercise calories into',
		).toBe(browserDateOf(nowMs));
		const { data: run } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: startedAt,
				distance_m: 10000,
				duration_s: 3000,
				source: 'app',
				is_public: false,
				metadata: { activity_type: 'run' },
			})
			.select('id')
			.single();

		try {
			await page.goto('/nutrition');
			const breakdown = page.getByTestId('goal-breakdown');
			await expect(breakdown).toBeVisible({ timeout: 10_000 });
			// "Goal <base> + <exercise> kcal burned today" — exercise must be > 0.
			await expect(breakdown).toContainText(/\+\s*\d+\s*kcal burned today/);
		} finally {
			await admin.from('runs').delete().eq('id', run!.id);
		}
	});

	test('a meal-slot header links to the per-meal detail route', async ({ page }) => {
		const admin = getAdminClient();
		const item = `E2E Detail ${Date.now()}`;
		// USER_A is the seed user (runner@test.com) with today-relative seed
		// food_log in every slot — clear the recent window so the breakfast
		// roll-up on the detail page reflects only this test's 275-kcal item.
		const since = new Date(Date.now() - 8 * 24 * 3600 * 1000).toISOString();
		await admin.from('food_log').delete().eq('user_id', USER_A.id).gte('started_at', since);
		const { data: created } = await admin
			.from('food_log')
			.insert({
				user_id: USER_A.id,
				started_at: new Date().toISOString(),
				item_name: item,
				calories: 275,
				protein_g: 18,
				meal_slot: 'breakfast',
			})
			.select('id')
			.single();

		try {
			await page.goto('/nutrition');
			const row = page.locator('.meal-list li', { hasText: item });
			await expect(row).toBeVisible({ timeout: 10_000 });

			// Tap the Breakfast meal-group header → per-meal detail route.
			await page.locator('.meal-head-link', { hasText: 'Breakfast' }).click();
			await expect(page).toHaveURL(/\/nutrition\/\d{4}-\d{2}-\d{2}\/breakfast$/, {
				timeout: 10_000
			});

			// The detail shows the slot title, the macro breakdown, the logged
			// item, and a 7-day trend.
			await expect(page.getByRole('heading', { name: 'Breakfast' })).toBeVisible();
			await expect(page.getByTestId('meal-macros')).toContainText('275');
			await expect(page.getByText(item)).toBeVisible();
			await expect(page.getByTestId('meal-trend')).toBeVisible();
		} finally {
			await admin.from('food_log').delete().eq('id', created!.id);
		}
	});
});
