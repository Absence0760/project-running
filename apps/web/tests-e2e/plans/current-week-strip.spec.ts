import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] — CurrentWeekStrip.svelte (the focused 7-day ribbon
 * mounted above the month Calendar section).
 *
 * The strip's window is anchored to the plan's CURRENT week bucket
 * (`start_date + week_index*7`), re-ordered for display by the user's
 * `week_start_day` pref. Its completion count reads off exactly the
 * workouts in that week bucket (the same list the week card counts), so
 * the strip and the week card never disagree.
 *
 * The seed's "Sydney Half 2026" plan (id a1a1eada-…) runs
 * 2026-03-29 → 2026-06-20; today (2026-05-XX) lands inside the plan, so
 * the strip mounts with a current week.
 */

const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

test.describe('/plans/[id] — CurrentWeekStrip (this-week ribbon)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('Strip mounts with the "This week" heading and exactly 7 day cells', async ({
		page
	}) => {
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		const strip = page.locator('section.strip');
		await expect(strip).toBeVisible({ timeout: 10_000 });
		await expect(strip.locator('.strip-title')).toHaveText('This week');
		// The window is always the seven days of the current week bucket.
		await expect(strip.locator('.strip-row .day')).toHaveCount(7);
	});

	test('Completion count renders in the strip head (done / active)', async ({ page }) => {
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		const count = page.locator('section.strip .strip-count');
		await expect(count).toBeVisible({ timeout: 10_000 });
		// Matches "N / M done" — the fraction is the load-bearing legibility
		// of the surface; the exact numbers depend on where "today" lands.
		await expect(count).toContainText('done');
		await expect(count).toContainText('/');
	});

	test('Strip sits above the month Calendar section', async ({ page }) => {
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		const strip = page.locator('section.strip');
		const calendar = page.locator('section.calendar-section');
		await expect(strip).toBeVisible({ timeout: 10_000 });
		await expect(calendar).toBeVisible();
		const stripBox = await strip.boundingBox();
		const calBox = await calendar.boundingBox();
		expect(stripBox).not.toBeNull();
		expect(calBox).not.toBeNull();
		expect(stripBox!.y).toBeLessThan(calBox!.y);
	});

	test('A workout cell in the strip opens the WorkoutEditor (host onSelect wins)', async ({
		page
	}) => {
		// When the current week carries any workout, clicking its strip
		// cell opens the inline editor (the <button> branch) rather than
		// navigating. Skip cleanly on the weeks where the seed's current
		// week has no workout rows (the placeholder gap).
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('section.strip')).toBeVisible({ timeout: 10_000 });
		const cell = page.locator('section.strip .day.has-workout').first();
		if ((await cell.count()) === 0) {
			test.skip(true, 'Current week has no workouts this run (seed gap)');
		}
		const urlBefore = page.url();
		await cell.click();
		await expect(page.locator('.modal')).toBeVisible({ timeout: 5_000 });
		expect(page.url()).toBe(urlBefore);
		await page.locator('.modal .modal-close').click();
		await expect(page.locator('.modal')).toHaveCount(0);
	});
});
