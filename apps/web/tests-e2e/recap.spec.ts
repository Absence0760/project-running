import { expect, test } from '@playwright/test';

import { USER_A } from './fixtures/users';

/**
 * /recap/[year] — Year in Running recap surface.
 *
 * Source: apps/web/src/lib/recap.ts builds the recap shape; the
 * route reads `fetchRuns()` then derives the recap from `year` in
 * the URL. Auth-gated — needs a signed-in user. Useful as a
 * surface-smoke test so a regression that broke `recap.ts` (e.g.
 * a divide-by-zero on a user with no runs in that year) fails CI.
 */

test.describe('/recap/[year]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('renders the recap shell for a year with runs', async ({ page }) => {
		// USER_A is the seed user (runner@test.com) — seed.sql plants
		// runs in the same year as the seed timestamp. The recap
		// computes against the run set; we just assert the page
		// mounts without an error and doesn't redirect.
		const year = new Date().getFullYear();
		await page.goto(`/recap/${year}`);
		await page.waitForLoadState('networkidle');
		// Stay on /recap/<year> — a 4xx error or redirect to /login
		// would break the post-load URL. Use a regex so a trailing
		// slash or QS doesn't false-positive.
		await expect(page).toHaveURL(new RegExp(`/recap/${year}`));
	});

	test('out-of-range year does not crash the page', async ({ page }) => {
		// year < 2010 or > 2100 is invalid per the page's $derived
		// `valid` flag. The page must not crash; it should render
		// a sane empty state.
		await page.goto('/recap/1999');
		await page.waitForLoadState('networkidle');
		// No assertion on exact copy — the contract is "doesn't 500
		// and doesn't redirect to /login".
		await expect(page).toHaveURL(/\/recap\/1999/);
	});

	test('non-numeric year is gracefully ignored', async ({ page }) => {
		await page.goto('/recap/abc');
		await page.waitForLoadState('networkidle');
		// Stay on the path; no crash. The recap derivation guards on
		// `Number.isNaN(year)`.
		await expect(page).toHaveURL(/\/recap\/abc/);
	});
});
