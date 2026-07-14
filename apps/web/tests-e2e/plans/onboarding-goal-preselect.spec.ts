import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * runner-new persona: the onboarding "Create my training plan" CTA deep-links
 * to `/plans/new?type=training&goal=<primary_goal>`. This pins that the goal
 * query param preselects the PlanEditor — the durable half of the finding
 * (`planPresetForGoal` is unit-tested; this proves it actually seeds the form),
 * so a brand-new runner lands on the right plan shape without hunting for the
 * buried "New to running?" walk-run checkbox.
 *
 * Drives only the PlanEditor (no plan is created), so there is no server state
 * to clean up.
 */
test.describe('/plans/new — onboarding goal preselection', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a beginner goal ticks the walk-run toggle and seeds the 5K', async ({ page }) => {
		await page.goto('/plans/new?type=training&goal=5k');
		const goal = page.getByLabel('Goal race');
		await expect(goal).toBeVisible({ timeout: 5_000 });
		// 5k / general_fitness / weight_loss all seed the beginner walk-run 5K.
		await expect(goal).toHaveValue('distance_5k');
		await expect(page.getByRole('checkbox', { name: /New to running/i })).toBeChecked();
	});

	test('general_fitness also seeds the beginner walk-run 5K', async ({ page }) => {
		await page.goto('/plans/new?type=training&goal=general_fitness');
		const goal = page.getByLabel('Goal race');
		await expect(goal).toBeVisible({ timeout: 5_000 });
		await expect(goal).toHaveValue('distance_5k');
		await expect(page.getByRole('checkbox', { name: /New to running/i })).toBeChecked();
	});

	test('a distance goal preselects that distance without the walk-run toggle', async ({ page }) => {
		await page.goto('/plans/new?type=training&goal=half_marathon');
		const goal = page.getByLabel('Goal race');
		await expect(goal).toBeVisible({ timeout: 5_000 });
		await expect(goal).toHaveValue('distance_half');
		await expect(page.getByRole('checkbox', { name: /New to running/i })).not.toBeChecked();
	});

	test('an unknown goal param is ignored (defaults intact)', async ({ page }) => {
		await page.goto('/plans/new?type=training&goal=bogus');
		const goal = page.getByLabel('Goal race');
		await expect(goal).toBeVisible({ timeout: 5_000 });
		// Falls back to the PlanEditor default, unticked.
		await expect(goal).toHaveValue('distance_half');
		await expect(page.getByRole('checkbox', { name: /New to running/i })).not.toBeChecked();
	});
});
