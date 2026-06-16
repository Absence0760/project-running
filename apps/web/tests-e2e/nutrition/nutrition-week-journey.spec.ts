import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Nutrition multi-day WEEK journey — one long, multi-step walk that THREADS
 * body metrics → a multi-day food log → the week-level surfaces (7-day calorie
 * trend + "under/over goal/day" summary chip, the macro budget, the
 * bodyweight-derived hydration goal) end to end.
 *
 * Deliberately distinct from nutrition-day-journey.spec.ts, which covers a
 * SINGLE day's log + rings + a single water add. This one is the WEEK-scale
 * companion: it plants food across SEVERAL trailing days, logs one more via the
 * real FoodLogEditor write path, and then asserts the surfaces that only light
 * up with a week of data — the 7-day trend bars, the week-summary delta chip,
 * the per-macro calorie budget, and the hydration goal that scales with
 * bodyweight (+ logged exercise).
 *
 * Body metrics + activity/goal prefs (the inputs to computeNutritionTargets +
 * hydrationTargetMl): the shared seed user (runner@test.com) ALREADY carries
 * them — height_cm + date_of_birth + gender on user_profiles, a body_metrics
 * weight series (latest 73.9 kg), and nutrition_activity_level/nutrition_goal in
 * user_settings (seed.sql). /nutrition reads them via fetchLatestWeightKg() +
 * get_my_profile() and gates the rings purely on whether those resolve into a
 * target — there is NO health-consent gate on the read path (the Art 9 consent
 * gate lives only in Settings, for EDITING). So this spec NEVER sets or clears
 * body metrics or health consent: it relies on the seed and leaves it untouched.
 *
 * Date handling: the 7-day trend buckets on the LOCAL calendar day, and the
 * Playwright browser is pinned to UTC (playwright.config.ts § timezoneId). So
 * every inserted row is anchored to NOON UTC of its target day (Date.UTC(...,12))
 * — noon keeps each row safely inside its own UTC day regardless of the ±offset
 * between this Node process's zone and the browser's UTC, avoiding the
 * day-boundary flake that bit the dynamic-TDEE seed (see nutrition.spec.ts).
 *
 * A unique stamp per run keeps the inserted rows + the UI-logged item isolated
 * from the seed's own week of food in the shared DB, and the finally block
 * deletes exactly what this spec created (food_log rows by item_name + the
 * water-tracker localStorage key) — no seed row is touched.
 */
