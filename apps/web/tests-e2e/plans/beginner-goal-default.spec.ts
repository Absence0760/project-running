import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * runner-new persona (round-5): the wizard defaults the goal to a half
 * marathon, but a brand-new runner who ticks "New to running?" is not
 * training for a half. Enabling the walk-run toggle should switch the goal
 * to 5K — the appropriate first-timer target — without locking it (they can
 * still re-pick 10K) and without clobbering a deliberate 5K/short choice.
 *
 * Drives only the PlanEditor modal (no plan is created), so there is no
 * server state to clean up.
 */
test.describe('/plans/new — beginner walk-run goal default', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const openModal = async (page: import('@playwright/test').Page) => {
		await page.goto('/plans');
		await page.getByRole('button', { name: /New plan/ }).first().click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		return modal;
	};

	test('enabling "New to running?" switches the half-marathon default to 5K', async ({ page }) => {
		const modal = await openModal(page);
		const goal = modal.getByLabel('Goal race');

		await expect(goal).toHaveValue('distance_half');

		await modal.getByRole('checkbox', { name: /New to running/i }).check();
		await expect(goal).toHaveValue('distance_5k');
	});

	test('does not stop the runner re-picking 10K after enabling', async ({ page }) => {
		const modal = await openModal(page);
		const goal = modal.getByLabel('Goal race');

		await modal.getByRole('checkbox', { name: /New to running/i }).check();
		await expect(goal).toHaveValue('distance_5k');

		await goal.selectOption('distance_10k');
		await expect(goal).toHaveValue('distance_10k');
	});

	test('does not clobber a deliberate 5K choice', async ({ page }) => {
		const modal = await openModal(page);
		const goal = modal.getByLabel('Goal race');

		await goal.selectOption('distance_5k');
		await modal.getByRole('checkbox', { name: /New to running/i }).check();
		await expect(goal).toHaveValue('distance_5k');
	});
});
