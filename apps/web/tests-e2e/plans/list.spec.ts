import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /plans — training-plan list. Drills into /plans/[id] in the same
 * test for now (one seeded plan); a future round can split out a
 * dedicated plans/detail.spec.ts when the plan-detail surface gets
 * its own depth (week-grid, edit-plan, mark-workout-done, etc).
 */

test.describe('/plans', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('seeded Sydney Half 2026 plan renders + drill into detail', async ({
		page
	}) => {
		// seed.sql provisions a single active training_plan named
		// "Sydney Half 2026" with id a1a1eada-aaaa-... A regression
		// in the plan-list fetch (RLS, query, or rendering) would
		// surface as the empty state instead. The card links to
		// /plans/<id> via an outer <a>, so we can also navigate
		// through it to confirm /plans/[id] mounts.
		await page.goto('/plans');
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { name: 'No plans yet.' })
		).toHaveCount(0);
		await expect(
			page.getByRole('heading', { name: 'Sydney Half 2026' })
		).toBeVisible({ timeout: 10_000 });

		// Drill into the plan detail to prove /plans/[id] also mounts.
		await page.getByRole('link', { name: /Sydney Half 2026/ }).click();
		await expect(page).toHaveURL(/\/plans\/[0-9a-f-]+$/);
		await page.waitForLoadState('networkidle');
		// /plans/[id] renders the plan name as a heading too.
		await expect(
			page.getByRole('heading', { name: /Sydney Half 2026/ })
		).toBeVisible({ timeout: 10_000 });
	});
});
