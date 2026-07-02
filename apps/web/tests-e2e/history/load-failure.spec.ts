import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /history — load-failure vs empty-timeline split.
 *
 * The unified activities feed used to swallow fetch errors into an empty
 * timeline, so a transient network / DB failure rendered the "Nothing logged
 * in this view yet" empty state (with no retry) — identical to a genuinely
 * empty history. fetchActivitiesWithError now distinguishes a real error, and
 * the page renders a distinct, retryable error card instead. This pins that
 * split.
 */
test.describe('/history — load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed activities fetch shows a retryable error, NOT the empty timeline', async ({
		page
	}) => {
		let failNext = true;
		await page.route('**/rest/v1/activities*', async (route) => {
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

		await page.goto('/history');

		// Error state, not the "nothing logged yet" empty card.
		await expect(page.getByTestId('history-load-error')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByText('Nothing logged in this view yet.')).toHaveCount(0);

		// Retry recovers — the second activities fetch is allowed through, so
		// the timeline resolves and the error card clears.
		await page.getByTestId('history-load-error-retry').click();
		await expect(page.getByTestId('history-load-error')).toHaveCount(0, { timeout: 15_000 });
	});
});
