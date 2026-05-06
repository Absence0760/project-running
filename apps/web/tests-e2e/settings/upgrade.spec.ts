import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/upgrade — Pro pricing card + RevenueCat checkout button +
 * one-off donate section.
 *
 * Future depth: Pro-active state when signed in as USER_C_PRO, click
 * "Get Pro" → mock RevenueCat web SDK, verify subscription_tier flips
 * after a stubbed webhook fires.
 */

test.describe('/settings/upgrade', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Pro pricing card renders for a free user', async ({ page }) => {
		// USER_A is on the free tier. The page renders the Pro card
		// with the monthly price. A regression would either crash
		// the page (PRO_PRICE_MONTHLY import broken) or the active
		// state would flip incorrectly (lock_subscription_columns
		// trigger + RPC drift).
		await page.goto('/settings/upgrade');
		await page.waitForLoadState('networkidle');

		// `exact: true` because case-insensitive substring matching
		// otherwise pulls in "Support the project" (contains "pro").
		await expect(
			page.getByRole('heading', { name: 'Pro', exact: true })
		).toBeVisible();
		// Monthly price is rendered as $N / month — assert the
		// "/ month" half is present (PRO_PRICE_MONTHLY is a number
		// constant, so the literal is robust to price changes).
		await expect(page.getByText('/ month')).toBeVisible();
	});
});
