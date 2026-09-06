import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /runs navigation + toolbar completeness.
 *
 * Three regressions, all about the list a runner comes BACK to. `renderLimit`
 * was component state and not in the `snapshot.capture` payload, and the reset
 * effect fired on the restore's own filter writes — so a list expanded past one
 * page collapsed back to 50 cards on Back, which made the document too short
 * for the captured scroll to be re-applied. The Source dropdown offered 4 of
 * the 8 values
 * `runs_source_check` allows, so a Wear OS runner saw a "Watch" badge on every
 * card and had no Watch option to filter by. And `/runs/heatmap`'s
 * "Back to runs" button pointed at `/history` — the
 * cross-modal timeline, not the run list its only entry point came from. It is
 * also a BACK navigation now when the runner arrived from /runs, because a
 * soft-nav forward creates a new history entry and drops the /runs snapshot
 * (filters + scroll) the runner had built up.
 */

test.describe('/runs — navigation and toolbar', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the heatmap Back button returns to /runs, not /history', async ({ page }) => {
		await page.goto('/runs');
		await expect(page.getByTestId('runs-surface')).toBeVisible({ timeout: 15_000 });

		await page.getByRole('link', { name: 'Heatmap' }).click();
		await expect(page).toHaveURL(/\/runs\/heatmap$/);

		const back = page.getByRole('link', { name: 'Back to runs' });
		await expect(back).toHaveAttribute('href', '/runs');
		await back.click();
		await expect(page).toHaveURL(/\/runs$/);
		await expect(page.getByTestId('runs-surface')).toBeVisible();
	});
	test('the source filter offers every source the column allows', async ({ page }) => {
		await page.goto('/runs');
		await expect(page.getByTestId('runs-surface')).toBeVisible({ timeout: 15_000 });

		const select = page.getByLabel('Source');
		await expect(select).toBeVisible();
		const values = await select.locator('option').evaluateAll((els) =>
			els.map((e) => (e as HTMLOptionElement).value)
		);
		expect(values).toEqual([
			'all',
			'app',
			'watch',
			'healthkit',
			'healthconnect',
			'strava',
			'garmin',
			'parkrun',
			'race'
		]);
		// The two that needed copy rather than a brand mark.
		await expect(select.locator('option[value="watch"]')).toHaveText('Watch');
		await expect(select.locator('option[value="race"]')).toHaveText('Race');
	});
	test('Back to /runs keeps the expanded render window and the scroll position', async ({
		page
	}) => {
		await page.goto('/runs');
		await expect(page.getByTestId('runs-surface')).toBeVisible({ timeout: 15_000 });

		// Two controls, two different jobs. "All time" widens the set to every
		// seeded run (the default range leaves too few to overflow one page),
		// and re-sorting is what puts the list in `full` mode -- `runsFetchMode`
		// returns `full` when the view is NARROWED or REORDERED, and "all" is
		// the un-narrowed value, so the range alone leaves it `paginated` and
		// the render window this test is about never applies.
		await page.getByLabel('Date range').selectOption('all');
		await page.getByLabel('Sort').selectOption('oldest');
		await expect(page.getByTestId('runs-surface')).toHaveAttribute(
			'data-list-state',
			'loaded-full',
			{ timeout: 15_000 }
		);

		const showMore = page.getByTestId('runs-show-more');
		// The seed has enough runs to overflow one 50-card page; if it ever
		// stops doing so the window is not exercised and the test should say
		// so rather than pass vacuously.
		await expect(showMore).toBeVisible({ timeout: 15_000 });
		await showMore.click();

		const cards = page.locator('a.run-card');
		const expanded = await cards.count();
		expect(expanded).toBeGreaterThan(50);

		await page.mouse.wheel(0, 4000);
		const scrolled = await page.evaluate(() => window.scrollY);
		expect(scrolled).toBeGreaterThan(500);

		await cards.nth(expanded - 1).click();
		await expect(page).toHaveURL(/\/runs\/[0-9a-f-]+$/);

		await page.goBack();
		await expect(page.getByTestId('runs-surface')).toBeVisible({ timeout: 15_000 });
		await expect(cards).toHaveCount(expanded);
		// The window is what makes the document tall enough for the scroll the
		// restore re-applies; a collapsed list clamps it back near the top.
		await expect
			.poll(async () => page.evaluate(() => window.scrollY), { timeout: 10_000 })
			.toBeGreaterThan(scrolled * 0.8);
	});

	test('changing a filter after a restore still collapses the window', async ({ page }) => {
		// The reset must compare the filter SET rather than fire on any write
		// to it, or suppressing it for the restore suppresses it for good.
		await page.goto('/runs');
		await expect(page.getByTestId('runs-surface')).toBeVisible({ timeout: 15_000 });
		await page.getByLabel('Date range').selectOption('all');
		await page.getByLabel('Sort').selectOption('oldest');
		await expect(page.getByTestId('runs-surface')).toHaveAttribute(
			'data-list-state',
			'loaded-full',
			{ timeout: 15_000 }
		);
		await page.getByTestId('runs-show-more').click();

		const cards = page.locator('a.run-card');
		expect(await cards.count()).toBeGreaterThan(50);

		await page.getByLabel('Source').selectOption('app');
		await expect
			.poll(async () => cards.count(), { timeout: 10_000 })
			.toBeLessThanOrEqual(50);
	});
});
