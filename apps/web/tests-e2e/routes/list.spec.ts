import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /routes — tabbed list (My routes / Explore). Owner-only ops here;
 * starring + public-toggle live in routes/detail.spec.ts because
 * those flows start on the detail page.
 *
 * Future depth: surface filter, distance bucket, sort-key change,
 * starred-only toggle (currently only verified as part of the
 * star-route round-trip in routes/detail.spec.ts).
 */

test.describe('/routes', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('search box narrows the My-routes list to a name match', async ({
		page
	}) => {
		// /routes computes `filteredRoutes` from a $derived that does a
		// case-insensitive substring match on `name`. Pinned route
		// "E2E demo public route" plus the seed's "Richmond Park Loop /
		// Thames Path 5K / Battersea / Sunday Long Run / Commute Run"
		// give us > 1 row to start with.
		await page.goto('/routes');
		await page.waitForLoadState('networkidle');
		await expect(page.locator('.route-card').first()).toBeVisible();

		const before = await page.locator('.route-card').count();
		expect(before).toBeGreaterThan(2);

		// "Richmond" → exactly the Richmond Park Loop seed row.
		await page.getByLabel('Search routes').fill('Richmond');
		await expect(page.locator('.route-card')).toHaveCount(1);
		await expect(
			page.locator('.route-card').first()
		).toContainText('Richmond Park Loop');

		// Clear by clicking the clear button — exposed for that purpose.
		await page.getByRole('button', { name: 'Clear search' }).click();
		await expect(page.locator('.route-card')).toHaveCount(before);
	});
});
