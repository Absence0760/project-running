import { expect, test, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

/**
 * Dynamic calorie-budget (base + exercise) cross-modal day — one long,
 * multi-step walk that threads body metrics → today's RUN + today's GYM
 * session → the dynamic-TDEE "base + exercise" goal → a real food log → the
 * calorie-budget headline chip and the over-budget ring states, end to end on
 * /nutrition.
 *
 * This is deliberately distinct from the other nutrition specs:
 *   - nutrition-day-journey.spec.ts  — a single day's log + rings + one water add.
 *   - nutrition-week-journey.spec.ts — the WEEK-scale trend + week-summary chip.
 * Neither exercises the dynamic-TDEE seam: that logging a run AND a gym session
 * RAISES the day's calorie goal by the estimated burn (`base + exercise`,
 * decisions §63 amendment), shown as the `Goal {base} + {exercise} kcal burned
 * today` breakdown line, and that the budget chip + ceiling-aware ring states
 * (calories/fat recolour to danger past target; protein/carbs show a
 * target-reached tick) track the food logged against that raised goal. That is
 * exactly the slice this spec owns.
 *
 * Determinism strategy — the BASE goal depends on age (Mifflin-St Jeor uses
 * whole-year age off date_of_birth, which shifts on a birthday), so this spec
 * never hardcodes the absolute calorie target. Instead it:
 *   1. Reads `base` + `exercise` off the rendered breakdown line, and the hero
 *      ring's `/ target` readout — the page's own `targets.calories`.
 *   2. Asserts the RELATIONSHIPS the source guarantees exactly:
 *        - exercise add-on == round(runCalories + gymCalories) for the seeded
 *          weight (exercise_calories.ts: 1.036·kg·km run + 5.0·kg·h gym),
 *        - target == base + exercise (nutrition_targets.ts),
 *        - budget chip == "{target − consumed} kcal left" while under
 *          (nutrition_budget.ts macroBudget.remaining),
 *        - logging food past the target flips the chip to "{over} kcal over"
 *          AND the calorie ring gains .ring-over (the ceiling state).
 * The exact arithmetic of the pure layer is unit-tested in
 * exercise_calories.test.ts / nutrition_targets.test.ts / nutrition_budget.test.ts;
 * this spec proves the cross-modal WIRING through the real UI.
 *
 * Seeding — a saga user starts with NO body metrics, so this spec seeds the
 * full target-input set itself (height_cm/date_of_birth/gender on
 * user_profiles, nutrition_activity_level/nutrition_goal in user_settings, and a
 * body_metrics weight row). There is NO health-consent gate on the /nutrition
 * READ path (the Art 9 gate lives only in Settings, for EDITING — confirmed in
 * the page's load(): it reads fetchLatestWeightKg() + get_my_profile() and gates
 * the rings purely on whether those resolve into a target). The saga user owns
 * every row, and deleteSagaUsers CASCADEs auth.users → all child rows
 * (body_metrics, runs, gym_workouts, food_log), so cleanup is a single delete.
 *
 * Date handling — the browser is pinned to UTC (playwright.config.ts
 * § timezoneId) and /nutrition's "today" window uses local-day boundaries
 * (dayStartIso), so in-browser that's the UTC day. Every seeded activity + food
 * row is anchored to NOON UTC of today (Date.UTC(...,12)) so it lands squarely
 * inside today's window regardless of the offset between this Node process's
 * zone and the browser's UTC.
 */
test.describe('/nutrition — dynamic budget (base + exercise) cross-modal day', () => {
	// A multi-surface journey: seed body metrics + a run + a gym session, then
	// several navigations + a UI log round-trip. The default 30 s is tight.
	test.describe.configure({ timeout: 120_000 });

	const admin = getAdminClient();

	// Seeded bodyweight — drives BOTH the exercise-calorie estimate and the
	// macro protein target. 80 kg keeps the arithmetic clean.
	const WEIGHT_KG = 80;
	const HEIGHT_CM = 178;
	const DOB = '1992-09-12';

	// Today's seeded activities. Distances/durations chosen so the burn is a
	// round, verifiable number for an 80 kg athlete:
	//   run:  1.036 · 80 · 10 km            = 828.8 kcal
	//   gym:  5.0  · 80 · (3600 s / 3600)   = 400.0 kcal
	//   total (rounded once)                = round(1228.8) = 1229 kcal
	const RUN_DISTANCE_M = 10_000;
	const GYM_DURATION_S = 3600;
	const EXPECTED_EXERCISE_KCAL = 1229;

	let user: SagaUser;

	/// Noon UTC of today, as an ISO string. The browser is UTC-pinned, so this
	/// lands inside /nutrition's local-day "today" window.
	function noonUtcToday(): string {
		const now = new Date();
		return new Date(
			Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 12, 0, 0),
		).toISOString();
	}

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Budget Saga'] });

		// 1) Body metrics: height + DOB + sex on user_profiles (the Mifflin-St
		//    Jeor inputs that aren't weight). get_my_profile() reads these back.
		const { error: profErr } = await admin
			.from('user_profiles')
			.update({ height_cm: HEIGHT_CM, date_of_birth: DOB, gender: 'male' })
			.eq('id', user.id);
		if (profErr) throw profErr;

		// 2) A current weight in the body_metrics series (fetchLatestWeightKg
		//    reads the most-recent row).
		const { error: bmErr } = await admin
			.from('body_metrics')
			.insert({ user_id: user.id, weight_kg: WEIGHT_KG, recorded_at: noonUtcToday() });
		if (bmErr) throw bmErr;

		// 3) Activity/goal prefs. sedentary (factor 1.2) + maintain (0 delta) so
		//    the BASE excludes any lifestyle exercise — the logged run + gym are
		//    the ONLY exercise add-on, which is what this spec verifies. (The page
		//    reads these via loadSettings()/effective().)
		const { error: setErr } = await admin.from('user_settings').upsert({
			user_id: user.id,
			prefs: {
				nutrition_activity_level: 'sedentary',
				nutrition_goal: 'maintain',
			},
		});
		if (setErr) throw setErr;

		// 4) Today's RUN — fires nothing relevant to nutrition; the page filters
		//    fetchRuns() to today and feeds distance into exerciseCaloriesForDay.
		await insertRun({
			user_id: user.id,
			started_at: noonUtcToday(),
			distance_m: RUN_DISTANCE_M,
			duration_s: 3000,
		});

		// 5) Today's GYM session — a plain gym_workouts parent with a duration;
		//    no helper exists, so insert directly. The page filters
		//    fetchGymWorkouts() to today and feeds duration_s into the estimate.
		const { error: gymErr } = await admin.from('gym_workouts').insert({
			user_id: user.id,
			title: 'E2E Budget Lift',
			started_at: noonUtcToday(),
			duration_s: GYM_DURATION_S,
		});
		if (gymErr) throw gymErr;
	});

	test.afterAll(async () => {
		// deleteSagaUsers CASCADEs auth.users → body_metrics / runs / gym_workouts
		// / food_log, and unlinks the storage-state file. Nothing else to sweep.
		if (user) await deleteSagaUsers([user]);
	});

	test('run + gym raise the goal (base + exercise) → log food → budget chip + over-budget ring track it', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		// Pre-accept the GDPR cookie banner — saga storage state doesn't bake
		// it, and the banner is itself a role="dialog" that both makes
		// getByRole('dialog') ambiguous and floats over the FoodLogEditor's
		// Add button (matches the saga-spec consent pattern, e.g.
		// cross-user/sagas/kudos-notification.spec.ts).
		await ctx.addInitScript(setConsentAccepted);
		const page: Page = await ctx.newPage();

		// Live readers over the rendered page — the source's own numbers, so the
		// assertions can't drift from a hardcoded age-dependent base.
		const readBreakdown = async (): Promise<{ base: number; exercise: number }> => {
			const txt = await page.getByTestId('goal-breakdown').innerText();
			// "Goal {base} + {exercise} kcal burned today"
			const m = txt.match(/Goal\s+([\d,]+)\s*\+\s*([\d,]+)/);
			if (!m) throw new Error(`goal-breakdown did not match: "${txt}"`);
			return {
				base: parseInt(m[1].replace(/[^\d]/g, ''), 10),
				exercise: parseInt(m[2].replace(/[^\d]/g, ''), 10),
			};
		};
		const readHeroTarget = async (): Promise<number> => {
			// ".ring-hero .ring-target" renders "/ {target}".
			const txt = await page.locator('.ring-hero .ring-target').innerText();
			return parseInt(txt.replace(/[^\d]/g, ''), 10);
		};
		const readConsumedKcal = async (): Promise<number> => {
			const txt = await page.locator('.ring-hero .ring-val').first().innerText();
			return parseInt(txt.replace(/[^\d]/g, ''), 10);
		};

		let targetKcal = 0;

		try {
			// ── 1. Body metrics resolve into a target; the rings render ───────
			await test.step('rings render with a real target (seeded body metrics)', async () => {
				await page.goto('/nutrition');
				await expect(page.getByTestId('macro-rings')).toBeVisible({ timeout: 15_000 });
				// The seed produced a target, so the "no targets" hint is absent.
				await expect(page.getByTestId('no-targets')).toHaveCount(0);
				await expect(page.locator('.ring-hero .ring-target')).toBeVisible();
			});

			// ── 2. The "base + exercise" breakdown shows today's burn exactly ──
			await test.step('the goal breakdown adds today’s run + gym burn on top of the base', async () => {
				// The breakdown line only renders when exerciseKcal > 0 — i.e. the
				// run + gym were both attributed to today.
				await expect(page.getByTestId('goal-breakdown')).toBeVisible();

				const { base, exercise } = await readBreakdown();
				// The exercise add-on is the run + gym burn for an 80 kg athlete,
				// rounded once (exercise_calories.ts): 828.8 + 400 → 1229.
				expect(
					exercise,
					'exercise add-on must equal round(runCalories + gymCalories) for 80 kg, 10 km, 1 h',
				).toBe(EXPECTED_EXERCISE_KCAL);
				expect(base).toBeGreaterThan(0);

				// The hero ring's target == base + exercise (nutrition_targets.ts:
				// calories = baseCalories + exerciseKcal).
				targetKcal = await readHeroTarget();
				expect(targetKcal).toBe(base + exercise);
			});

			// ── 3. With nothing logged, the budget chip == the full target left ─
			await test.step('the calorie-budget chip shows the full raised goal as "left"', async () => {
				const chip = page.getByTestId('calorie-budget');
				await expect(chip).toBeVisible();
				// consumed 0 → remaining == target → "left" state (budget-left).
				await expect(chip).toHaveClass(/budget-left/);
				await expect(chip).toHaveText(`${targetKcal} kcal left`);
				expect(await readConsumedKcal()).toBe(0);
				// The calorie ring is not in its over (ceiling-exceeded) state yet.
				await expect(page.locator('.ring-hero')).not.toHaveClass(/ring-over/);
			});

			// ── 4. Log food UNDER the goal → chip stays "left", decremented ────
			//    A protein-heavy item: enough protein to clear the protein goal
			//    (so the protein ring shows the target-reached tick — proving the
			//    goal-macro "reached" path), but calories well under target.
			const UNDER_ITEM = `E2E Budget Under ${Date.now()}`;
			const UNDER_KCAL = 500;
			const UNDER_PROTEIN = 220; // > 1.8 g/kg · 80 kg = 144 g target → reached
			await test.step('log food under the goal → chip decrements, protein ring reaches its target', async () => {
				await logManualFood(page, {
					slot: 'lunch',
					name: UNDER_ITEM,
					kcal: UNDER_KCAL,
					protein: UNDER_PROTEIN,
				});

				// The consumed calorie ring climbed by exactly the logged amount.
				await expect.poll(readConsumedKcal).toBe(UNDER_KCAL);

				// Budget chip: still "left", now target − consumed.
				const chip = page.getByTestId('calorie-budget');
				await expect(chip).toHaveClass(/budget-left/);
				await expect(chip).toHaveText(`${targetKcal - UNDER_KCAL} kcal left`);

				// Protein is a GOAL macro (over = success), so clearing 144 g shows
				// the reached tick, never an alert — ring-reached, not ring-over.
				const proteinRing = page.locator('.ring', {
					has: page.locator('.ring-label', { hasText: /^Protein$/ }),
				});
				await expect(proteinRing).toHaveClass(/ring-reached/);
				await expect(proteinRing).not.toHaveClass(/ring-over/);
				await expect(proteinRing.locator('.ring-pct-reached')).toBeVisible();
			});

			// ── 5. Log food that pushes calories OVER the goal → ceiling state ─
			//    One big item whose calories exceed the remaining headroom. Carry
			//    a large fat load too so the fat ring (also a ceiling) flips over.
			const OVER_ITEM = `E2E Budget Over ${Date.now()}`;
			await test.step('log food over the goal → chip flips to "over" and the calorie ring goes danger', async () => {
				const remainingBefore = targetKcal - UNDER_KCAL;
				// 400 kcal past the remaining headroom → deterministic overage.
				const overKcal = remainingBefore + 400;
				const totalConsumed = UNDER_KCAL + overKcal;
				const expectedOver = totalConsumed - targetKcal; // == 400

				await logManualFood(page, {
					slot: 'dinner',
					name: OVER_ITEM,
					kcal: overKcal,
					fat: 250, // a fat ceiling well over any sane target → fat ring over too
				});

				await expect.poll(readConsumedKcal).toBe(totalConsumed);

				// Calories is a CEILING macro: over target → warning. Chip flips to
				// the "over" state with the exact overage; the hero ring recolours.
				const chip = page.getByTestId('calorie-budget');
				await expect(chip).toHaveClass(/budget-over/);
				await expect(chip).toHaveText(`${expectedOver} kcal over`);
				await expect(page.locator('.ring-hero')).toHaveClass(/ring-over/);
				await expect(page.locator('.ring-hero .ring-pct-over')).toHaveText(`+${expectedOver}`);

				// Fat is the OTHER ceiling macro — 250 g blows past any target, so
				// its ring is in the same danger state (calories + fat recolour;
				// protein + carbs never do).
				const fatRing = page.locator('.ring', {
					has: page.locator('.ring-label', { hasText: /^Fat$/ }),
				});
				await expect(fatRing).toHaveClass(/ring-over/);
				await expect(fatRing.locator('.ring-pct-over')).toBeVisible();
			});

			// ── 6. Backend cross-check + the trend reflects today ─────────────
			await test.step('the day’s food rows exist for the user and the trend’s today cell is non-empty', async () => {
				const { data: rows } = await admin
					.from('food_log')
					.select('item_name, calories')
					.eq('user_id', user.id)
					.in('item_name', [UNDER_ITEM, OVER_ITEM]);
				expect((rows ?? []).length).toBe(2);

				const trend = page.locator('.trend-card');
				await expect(trend).toBeVisible({ timeout: 10_000 });
				const cols = trend.locator('.trend-col');
				await expect(cols).toHaveCount(7);
				// Today is the last column and carries this session's food.
				await expect(cols.last()).toHaveClass(/trend-today/);
				await expect(cols.last().locator('.trend-val')).not.toHaveText('');
			});
		} finally {
			await ctx.close();
		}
	});
});