test.describe('/nutrition — multi-day week journey', () => {
	// A multi-surface journey with several full navigations + a UI log
	// round-trip; the default 30 s test timeout is tight.
	test.describe.configure({ timeout: 90_000 });

	test.use({ storageState: USER_A.storageStatePath });

	const admin = getAdminClient();
	const stamp = Date.now();

	// Bodyweight-only hydration floor for the seed user (latest weight 73.9 kg):
	// 73.9 × 35 ml/kg = 2586.5 → rounded to the nearest 50 = 2600 ml = 2.6 L.
	// The seed also has a run "today" whose minutes add MORE on top, so the
	// rendered target is >= this floor — assert the floor, not an exact value
	// (the exact-arithmetic is unit-tested in hydration.test.ts).
	const HYDRATION_FLOOR_L = 2.6;

	// Inserted across the trailing week. Plain calorie-only rows (the trend
	// buckets on calories); each lands in a distinct UTC day so >= 4 of the 7
	// trend columns carry data — the "multi-day" shape the day journey can't show.
	const WEEK_ITEM = (offsetDays: number) => `E2E Week D-${offsetDays} ${stamp}`;
	const WEEK_OFFSETS = [3, 2, 1] as const; // today is covered by the UI-logged item
	const WEEK_KCAL = 600;

	// Logged through the real FoodLogEditor (UI write path), dated today.
	const TODAY_ITEM = `E2E Week Today ${stamp}`;
	const TODAY_KCAL = 540;

	/// Noon UTC of (today − offsetDays), as an ISO string. Browser-UTC bucketing
	/// puts this squarely on that calendar day.
	function noonUtcDaysAgo(offsetDays: number): string {
		const now = new Date();
		return new Date(
			Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - offsetDays, 12, 0, 0),
		).toISOString();
	}

	test.beforeAll(async () => {
		// Plant calorie-only food on three distinct prior days so the 7-day
		// trend has multi-day variation independent of the seed's own week.
		const rows = WEEK_OFFSETS.map((off) => ({
			user_id: USER_A.id,
			started_at: noonUtcDaysAgo(off),
			item_name: WEEK_ITEM(off),
			calories: WEEK_KCAL,
			meal_slot: 'lunch',
		}));
		const { error } = await admin.from('food_log').insert(rows);
		if (error) throw error;
	});

	test.afterAll(async () => {
		// Delete only what this spec created — the three week rows + the
		// UI-logged today row (guard the path where an assertion threw before the
		// in-flow cleanup). The seed's own food_log/body_metrics are untouched.
		await admin
			.from('food_log')
			.delete()
			.eq('user_id', USER_A.id)
			.like('item_name', `%${stamp}%`);
	});

	test('targeted rings + budget → log today via the editor → 7-day trend + week chip + hydration goal', async ({
		page,
	}) => {
		const consumedKcal = async (): Promise<number> => {
			const txt = await page.locator('.ring-hero .ring-val').first().innerText();
			return parseInt(txt.replace(/\D/g, ''), 10);
		};

		let baseKcal = 0;

		// ── 1. Body metrics present → rings + calorie budget render targeted ──
		await test.step('macro rings + calorie budget render with real targets', async () => {
			await page.goto('/nutrition');

			// The rings resolve to REAL targets (the "no-targets" hint is absent),
			// proving the seed body metrics + prefs computed a goal.
			await expect(page.getByTestId('macro-rings')).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('no-targets')).toHaveCount(0);

			// The hero (calorie) ring carries a "/ target" readout and the macro
			// budget headline chip is wired (left / on / over — the seed user's day
			// decides which, all three are valid).
			const heroRing = page.locator('.ring-hero');
			await expect(heroRing).toBeVisible();
			await expect(heroRing.locator('.ring-target')).toBeVisible();
			await expect(page.getByTestId('calorie-budget')).toBeVisible();

			baseKcal = await consumedKcal();
		});

		// ── 2. Hydration goal reflects bodyweight (+ exercise) ───────────────
		await test.step('the hydration goal scales with bodyweight (>= the 73.9 kg floor)', async () => {
			// "consumed / target L" — the target is bodyweight-derived (~35 ml/kg),
			// so it must be >= the 2.6 L floor for the seed user, never the flat
			// 2 L fallback (which only applies when bodyweight is unknown).
			const amount = page.locator('.water-amount');
			await expect(amount).toBeVisible();
			await expect(amount).toContainText(/\/\s*[\d.]+ L/);
			const targetL = parseFloat((await amount.innerText()).split('/')[1].replace(/[^\d.]/g, ''));
			expect(
				targetL,
				'hydration target must be bodyweight-derived (>= 2.6 L for 73.9 kg), not the 2 L unknown-weight fallback',
			).toBeGreaterThanOrEqual(HYDRATION_FLOOR_L);

			// And the water budget chip is wired to that goal.
			const chip = page.getByTestId('water-budget');
			await expect(chip).toBeVisible();
			await expect(chip).toContainText(/ml left|Goal reached/);
		});

		// ── 3. Log today's food via the real FoodLogEditor write path ────────
		await test.step('log a food via the in-place editor → it lands today + the ring climbs', async () => {
			await page.getByTestId('log-food').click();
			const modal = page.getByRole('dialog');
			await expect(modal).toBeVisible();

			await modal.getByTestId('meal-slot').selectOption('dinner');
			// Manual-macro fallback — avoids the Open Food Facts network search.
			await modal.getByRole('button', { name: 'Enter manually' }).click();
			await modal.getByTestId('manual-name').fill(TODAY_ITEM);
			const manual = modal.getByTestId('manual-entry');
			await manual.locator('input[type="number"]').nth(0).fill(String(TODAY_KCAL)); // kcal
			await manual.locator('input[type="number"]').nth(1).fill('40'); // protein
			await manual.getByRole('button', { name: 'Add' }).click();

			await expect(modal).toBeHidden();
			await expect(page).toHaveURL(/\/nutrition$/);
			const row = page.locator('.meal-list li', { hasText: TODAY_ITEM });
			await expect(row).toBeVisible({ timeout: 10_000 });
			await expect(row.locator('.item-kcal')).toHaveText(String(TODAY_KCAL));

			// The consumed calorie ring climbed by exactly the logged amount.
			await expect.poll(consumedKcal).toBe(baseKcal + TODAY_KCAL);

			// Backend row exists today, owned by USER_A, in the chosen slot.
			const { data: created } = await admin
				.from('food_log')
				.select('id, meal_slot')
				.eq('user_id', USER_A.id)
				.eq('item_name', TODAY_ITEM);
			expect(created?.length).toBe(1);
			expect(created![0].meal_slot).toBe('dinner');
		});

		// ── 4. The 7-day calorie trend shows the multi-day data ──────────────
		await test.step('the 7-day trend renders multiple non-empty days', async () => {
			const trend = page.locator('.trend-card');
			await expect(trend).toBeVisible({ timeout: 10_000 });

			// Seven day columns; today is the last and carries this session's
			// dinner item, so its value cell is non-empty.
			const cols = trend.locator('.trend-col');
			await expect(cols).toHaveCount(7);
			await expect(cols.last()).toHaveClass(/trend-today/);
			await expect(cols.last().locator('.trend-val')).not.toHaveText('');

			// At least four of the seven columns carry data — the multi-day shape
			// the single-day journey can't exercise (the three planted prior days
			// + today, on top of the seed's own week).
			const vals = await trend.locator('.trend-col .trend-val').allInnerTexts();
			const nonEmpty = vals.filter((v) => v.trim().length > 0);
			expect(nonEmpty.length).toBeGreaterThanOrEqual(4);

			// Backend cross-check: the three planted week rows + today's UI row
			// all exist for USER_A within the trailing-week window.
			const since = noonUtcDaysAgo(6);
			const { data: weekRows } = await admin
				.from('food_log')
				.select('item_name')
				.eq('user_id', USER_A.id)
				.like('item_name', `%${stamp}%`)
				.gte('started_at', since);
			expect((weekRows ?? []).length).toBe(WEEK_OFFSETS.length + 1);
		});

		// ── 5. The week-summary "under/over goal/day" chip is wired ──────────
		await test.step('the week-summary delta chip compares the logged-day average to the goal', async () => {
			const weekDelta = page.getByTestId('week-delta');
			await expect(weekDelta).toBeVisible({ timeout: 10_000 });
			// One of the three goal-comparison states (under / on / over) — the
			// exact direction depends on the seed week's totals; the signed-delta
			// math is unit-tested precisely in nutrition_week.test.ts.
			await expect(weekDelta).toContainText(/goal/);
		});

		// ── 6. Reset the client-only water counter for the shared seed user ──
		await test.step('leave the water tracker clean for the next run', async () => {
			await page.evaluate(() => {
				const d = new Date();
				localStorage.removeItem(
					`water_ml_${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`,
				);
			});
		});
	});
});
