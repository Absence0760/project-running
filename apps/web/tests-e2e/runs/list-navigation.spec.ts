import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /runs navigation + toolbar completeness.
 *
 * Two regressions. The Source dropdown offered 4 of the 8 values
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
});