/// Drive the real FoodLogEditor manual-entry path (no Open Food Facts network
/// search): open the modal, pick a slot, switch to manual, fill name + macros,
/// Add. Mirrors the editor's testids (FoodLogEditor.svelte) and the
/// nutrition-week journey's manual-log flow. The macro inputs are the numeric
/// fields inside [data-testid=manual-entry], ordered kcal / protein / carbs /
/// fat.
async function logManualFood(
	page: Page,
	opts: { slot: string; name: string; kcal: number; protein?: number; carbs?: number; fat?: number },
): Promise<void> {
	await page.getByTestId('log-food').click();
	const modal = page.getByRole('dialog');
	await expect(modal).toBeVisible();

	await modal.getByTestId('meal-slot').selectOption(opts.slot);
	await modal.getByRole('button', { name: 'Enter manually' }).click();
	await modal.getByTestId('manual-name').fill(opts.name);

	const manual = modal.getByTestId('manual-entry');
	const num = manual.locator('input[type="number"]');
	await num.nth(0).fill(String(opts.kcal));
	if (opts.protein != null) await num.nth(1).fill(String(opts.protein));
	if (opts.carbs != null) await num.nth(2).fill(String(opts.carbs));
	if (opts.fat != null) await num.nth(3).fill(String(opts.fat));

	await manual.getByRole('button', { name: 'Add' }).click();
	await expect(modal).toBeHidden();
	await expect(page).toHaveURL(/\/nutrition$/);
	const row = page.locator('.meal-list li', { hasText: opts.name });
	await expect(row).toBeVisible({ timeout: 10_000 });
}
