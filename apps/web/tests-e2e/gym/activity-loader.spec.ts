import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * ActivityLoader (lib/components/ActivityLoader.svelte) — verifies the shared
 * animated-athlete loader actually renders in a real loading state.
 *
 * /gym/routines is the cheapest page to hold in its loading branch: `loading`
 * stays true until `fetchGymRoutinesWithError` resolves. We stall the
 * gym_routines GET so the branch never advances, then assert the loader's
 * accessible surface — a role="status" region carrying the localized
 * "Loading…" text with an <svg> figure inside. The stalled request is released
 * (aborted) at the end so the page can settle and the context tears down clean.
 */
test.describe('ActivityLoader in a live loading state', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/gym/routines shows the animated-athlete loader while data is in flight', async ({
		page,
	}) => {
		let releaseGate: () => void = () => {};
		const gate = new Promise<void>((resolve) => {
			releaseGate = resolve;
		});

		// Hold the routines fetch open so the page can't leave its loading
		// branch. Non-GET (or a retry) falls through untouched.
		await page.route('**/rest/v1/gym_routines**', async (route) => {
			if (route.request().method() !== 'GET') {
				await route.fallback();
				return;
			}
			await gate;
			await route.abort();
		});

		await page.goto('/gym/routines');

		const loader = page.locator('[role="status"]');
		await expect(loader).toBeVisible({ timeout: 10_000 });
		await expect(loader).toContainText('Loading…');
		await expect(loader.locator('svg')).toBeVisible();

		// Release the stalled request so the load resolves (error branch) and
		// the page settles before teardown — no dangling in-flight route.
		releaseGate();
		await expect(loader).toHaveCount(0, { timeout: 10_000 });
	});
});
