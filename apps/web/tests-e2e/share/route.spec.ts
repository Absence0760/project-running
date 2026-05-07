import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';

/**
 * /share/route/[id] — public route share page.
 *
 * The route's anon path goes through fetchRouteById, which for anon
 * hits the `public_routes` view (drops `geom` + `start_point`).
 *
 * Future depth: full waypoint render with privacy-zone clipping,
 * "save to my routes" affordance for authed visitors, GPX download.
 */

test.describe('/share/route/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor sees the public route name + meta', async ({ page }) => {
		// Pinned public route is "E2E demo public route" with distance
		// 10000 m + surface road; the page should render those into
		// h1 + .route-meta.
		await page.goto(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { name: 'E2E demo public route', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		// The .route-meta strip carries distance + surface tag.
		await expect(page.locator('.surface-tag')).toContainText('road');
		await expect(page.locator('.route-meta')).toContainText('10');
	});

	test('not-found: visiting a missing route id renders the not-found state', async ({
		page
	}) => {
		// Stale-link landing protection — same shape as /runs/[id] +
		// /routes/[id] not-found tests but on the public-share path
		// (anon viewer hitting a deleted route URL).
		const bogusId = '00000000-0000-0000-0000-000000000bad';
		await page.goto(`/share/route/${bogusId}`);
		await page.waitForLoadState('networkidle');
		// /share/route renders the not-found copy as a status paragraph
		// rather than a heading. Match the literal copy.
		await expect(
			page.getByText('Route not found or is private.')
		).toBeVisible({ timeout: 10_000 });
	});
});
