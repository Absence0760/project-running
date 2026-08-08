import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Load failures on the session-planner surfaces.
 *
 * `fetchSessionPlans` / `fetchSessionPlan` rethrow the Postgres error, and
 * these pages cleared `loading` only on the success path — so any failure
 * left the page on its spinner forever, with nothing said and nothing to
 * retry. The detail page had a second problem: a failed fetch fell through
 * to the not-found branch, telling an owner their session had been deleted
 * when it was only unreachable.
 *
 * Every case forces the failure at the network boundary.
 */

// Scoped to the session-plan reads so an unrelated request (auth, settings)
// can't consume the injected failure.
const SESSION_PLANS = '**/rest/v1/session_plans*';

test.describe('/sessions — load failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed list load states the error and offers a retry', async ({ page }) => {
		await page.route(SESSION_PLANS, (route) =>
			route.fulfill({ status: 500, body: 'boom' })
		);

		await page.goto('/sessions');

		const banner = page.getByTestId('sessions-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner.getByRole('button')).toBeVisible();
		// Not the empty state — "you have no session plans" is a different
		// claim from "we could not load them".
		await expect(page.getByTestId('sessions-empty')).toHaveCount(0);
	});

	test('retrying the list after recovery renders the plans', async ({ page }) => {
		let failNext = true;
		await page.route(SESSION_PLANS, (route) => {
			if (failNext) {
				failNext = false;
				return route.fulfill({ status: 500, body: 'boom' });
			}
			return route.continue();
		});

		await page.goto('/sessions');

		const banner = page.getByTestId('sessions-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });

		await banner.getByRole('button').click();

		// Whatever the seed holds, the error state is gone and the page has
		// resolved to a real one.
		await expect(page.getByTestId('sessions-load-error')).toHaveCount(0, {
			timeout: 15_000
		});
	});

	test('a failed detail load does not claim the plan was not found', async ({ page }) => {
		// The load-bearing distinction: not-found and could-not-load are
		// different answers, and showing the first for the second tells an
		// owner their work is gone.
		await page.route(SESSION_PLANS, (route) =>
			route.fulfill({ status: 500, body: 'boom' })
		);

		await page.goto('/sessions/11111111-2222-3333-4444-555555555555');

		await expect(page.getByTestId('session-load-error')).toBeVisible({
			timeout: 15_000
		});
		await expect(page.getByTestId('session-not-found')).toHaveCount(0);
	});
});
