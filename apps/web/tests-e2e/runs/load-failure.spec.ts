import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /runs — load-failure vs empty-state split.
 *
 * A transient network / DB failure loading the run list used to collapse to
 * an empty array — indistinguishable from a brand-new account with zero runs
 * — so /runs showed the "No runs yet / log your first run" onboarding card
 * with no way to retry. fetchRunsWithError now distinguishes a real error
 * from a genuinely-empty result, and the page renders a distinct, retryable
 * error card. This pins that split.
 */
test.describe('/runs — load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed runs fetch shows a retryable error, NOT the empty state', async ({ page }) => {
		let failNext = true;
		await page.route('**/rest/v1/runs**', async (route) => {
			if (route.request().method() === 'GET' && failNext) {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated failure' })
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/runs');

		// Error state, not the "no runs yet" onboarding card.
		await expect(page.getByTestId('runs-load-error')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('runs-empty-no-data')).toHaveCount(0);

		// Retry recovers — the second runs fetch is allowed through, so the
		// list resolves and the error card clears.
		await page.getByTestId('runs-load-error-retry').click();
		await expect(page.getByTestId('runs-load-error')).toHaveCount(0, { timeout: 15_000 });
	});
});
