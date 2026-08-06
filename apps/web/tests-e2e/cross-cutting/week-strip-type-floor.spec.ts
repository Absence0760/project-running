import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * The two week ribbons at a phone-width viewport, against the 11 px
 * micro-label floor § 482 pins on mobile and § 525 brought to web.
 *
 * Both carried the identical narrow-viewport shrink § 525 removed from
 * `PlanCalendar` — a `max-width: 40rem` media query dropping micro-labels to
 * 0.55rem / 0.6rem (8.8 / 9.6 px). `font_size_floor_guard.test.ts` scans the
 * source and so can see the literal, but it cannot prove the *fix*: what fails
 * in this class is a higher-specificity media-query override winning over a
 * compliant base rule, and only the resolved cascade says which declaration
 * paints. Planting either override back fails this spec at 8.8 px while the
 * base rule still reads 11.2.
 *
 * The pair is deliberately NOT merged: `CurrentWeekStrip` anchors its 7-day
 * window to `start_date + week_index * 7` (the plan's week) and `ThisWeekStrip`
 * to the real calendar week containing `now` (§ 509 found their duplication was
 * presentation-only). They are asserted on the same floor, from two routes.
 */

const FLOOR_PX = 11;
const PHONE = { width: 360, height: 780 };
const RICHMOND_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

/**
 * Resolve `getComputedStyle().fontSize` for every element matching `selector`
 * inside `root`, assert each clears the floor, and require `expected` of them.
 *
 * The count is not decoration. The shrink lived on `.kind` / `.day-dist`, and a
 * selector that matches nothing passes every size assertion while measuring
 * nothing — which is how the first draft of this spec passed with the override
 * planted back.
 */
async function expectAtFloor(
	page: import('@playwright/test').Page,
	root: string,
	selector: string,
	expected: number
): Promise<void> {
	const sizes = await page
		.locator(`${root} ${selector}`)
		.evaluateAll((els) =>
			els.map((el) => parseFloat(getComputedStyle(el as HTMLElement).fontSize))
		);
	expect(sizes.length, `${root} ${selector} matched no element to measure`).toBe(expected);
	for (const px of sizes) {
		expect(
			px,
			`${root} ${selector} resolves to ${px}px at ${PHONE.width}px wide`
		).toBeGreaterThanOrEqual(FLOOR_PX);
	}
}

test.describe('week ribbons — 11px micro-label floor at phone width', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context, page }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		await page.setViewportSize(PHONE);
	});

	test('ThisWeekStrip day labels and distances clear the floor', async ({ page }) => {
		await page.goto('/dashboard');
		await expect(page.locator('.week-strip')).toBeVisible({ timeout: 10_000 });

		// Seven cells always render — a rest day draws a `·` rather than
		// dropping the element — so both selectors are pinned at 7 and the test
		// does not depend on the seed having runs in the live week.
		await expectAtFloor(page, '.week-strip', '.day-dow', 7);
		await expectAtFloor(page, '.week-strip', '.day-dist', 7);
	});

	test.describe('CurrentWeekStrip', () => {
		// The seed slides the plan onto a now()-relative window that lands the
		// CURRENT week inside its deliberate week-5..10 workout gap, so `.kind`
		// and `.dist` — the two labels that carried the shrink — never render on
		// the seeded data. One workout on today's date in the current week is
		// what makes the assertion able to fail.
		let workoutId: string | null = null;

		test.beforeAll(async () => {
			const admin = getAdminClient();
			const { data: plan } = await admin
				.from('training_plans')
				.select('start_date')
				.eq('id', RICHMOND_HALF_PLAN_ID)
				.single();
			if (!plan) throw new Error('week-strip floor: Richmond Half plan missing from the seed');

			const today = new Date();
			const todayIso = today.toISOString().slice(0, 10);
			const startMs = Date.parse(`${plan.start_date}T00:00:00Z`);
			const todayMs = Date.parse(`${todayIso}T00:00:00Z`);
			const weekIndex = Math.floor((todayMs - startMs) / (7 * 86_400_000));

			const { data: week } = await admin
				.from('plan_weeks')
				.select('id')
				.eq('plan_id', RICHMOND_HALF_PLAN_ID)
				.eq('week_index', weekIndex)
				.single();
			if (!week)
				throw new Error(
					`week-strip floor: plan has no week at index ${weekIndex} (start ${plan.start_date})`
				);

			// `plan_workouts_one_per_day` is unique on (week_id, scheduled_date),
			// so clear today's slot before claiming it.
			await admin
				.from('plan_workouts')
				.delete()
				.eq('week_id', week.id)
				.eq('scheduled_date', todayIso);
			const { data: created, error } = await admin
				.from('plan_workouts')
				.insert({
					week_id: week.id,
					scheduled_date: todayIso,
					kind: 'tempo',
					target_distance_m: 8000
				})
				.select('id')
				.single();
			if (error || !created)
				throw new Error(`week-strip floor: could not seed a workout — ${error?.message}`);
			workoutId = created.id;
		});

		test.afterAll(async () => {
			if (!workoutId) return;
			await getAdminClient().from('plan_workouts').delete().eq('id', workoutId);
		});

		test('day, kind and distance labels clear the floor', async ({ page }) => {
			await page.goto(`/plans/${RICHMOND_HALF_PLAN_ID}`);
			await expect(page.locator('.strip')).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.strip .day.has-workout')).toHaveCount(1);

			await expectAtFloor(page, '.strip', '.dow', 7);
			await expectAtFloor(page, '.strip', '.kind', 1);
			await expectAtFloor(page, '.strip', '.dist', 1);
		});
	});
});
