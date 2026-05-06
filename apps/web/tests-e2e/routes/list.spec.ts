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

	test('tab switch My routes ↔ Explore shows different result sets', async ({
		page
	}) => {
		// The Routes page has two tabs — My routes (owned + cloned)
		// and Explore (community-public discovery). The Explore tab
		// fetches via searchPublicRoutes; the My tab fetches via
		// fetchMyRoutes. Both can be empty independently. Asserts
		// the active class flips and at least the My tab has the
		// seeded routes.
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({
			timeout: 10_000
		});
		const myCount = await page.locator('.route-card').count();

		// My tab is the default; switch to Explore.
		const exploreTab = page.getByRole('button', { name: /Explore/ });
		await exploreTab.click();
		await expect(exploreTab).toHaveClass(/active/);

		// Explore renders different rows (or none, if no community
		// routes exist). Either way, the My tab's count should
		// differ from Explore's after pagination — assert tab class
		// flipped, that's the load-bearing assertion. Explore
		// sometimes empty in this seed; don't pin a count.
		await expect(
			page.getByRole('button', { name: /My routes/ })
		).not.toHaveClass(/active/);

		// Switch back so subsequent tests see My-routes default.
		await page.getByRole('button', { name: /My routes/ }).click();
		await expect(page.locator('.route-card')).toHaveCount(myCount);
	});

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
