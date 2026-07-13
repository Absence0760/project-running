import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * runner-new persona finding #1: a brand-new runner who ticks "New to
 * running?" gets a duration-based walk-run plan, not a pace-based one. The
 * live preview must NOT show the Daniels VDOT badge or the five Daniels pace
 * zones (Easy/Marathon/Tempo/Interval/Repetition) — jargon they can't parse
 * and never use. It should show only the duration-based week outline.
 *
 * Drives only the PlanEditor modal (no plan is created), so there is no
 * server state to clean up.
 */
test.describe('/plans/new — beginner walk-run hides pace jargon', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const openModal = async (page: import('@playwright/test').Page) => {
		await page.goto('/plans');
		await page.getByRole('button', { name: /New plan/ }).first().click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		return modal;
	};

	test('a normal plan preview shows the pace zones + VDOT', async ({ page }) => {
		const modal = await openModal(page);
		// The default half-marathon plan renders the pace panel.
		await expect(modal.locator('.paces')).toBeVisible({ timeout: 10_000 });
		await expect(modal.getByText('Easy', { exact: true })).toBeVisible();
		await expect(modal.getByText('Repetition', { exact: true })).toBeVisible();
		await expect(modal.getByRole('heading', { name: 'Week outline' })).toBeVisible();
	});

	test('enabling "New to running?" drops the pace zones + VDOT, keeps the outline', async ({
		page
	}) => {
		const modal = await openModal(page);
		await expect(modal.locator('.paces')).toBeVisible({ timeout: 10_000 });

		await modal.getByRole('checkbox', { name: /New to running/i }).check();

		// The pace panel and the VDOT line are gone...
		await expect(modal.locator('.paces')).toHaveCount(0);
		await expect(modal.locator('.vdot')).toHaveCount(0);
		await expect(modal.getByText('Repetition', { exact: true })).toHaveCount(0);
		await expect(modal.getByText('Daniels VDOT:')).toHaveCount(0);

		// ...but the duration-based week outline still renders.
		await expect(modal.getByRole('heading', { name: 'Week outline' })).toBeVisible();
	});
});
