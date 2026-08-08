import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /dashboard — a failed run read must not render a brand-new account.
 *
 * Every card on the dashboard derives from `fetchRunsForDashboard`, which
 * degraded to `[]` on error. During a Supabase blip the app's primary landing
 * surface therefore painted a complete and entirely convincing empty account —
 * zero runs, no PRs, no streak, an empty week — with no error and no retry.
 * A runner has no way to tell that from having actually lost their history.
 */
test.describe('/dashboard — a failed read is not an empty account', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('shows a load error with retry instead of a zeroed dashboard', async ({ page }) => {
		// Scope the failure to the dashboard's own windowed run read: it is the
		// only GET on /runs that carries the started_at window filter.
		await page.route('**/rest/v1/runs?*started_at=gte*', async (route) => {
			if (route.request().method() !== 'GET') return route.fallback();
			await route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated dashboard run read failure' }),
			});
		});

		await page.goto('/dashboard');

		const banner = page.getByTestId('dash-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');
		await expect(page.getByTestId('dash-load-retry')).toBeVisible();

		// None of the zeroed cards may render alongside the failure — that is
		// the misleading state the banner replaces.
		await expect(page.locator('.stat-card')).toHaveCount(0);
	});

	test('a healthy load renders the real dashboard, not the error', async ({ page }) => {
		await page.goto('/dashboard');

		await expect(page.locator('.stat-card').first()).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('dash-load-error')).toHaveCount(0);
	});
});
