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

		await expect(
			page.getByRole('heading', { name: 'E2E demo public route', level: 1 })
		).toBeVisible({ timeout: 10_000 });

		// The .route-meta strip carries distance + surface tag.
		// (The hero subtitle also renders a .surface-tag; scope to .route-meta
		// to keep the assertion pinned at the body-level summary strip.)
		await expect(page.locator('.route-meta .surface-tag')).toContainText('road');
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

		// Reactive head tags are populated after the fetchRouteById
		// onMount call. Wait until the title flips from the
		// initial "Route — Threkir" placeholder to the
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
			'Threkir'
		);
		// og:image is the per-route og:image PNG (request-time in prod
		// via the share-route Lambda; the dev server's /og/route/[id].png
		// endpoint here). The image URL includes the route id so the
		// unfurl card carries a real track preview rather than the
		// static favicon.
		await expect(page.locator('meta[property="og:image"]')).toHaveAttribute(
			'content',
			`/og/route/${RUNNER_PUBLIC_ROUTE_ID}.png`
		);
		await expect(page.locator('meta[property="og:image:width"]')).toHaveAttribute(
			'content',
			'1200'
		);
		await expect(page.locator('meta[property="og:image:height"]')).toHaveAttribute(
			'content',
			'630'
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
			`/og/route/${RUNNER_PUBLIC_ROUTE_ID}.png`
		);
	});

	test('anon visitor gets a canonical link + JSON-LD structured data', async ({ page }) => {
		// SEO-indexing hardening: the public share page is the single
		// canonical, crawlable surface for a route (the in-app
		// /routes/[id] page canonicals here), and it carries schema.org
		// JSON-LD so search engines get a WebPage + breadcrumb trail.
		// Pin both so a refactor can't silently drop the indexing signals.
		await page.goto(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}`);

		// Canonical is baked at load() time (not onMount), so it's present
		// in the initial HTML. Assert the path tail rather than the full
		// host so the test is independent of PUBLIC_SITE_URL.
		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			new RegExp(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}$`)
		);
		// og:url mirrors the canonical.
		await expect(page.locator('meta[property="og:url"]')).toHaveAttribute(
			'content',
			new RegExp(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}$`)
		);

		// JSON-LD: parse the script body and assert the schema.org shape.
		const ld = await page
			.locator('script[type="application/ld+json"]')
			.first()
			.textContent();
		expect(ld, 'expected a JSON-LD script block').toBeTruthy();
		const obj = JSON.parse(ld!);
		expect(obj['@type']).toBe('WebPage');
		expect(obj.name).toBe('E2E demo public route');
		expect(obj.url).toMatch(new RegExp(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}$`));
		expect(obj.breadcrumb['@type']).toBe('BreadcrumbList');
		expect(obj.breadcrumb.itemListElement).toHaveLength(3);
		expect(obj.breadcrumb.itemListElement[2].name).toBe('E2E demo public route');
	});

	test('per-route og:image renders a real PNG of correct dimensions', async ({ request }) => {
		// The /og/route/[id].png endpoint must return a 1200×630 PNG
		// (Twitter / Facebook recommended unfurl size). The +server.ts
		// handler runs at request time here; in production CloudFront
		// routes /og/route/* to the share-route Lambda (same
		// renderRouteOgPng helper). Either way the URL + Content-Type +
		// magic bytes are pinned.
		const res = await request.get(
			`http://localhost:7777/og/route/${RUNNER_PUBLIC_ROUTE_ID}.png`
		);
		expect(res.status()).toBe(200);
		expect(res.headers()['content-type']).toContain('image/png');
		const body = await res.body();
		// PNG magic number — 89 50 4E 47 0D 0A 1A 0A.
		expect(body.subarray(0, 8)).toEqual(
			Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
		);
		// Sanity: > 1KB rules out a degenerate 0-byte error response.
		expect(body.length).toBeGreaterThan(1024);
	});

	test('not-found: visiting a missing route id renders the not-found state', async ({
		page
	}) => {
		// Stale-link landing protection — same shape as /runs/[id] +
		// /routes/[id] not-found tests but on the public-share path
		// (anon viewer hitting a deleted route URL).
		const bogusId = '00000000-0000-0000-0000-000000000bad';
		await page.goto(`/share/route/${bogusId}`);
		// /share/route renders the not-found copy as a status paragraph
		// rather than a heading. Match the literal copy.
		await expect(
			page.getByText('Route not found or is private.')
		).toBeVisible({ timeout: 10_000 });
	});

	test('anon visitor cannot see a private route via the share URL', async ({ page }) => {
		// `public_routes` view filters on is_public = true, so the share
		// path for a private route should render the same not-found
		// copy as a missing id. Pins the privacy boundary at the read
		// site rather than relying on RLS alone.
		const { getAdminClient } = await import('../fixtures/local-supabase');
		const { USER_A } = await import('../fixtures/users');
		const admin = getAdminClient();
		const routeId = crypto.randomUUID();
		try {
			await admin.from('routes').insert({
				id: routeId,
				user_id: USER_A.id,
				name: 'private route for share test',
				distance_m: 4000,
				is_public: false,
				surface: 'road',
				waypoints: []
			});
			await page.goto(`/share/route/${routeId}`);
			await expect(
				page.getByText('Route not found or is private.')
			).toBeVisible({ timeout: 10_000 });
		} finally {
			await admin.from('routes').delete().eq('id', routeId);
		}
	});

	test('share page links back to Threkir via the brand mark', async ({ page }) => {
		// Anon viewers landing from a paste-link must have a clear
		// click-out to the marketing site. The header brand link is
		// the canonical affordance.
		await page.goto(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}`);
		await expect(page.getByRole('link', { name: 'Threkir' }).first()).toHaveAttribute(
			'href',
			'/'
		);
	});
});
