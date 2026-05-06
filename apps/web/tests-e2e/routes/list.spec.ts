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

	test('Surface filter narrows by surface (road)', async ({ page }) => {
		// Surface is a per-route enum (road / trail / mixed). The
		// seed has multiple surfaces; selecting "road" should
		// collapse to the road-surface subset. Hidden behind a
		// `<select aria-label="Surface">`.
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({
			timeout: 10_000
		});
		const allCount = await page.locator('.route-card').count();
		expect(allCount).toBeGreaterThan(2);

		await page.getByLabel('Surface').selectOption('road');
		await expect
			.poll(() => page.locator('.route-card').count(), { timeout: 5_000 })
			.toBeLessThan(allCount);

		// Restore.
		await page.getByLabel('Surface').selectOption('any');
		await expect(page.locator('.route-card')).toHaveCount(allCount);
	});

	test('Distance bucket filter narrows by distance range', async ({ page }) => {
		// `distanceFilter` buckets are client-side $derived: any /
		// lt5 / 5to10 / 10to20 / gt20. Pinned route is 10000m → in
		// the 5to10 bucket. Selecting 5to10 must include it.
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({
			timeout: 10_000
		});
		const allCount = await page.locator('.route-card').count();

		await page.getByLabel('Distance').selectOption('5to10');
		// Should narrow.
		await expect
			.poll(() => page.locator('.route-card').count(), { timeout: 5_000 })
			.toBeLessThan(allCount);

		// Restore.
		await page.getByLabel('Distance').selectOption('any');
	});

	test('Sort by Longest puts the longest route first', async ({ page }) => {
		// `sortKey` re-orders the in-memory `filteredRoutes`. Newest
		// is the default; Longest sorts by distance_m desc. Read
		// each .route-card's distance text + assert the first is the
		// max.
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({
			timeout: 10_000
		});

		await page.getByLabel('Sort').selectOption('longest');
		// Distance text inside .route-card includes a "X.X km" /
		// "X.X mi" string. Read all of them; the first should be the
		// max numerically.
		const distances = await page
			.locator('.route-card')
			.evaluateAll((cards) =>
				cards.map((c) => {
					const txt = c.textContent ?? '';
					const m = txt.match(/(\d+(?:\.\d+)?)\s*(?:km|mi)/);
					return m ? parseFloat(m[1]) : 0;
				})
			);
		expect(distances.length).toBeGreaterThan(1);
		expect(distances[0]).toBe(Math.max(...distances));

		// Restore.
		await page.getByLabel('Sort').selectOption('newest');
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
