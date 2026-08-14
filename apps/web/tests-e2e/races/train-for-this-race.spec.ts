import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * The race calendar → plan generator bridge. `racePlanPreset` is unit-tested;
 * this pins that the CTA appears on a race a plan can be built for, that it
 * stays off one too close to build for, and that following it seeds the wizard
 * with a Sunday start whose final race week lands on race day.
 *
 * Dates are derived from today rather than hard-coded so the spec can't expire
 * — `search_race_listings` only returns upcoming races, so a frozen future
 * date would eventually stop surfacing at all.
 *
 * Drives only the wizard (no plan is created), so the only server state is the
 * two seeded listings.
 */
test.describe('/races — train for this race', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const DAY_MS = 86_400_000;

	/// The first Sunday at least `days` out, as `yyyy-mm-dd`.
	function sundayAtLeast(days: number): string {
		const d = new Date();
		d.setUTCHours(0, 0, 0, 0);
		const t = new Date(d.getTime() + days * DAY_MS);
		t.setUTCDate(t.getUTCDate() + ((7 - t.getUTCDay()) % 7));
		return t.toISOString().slice(0, 10);
	}

	function minusDays(iso: string, days: number): string {
		return new Date(new Date(iso + 'T00:00:00Z').getTime() - days * DAY_MS)
			.toISOString()
			.slice(0, 10);
	}

	const stamp = Date.now();
	const goalName = `E2E Goal Half ${stamp}`;
	const soonName = `E2E Soon Half ${stamp}`;
	// Far enough out that the half's 12-week default is the binding cap, so
	// the plan starts on the Sunday 11 weeks before race week.
	const goalDate = sundayAtLeast(300);
	const expectedStart = minusDays(goalDate, 11 * 7);
	// Inside RACE_PLAN_MIN_WEEKS — upcoming (so it still lists), but too close.
	const soonDate = new Date(Date.now() + 10 * DAY_MS).toISOString().slice(0, 10);
	const ids: string[] = [];

	test.beforeAll(async () => {
		const admin = getAdminClient();
		for (const [name, date] of [
			[goalName, goalDate],
			[soonName, soonDate],
		]) {
			const { data } = await admin
				.from('race_listings')
				.insert({
					provider: 'manual',
					name,
					race_date: date,
					distance_m: 21097,
					location_label: 'Richmond, VA',
					is_verified: true,
				})
				.select('id')
				.single();
			ids.push((data as { id: string }).id);
		}
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		for (const id of ids) await admin.from('race_listings').delete().eq('id', id);
	});

	test('the CTA seeds a plan whose final week is race week', async ({ page }) => {
		await page.goto('/races');
		await page.getByTestId('races-search').fill(goalName);
		const card = page
			.getByTestId('races-results')
			.getByTestId('race-card')
			.filter({ hasText: goalName });
		await expect(card).toBeVisible({ timeout: 10_000 });

		await card.getByTestId('race-train-for').click();
		await expect(page.getByTestId('race-preset-note')).toBeVisible({ timeout: 10_000 });

		// The race's distance resolves to the half; the name prefills the plan.
		await expect(page.getByLabel('Goal race')).toHaveValue('distance_half');
		await expect(page.getByLabel('Plan name')).toHaveValue(goalName);

		// 12 weeks (the half default) ending on race week, so the start is the
		// Sunday 11 weeks before race day's own Sunday.
		await expect(page.getByLabel('Override total weeks')).toHaveValue('12');
		// The clone-a-template sections carry their own "Start date" fields;
		// the wizard's is the one that names the Sunday rule.
		await expect(page.getByLabel(/first week begins/i)).toHaveValue(expectedStart);
	});

	test('a race too close to build a plan for offers no CTA', async ({ page }) => {
		await page.goto('/races');
		await page.getByTestId('races-search').fill(soonName);
		const card = page
			.getByTestId('races-results')
			.getByTestId('race-card')
			.filter({ hasText: soonName });
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('race-train-for')).toHaveCount(0);
	});

	test('the distance param picks the goal event when present', async ({ page }) => {
		// 10K differs from the wizard's own default, so this proves the param
		// is read rather than coinciding with it.
		await page.goto(`/plans/new?type=training&raceDate=${goalDate}&raceDistance=10000`);
		await expect(page.getByTestId('race-preset-note')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByLabel('Goal race')).toHaveValue('distance_10k');
	});

	test('a link with no distance presets the dates and leaves the goal alone', async ({ page }) => {
		// An absent (or empty) param coerces to 0 through `Number`, so this is
		// the case a presence check written on the number silently gets wrong.
		await page.goto(`/plans/new?type=training&raceDate=${goalDate}&raceDistance=`);
		await expect(page.getByTestId('race-preset-note')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByLabel('Goal race')).toHaveValue('distance_half'); // untouched default
		await expect(page.getByLabel('Override total weeks')).toHaveValue('12');
		await expect(page.getByLabel(/first week begins/i)).toHaveValue(expectedStart);
	});

	test('a hand-edited link to a past race says so instead of silently defaulting', async ({
		page,
	}) => {
		await page.goto('/plans/new?type=training&raceDate=2020-05-10&raceName=Old%20Race');
		await expect(page.getByTestId('race-preset-refusal')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('race-preset-note')).toHaveCount(0);
		// The wizard still works, on its own defaults — the name is not seeded.
		await expect(page.getByLabel('Plan name')).toHaveValue('');
	});
});
