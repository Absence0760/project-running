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

	test('anon visitor gets full SEO unfurl tags on the share page', async ({ page }) => {
		// Crawlers + chat-app unfurls (Slack, Discord, iMessage,
		// LinkedIn) read these tags from <head>. Pin the full
		// surface so a future refactor of the share page can't
		// silently regress the unfurl card to "untitled link".
		// Coverage:
		//   - title interpolates the route name
		//   - description carries the distance + surface
		//   - Open Graph: og:title / og:description / og:type / og:site_name / og:image
		//   - Twitter: twitter:card=summary_large_image + title / description / image
		await page.goto(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}`);
		await page.waitForLoadState('networkidle');

		// Reactive head tags are populated after the fetchRouteById
		// onMount call. Wait until the title flips from the
		// initial "Route — Run Onward" placeholder to the
		// route-specific version.
		await expect.poll(async () => await page.title()).toContain('E2E demo public route');

		await expect(page.locator('meta[name="description"]')).toHaveAttribute(
			'content',
			/10\.0 km road/
		);
		await expect(page.locator('meta[property="og:title"]')).toHaveAttribute(
			'content',
			/E2E demo public route/
		);
		await expect(page.locator('meta[property="og:description"]')).toHaveAttribute(
			'content',
			/10\.0 km road/
		);
		await expect(page.locator('meta[property="og:type"]')).toHaveAttribute(
			'content',
			'website'
		);
		await expect(page.locator('meta[property="og:site_name"]')).toHaveAttribute(
			'content',
			'Run Onward'
		);
		await expect(page.locator('meta[property="og:image"]')).toHaveAttribute(
			'content',
			'/apple-touch-icon.png'
		);
		await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute(
			'content',
			'summary_large_image'
		);
		await expect(page.locator('meta[name="twitter:title"]')).toHaveAttribute(
			'content',
			/E2E demo public route/
		);
		await expect(page.locator('meta[name="twitter:description"]')).toHaveAttribute(
			'content',
			/10\.0 km road/
		);
		await expect(page.locator('meta[name="twitter:image"]')).toHaveAttribute(
			'content',
			'/apple-touch-icon.png'
		);
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
