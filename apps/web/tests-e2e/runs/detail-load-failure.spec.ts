import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /runs/[id] — a failed read must not claim the run does not exist.
 *
 * `fetchRunById` destructured only `{ data }` from `.single()`. supabase-js
 * resolves `{data: null, error}` on a transport/RLS failure rather than
 * throwing, so an unreachable backend was indistinguishable from a deleted
 * run and the highest-traffic detail page in the app rendered "Run not
 * found" — telling an owner their run is gone when it is merely unreachable.
 *
 * The helper now reports the error separately (PGRST116 "no rows" stays a
 * genuine not-found) and the page states the failure with a retry.
 */
test.describe('/runs/[id] — a failed read is not a missing run', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('shows a load error, not the not-found card', async ({ page }) => {
		// Fail only the owner-scoped single-run read.
		await page.route('**/rest/v1/runs?*id=eq.*', async (route) => {
			if (route.request().method() !== 'GET') return route.fallback();
			await route.fulfill({
				status: 500,
				contentType: 'application/json',
				body: JSON.stringify({ message: 'simulated run read failure' }),
			});
		});

		// Any run id: the read fails before ownership is ever established.
		await page.goto('/runs/00000000-0000-4000-8000-000000000abc');

		const banner = page.getByTestId('run-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');
		await expect(page.getByRole('heading', { name: 'Run not found' })).toHaveCount(0);
	});

	test('a genuinely absent run still gets the not-found card', async ({ page }) => {
		// No interception: the read succeeds and matches no row (PGRST116),
		// which must stay a not-found rather than becoming an error.
		await page.goto('/runs/00000000-0000-4000-8000-000000000abc');

		await expect(page.getByRole('heading', { name: 'Run not found' })).toBeVisible({
			timeout: 15_000,
		});
		await expect(page.getByTestId('run-load-error')).toHaveCount(0);
	});
});
