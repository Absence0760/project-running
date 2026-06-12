import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/new built-in starter library (Training P3). The engine
 * (starter_plans.ts) is unit-tested; this pins the picker UI: choosing a
 * starter instantiates it via generatePlan → createTrainingPlan and lands on
 * the new plan's detail. Clears USER_A's plans around the test so the
 * one-active-plan index can't reject the create.
 */

test.describe('/plans/new starter library', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		await getAdminClient().from('training_plans').delete().eq('user_id', USER_A.id);
	});
	test.afterEach(async () => {
		await getAdminClient().from('training_plans').delete().eq('user_id', USER_A.id);
	});

	test('picking a built-in starter creates a plan and lands on its detail', async ({ page }) => {
		await page.goto('/plans/new');
		await expect(
			page.getByRole('heading', { level: 2, name: 'Start from a built-in plan' })
		).toBeVisible({ timeout: 10_000 });

		await page.getByLabel('Starter plan').selectOption('half_12wk');
		// Scope to the starter section — the from-scratch PlanEditor also has a
		// "Create plan" submit button.
		await page
			.locator('.starter-picker')
			.getByRole('button', { name: 'Create plan' })
			.click();

		await page.waitForURL(/\/plans\/[0-9a-f-]{36}$/, { timeout: 15_000 });

		// The 12-week half-marathon starter persisted as USER_A's active plan.
		const { data } = await getAdminClient()
			.from('training_plans')
			.select('name, status, goal_event')
			.eq('user_id', USER_A.id)
			.eq('status', 'active')
			.maybeSingle();
		expect(data?.name).toContain('Half Marathon');
		expect(data?.goal_event).toBe('distance_half');
	});
});
