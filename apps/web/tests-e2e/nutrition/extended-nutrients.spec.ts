import { expect, test, type Page } from '@playwright/test';

import { noonOnBrowserDay } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
	);
}

/**
 * Extended-nutrient day roll-up on `/nutrition` — and specifically the
 * COVERAGE honesty that makes it safe to show at all.
 *
 * The five extended nutrients (`fiber_g` / `sugar_g` / `sodium_mg` /
 * `saturated_fat_g` / `cholesterol_mg`) are carried unevenly by both food
 * sources, so a day's total is usually a total over *some* of the day's items.
 * `extended_nutrients.ts` therefore only offers the claims that survive partial
 * coverage, and this spec proves the wiring of exactly that rule through the
 * real page:
 *
 *   - a ceiling BLOWN under partial coverage is still stated (monotone — the
 *     reported items alone already clear it),
 *   - "N left" under partial coverage is WITHHELD (the unreported items could
 *     have eaten all of it), and the row is marked "at least" instead,
 *   - a nutrient no item reported is absent entirely, not a zero row.
 *
 * The arithmetic itself is unit-tested in extended_nutrients.test.ts; this is
 * the UI seam.
 *
 * Determinism — the sodium ceiling is a FLAT 2300 mg plus a sweat allowance
 * that is zero when nothing was trained, so this spec seeds no run and no gym
 * session and can assert the sodium overage to the milligram. The fibre floor
 * scales off the (age-dependent) base calorie goal, so nothing here asserts its
 * absolute value — only that a target exists and that no "left" claim is made.
 *
 * Seeding is direct `food_log` inserts (this spec is about the roll-up, not the
 * composer); deleteSagaUsers CASCADEs them away.
 */
test.describe('/nutrition — extended nutrients, coverage-aware', () => {
	test.describe.configure({ timeout: 120_000 });

	const admin = getAdminClient();

	const WEIGHT_KG = 80;
	const HEIGHT_CM = 178;
	const DOB = '1992-09-12';

	// Sodium: both items report it, so coverage is full and the total is the
	// day. 2600 + 200 = 2800 against the flat 2300 mg ceiling → 500 mg over.
	const SODIUM_A = 2600;
	const SODIUM_B = 200;
	const SODIUM_CEILING_MG = 2300;
	const EXPECTED_SODIUM_OVER = SODIUM_A + SODIUM_B - SODIUM_CEILING_MG;

	// Fibre + sugar: only the first item reports them → partial coverage.
	const FIBER_A = 10;
	const SUGAR_A = 20;

	let user: SagaUser;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Nutrient Saga'] });

		const { error: profErr } = await admin
			.from('user_profiles')
			.update({
				height_cm: HEIGHT_CM,
				date_of_birth: DOB,
				gender: 'male',
				// A calorie target is an Art 9 health use of the age record, so
				// `healthUseDob` (§ 722) withholds the date until the Art 9
				// consent is on record — a saga user starts without it, where
				// the three seed users are stamped by seed.sql. Without this the
				// page renders its untargeted "set your body metrics" state and
				// every assertion below reads as a product bug.
				health_data_consent_at: new Date().toISOString(),
			})
			.eq('id', user.id);
		if (profErr) throw profErr;

		const { error: bmErr } = await admin
			.from('body_metrics')
			.insert({ user_id: user.id, weight_kg: WEIGHT_KG, recorded_at: noonOnBrowserDay() });
		if (bmErr) throw bmErr;

		const { error: setErr } = await admin.from('user_settings').upsert({
			user_id: user.id,
			prefs: { nutrition_activity_level: 'sedentary', nutrition_goal: 'maintain' },
		});
		if (setErr) throw setErr;

		// Two items, deliberately uneven: A carries sodium + fibre + sugar, B
		// carries sodium only. Nothing reports saturated fat or cholesterol.
		const { error: foodErr } = await admin.from('food_log').insert([
			{
				user_id: user.id,
				started_at: noonOnBrowserDay(),
				item_name: 'E2E Nutrient Salted Bowl',
				meal_slot: 'lunch',
				calories: 600,
				protein_g: 30,
				carbs_g: 70,
				fat_g: 20,
				sodium_mg: SODIUM_A,
				fiber_g: FIBER_A,
				sugar_g: SUGAR_A,
			},
			{
				user_id: user.id,
				started_at: noonOnBrowserDay(),
				item_name: 'E2E Nutrient Broth',
				meal_slot: 'dinner',
				calories: 90,
				protein_g: 4,
				carbs_g: 8,
				fat_g: 3,
				sodium_mg: SODIUM_B,
			},
		]);
		if (foodErr) throw foodErr;
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]);
	});

	test('a blown ceiling is stated under partial coverage; a "left" claim is not', async ({
		browser,
	}) => {
		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		await ctx.addInitScript(setConsentAccepted);
		const page: Page = await ctx.newPage();

		try {
			await test.step('the nutrients section renders once an item reports one', async () => {
				await page.goto('/nutrition');
				await expect(page.getByTestId('macro-rings')).toBeVisible({ timeout: 15_000 });
				await expect(page.getByTestId('nutrients')).toBeVisible();
			});

			await test.step('full coverage on sodium → the exact overage against the flat ceiling', async () => {
				const row = page.getByTestId('nutrient-sodium');
				await expect(row).toBeVisible();
				// Both items reported sodium, so no "at least" marker is shown.
				await expect(page.getByTestId('nutrient-partial-sodium')).toHaveCount(0);
				await expect(row.locator('.nutrient-value')).toHaveText(
					String(SODIUM_A + SODIUM_B),
				);
				await expect(row.locator('.nutrient-target')).toHaveText(`/ ${SODIUM_CEILING_MG}`);

				const chip = page.getByTestId('nutrient-state-sodium');
				await expect(chip).toHaveClass(/budget-over/);
				await expect(chip).toHaveText(`${EXPECTED_SODIUM_OVER} mg over`);
			});

			await test.step('partial coverage on fibre → marked "at least", and NO remaining claim', async () => {
				const row = page.getByTestId('nutrient-fiber');
				await expect(row).toBeVisible();
				await expect(row.locator('.nutrient-value')).toHaveText(String(FIBER_A));
				// A target exists (body metrics are seeded) — so the absent chip is
				// the withholding rule firing, not a missing target.
				await expect(row.locator('.nutrient-target')).toBeVisible();
				await expect(page.getByTestId('nutrient-partial-fiber')).toBeVisible();
				await expect(page.getByTestId('nutrient-state-fiber')).toHaveCount(
					0,
					'"N g left" is unsound while an item has not reported fibre',
				);
			});

			await test.step('sugar is reported but deliberately ungraded', async () => {
				const row = page.getByTestId('nutrient-sugar');
				await expect(row.locator('.nutrient-value')).toHaveText(String(SUGAR_A));
				await expect(row.locator('.nutrient-target')).toHaveCount(0);
				await expect(page.getByTestId('nutrient-state-sugar')).toHaveText('No daily target');
			});

			await test.step('a nutrient nothing reported is absent, not a zero row', async () => {
				await expect(page.getByTestId('nutrient-saturatedFat')).toHaveCount(0);
				await expect(page.getByTestId('nutrient-cholesterol')).toHaveCount(0);
			});
		} finally {
			await ctx.close();
		}
	});
});
