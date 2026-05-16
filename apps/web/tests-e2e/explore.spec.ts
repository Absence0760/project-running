import { expect, test } from '@playwright/test';

import { USER_A } from './fixtures/users';

/**
 * /explore — thin redirect to /routes?tab=explore.
 *
 * Kept around so old links and Android deep links still resolve. The
 * behaviour is a single goto call inside onMount; pin the redirect
 * resolves to the canonical Explore tab, otherwise a regression that
 * dropped the redirect would silently land users on a blank page.
 */

test.describe('/explore', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('redirects to /routes?tab=explore', async ({ page }) => {
		await page.goto('/explore');
		await page.waitForURL(/\/routes\?tab=explore/, { timeout: 10_000 });
		// The Explore tab is the active one after the redirect. The /routes
		// polish made the tab strip ARIA-compliant: role="tab" with
		// aria-selected reflecting the URL ?tab= param.
		await expect(
			page.getByRole('tab', { name: /Explore/ })
		).toHaveAttribute('aria-selected', 'true', { timeout: 10_000 });
	});
});
