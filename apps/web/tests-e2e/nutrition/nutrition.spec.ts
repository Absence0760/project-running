import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

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
		await page.evaluate((ml) => {
			const d = new Date();
			localStorage.setItem(`water_ml_${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`, String(ml));
		}, targetMl - 250);
		await page.reload();
		await expect(chip).toContainText(/ml left/);
		await page.getByTestId('add-water').click();
		await expect(chip).toContainText('Goal reached');
		await expect(page.locator('.water-pips')).toHaveClass(/water-pips-reached/);

		// Reset the per-day localStorage counter so the shared seed user starts
		// clean on the next run (the tracker is client-only, not a DB row).
		await page.evaluate(() => {
			const d = new Date();
			localStorage.removeItem(`water_ml_${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`);
		});
	});

	test('deleting a food entry confirms first: cancel keeps it, confirm removes it', async ({
		page
	}) => {
		const admin = getAdminClient();
		const item = `E2E Delete ${Date.now()}`;
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

			// Cancel keeps the entry.
			await row.getByRole('button', { name: `Delete ${item}` }).click();
			const dialog = page.locator('.modal', { hasText: 'Delete this entry?' });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			await expect(dialog).toBeHidden({ timeout: 5_000 });
			await expect(row).toBeVisible();

			// Confirm removes it from the list + the DB.
			await row.getByRole('button', { name: `Delete ${item}` }).click();
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
			await expect(row).toHaveCount(0, { timeout: 10_000 });

			const { data: after } = await admin
				.from('food_log')
				.select('id')
				.eq('id', created!.id);
			expect(after?.length ?? 0).toBe(0);
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
		// The page buckets runs into "today" by the BROWSER's calendar day, and
		// the Playwright browser is pinned to UTC (timezoneId in the config)
		// while this Node process runs in the workstation's local zone. A
		// past-offset timestamp ("2h ago") computed here could land on a
		// *different* UTC calendar day than the browser's "today" — which is
		// exactly how this flaked on shard 7 of run 27585503400 at 00:31 UTC:
		// the run fell on the previous UTC day, was filtered out of todayRuns,
		// exerciseKcal went to 0, and the breakdown never rendered. Seed at the
		// current instant, which both Node and the UTC browser agree is today
		// (and which the page never excludes), matching the other seeds here.
		const nowMs = Date.now();
		const startedAt = new Date(nowMs).toISOString();
		const utcToday = new Date(nowMs).toISOString().slice(0, 10);
		// Loud precondition: guard against a future edit reintroducing an offset
		// that crosses the UTC midnight boundary — the seed must fall on the
		// browser-UTC "today" the page filters on, or fail here with a clear
		// message instead of a confusing 10s element-not-found timeout below.
		expect(
			startedAt.slice(0, 10),
			'seeded run must fall on the browser-UTC "today" the page buckets exercise calories into',
		).toBe(utcToday);
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
