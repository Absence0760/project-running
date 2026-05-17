import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /recap/[year] — Year in Running recap surface.
 *
 * Page lives at apps/web/src/routes/recap/[year]/+page.svelte and
 * pulls aggregates from apps/web/src/lib/recap.ts. The recap module
 * is unit-tested separately (recap.test.ts); these tests pin the
 * page-level wiring: invalid year → empty state, valid signed-in →
 * hero + cards + monthly chart, anon → sign-in prompt.
 *
 * USER_A is the seed user and has 12 runs distributed across recent
 * timestamps in seed.sql, so the "real recap" path renders against
 * stable data without needing fixtures of our own.
 */

const CURRENT_YEAR = new Date().getFullYear();

test.describe('/recap/[year] — anon visitor', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('valid year still loads (no auth-wall redirect)', async ({ page }) => {
		// /recap is public per the layout's publicPaths list. The page
		// itself renders 'Sign in to see your year in running.' when
		// auth.user is unset — that's the contract.
		await page.goto(`/recap/${CURRENT_YEAR}`);
		await page.waitForLoadState('networkidle');
		await expect(page).toHaveURL(new RegExp(`/recap/${CURRENT_YEAR}`));
		await expect(page.getByText(/Sign in to see your year/)).toBeVisible();
	});

	test('out-of-range year (1999) renders the picker hint', async ({ page }) => {
		await page.goto('/recap/1999');
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(/Pick a year between 2010 and 2100/)).toBeVisible();
	});

	test('out-of-range year (2200) renders the same hint', async ({ page }) => {
		await page.goto('/recap/2200');
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(/Pick a year between 2010 and 2100/)).toBeVisible();
	});

	test('non-numeric year is gracefully ignored', async ({ page }) => {
		await page.goto('/recap/abc');
		await page.waitForLoadState('networkidle');
		await expect(page.getByText(/Pick a year between 2010 and 2100/)).toBeVisible();
		await expect(page).toHaveURL(/\/recap\/abc/);
	});

	test('document title reflects the year param', async ({ page }) => {
		await page.goto('/recap/2024');
		await expect(page).toHaveTitle(/2024 in running/);
	});
});

test.describe('/recap/[year] — signed-in seed user', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('current-year recap renders hero + cards + monthly chart', async ({ page }) => {
		await page.goto(`/recap/${CURRENT_YEAR}`);
		await page.waitForLoadState('networkidle');

		// Header rendered (kicker + bignum + subhead). Kicker copy is
		// the canonical "I'm rendering as a real recap" signal — the
		// empty-state branch doesn't print it.
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});

		// Six labelled cards in the stats grid — pin each label so
		// a card refactor that drops or renames one is caught.
		for (const label of [
			'Longest run',
			'Fastest pace',
			'Best streak',
			'Top week',
			'Routes run',
			'Earliest start'
		]) {
			await expect(page.getByText(label)).toBeVisible();
		}

		// Monthly bar chart present + has 12 columns.
		await expect(page.getByRole('heading', { name: 'Distance by month' })).toBeVisible();
		const bars = page.locator('.bar-col');
		await expect(bars).toHaveCount(12);
	});

	test('empty-year recap renders the encouragement empty state', async ({ page }) => {
		// 2010 is in-range but the seed user has no runs in it →
		// the hero-empty branch fires.
		await page.goto('/recap/2010');
		await page.waitForLoadState('networkidle');
		await expect(
			page.getByText(/No runs in 2010 yet/)
		).toBeVisible({ timeout: 10_000 });
		// The hero-empty branch does NOT render the cards grid.
		await expect(page.getByText('Longest run')).toHaveCount(0);
	});

	test('Share recap button is visible on the populated path', async ({ page }) => {
		await page.goto(`/recap/${CURRENT_YEAR}`);
		await page.waitForLoadState('networkidle');
		// Wait for the populated branch to mount.
		await expect(page.getByText(`My ${CURRENT_YEAR} in running`).first()).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByRole('button', { name: 'Share recap' })).toBeVisible();
	});
});
