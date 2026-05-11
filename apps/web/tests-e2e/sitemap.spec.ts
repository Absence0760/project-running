import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_ROUTE_ID, RUNNER_PUBLIC_RUN_ID } from './fixtures/seeded-data';

/**
 * /sitemap.xml — the prerendered, build-time XML sitemap.
 *
 * Crawlers read this file to discover every public share URL the
 * app exposes. The endpoint lives at `src/routes/sitemap.xml/+server.ts`
 * with `prerender = true`, so the file is baked into the static
 * build (no Lambda per-crawl). Test surface here pins:
 *   - It exists at /sitemap.xml.
 *   - Content-Type is application/xml.
 *   - Doc shape is a valid <urlset>.
 *   - Top-level surfaces (/, /feed, /routes?tab=explore) all appear.
 *   - At least one seeded public run + route appear via their share URLs.
 *   - robots.txt advertises the sitemap so crawlers find it.
 */

test.describe('/sitemap.xml — prerendered SEO sitemap', () => {
	// Anon by design — sitemap is public regardless of auth state.
	test.use({ storageState: { cookies: [], origins: [] } });

	test('served as application/xml with a sane document shape', async ({ request }) => {
		const res = await request.get('http://localhost:7777/sitemap.xml');
		expect(res.status()).toBe(200);
		const ct = res.headers()['content-type'] ?? '';
		expect(ct).toMatch(/application\/xml/);
		const body = await res.text();
		expect(body).toMatch(/^<\?xml version="1\.0" encoding="UTF-8"\?>/);
		expect(body).toContain('xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"');
		expect(body.trim()).toMatch(/<\/urlset>$/);
	});

	test('top-level surfaces are present', async ({ request }) => {
		const body = await (await request.get('http://localhost:7777/sitemap.xml')).text();
		// Each of the three top-level surfaces should appear. The host
		// is whatever PUBLIC_SITE_URL is set to at build time (defaults
		// to runonward.com); match the path suffix to stay env-agnostic.
		expect(body).toMatch(/<loc>https?:\/\/[^<]+\/<\/loc>/);
		expect(body).toMatch(/<loc>https?:\/\/[^<]+\/feed<\/loc>/);
		expect(body).toMatch(/<loc>https?:\/\/[^<]+\/routes\?tab=explore<\/loc>/);
	});

	test('seeded public run + route appear as share URLs', async ({ request }) => {
		const body = await (await request.get('http://localhost:7777/sitemap.xml')).text();
		expect(body).toContain(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
		expect(body).toContain(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}`);
	});

	test('robots.txt advertises the sitemap location', async ({ request }) => {
		const res = await request.get('http://localhost:7777/robots.txt');
		expect(res.status()).toBe(200);
		const body = await res.text();
		expect(body).toMatch(/Sitemap:\s*\/sitemap\.xml/);
	});
});
