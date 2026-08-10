import { expect, test } from '@playwright/test';

import { switchRunsToAllTime } from '../fixtures/helpers';
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

	test('a failed Load more keeps the button and says so, instead of ending the list', async ({
		page
	}) => {
		// The second page used the swallowing fetch, so a failed read came
		// back as zero rows, cleared hasMore, and unmounted the button — the
		// runner's history silently stopped at the first page with no hint
		// that anything had gone wrong.
		//
		// The affordance only exists in paginated mode, which is "All time"
		// with both other filters at "all". USER_A's seeded back-history is
		// deep enough to fill more than one 50-run page.
		await page.goto('/runs');
		await switchRunsToAllTime(page);

		const loadMore = page.getByRole('button', { name: /Load \d+ more/ });
		await expect(loadMore).toBeVisible({ timeout: 15_000 });

		// Fail the page-two read only. `.range()` puts the window in the
		// query string, so `offset=50` identifies it exactly — matching on
		// "the next runs GET" instead would fire on whichever read happened
		// to be in flight.
		let failNext = true;
		await page.route('**/rest/v1/runs**', async (route) => {
			const url = new URL(route.request().url());
			if (route.request().method() === 'GET' && url.searchParams.get('offset') === '50' && failNext) {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated page-2 failure' })
				});
				return;
			}
			await route.fallback();
		});

		await loadMore.click();
		await expect(page.getByTestId('runs-load-more-error')).toBeVisible({ timeout: 15_000 });

		// The affordance survives as the retry, and recovers.
		const retry = page.getByRole('button', { name: 'Retry' });
		await expect(retry).toBeVisible();
		await retry.click();
		await expect(page.getByTestId('runs-load-more-error')).toHaveCount(0, { timeout: 15_000 });
	});
});
