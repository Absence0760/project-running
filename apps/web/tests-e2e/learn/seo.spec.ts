import { expect, test } from '@playwright/test';

/**
 * `/learn/<slug>` — SEO head: title, canonical, Open Graph, JSON-LD.
 * The whole point of the Learn surface is search/share discoverability,
 * so the per-guide head must be present and well-formed.
 */

test.describe('/learn/road-running-101 (SEO head)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('title, canonical, Open Graph, and Article JSON-LD are present', async ({ page }) => {
		await page.goto('/learn/road-running-101');

		await expect(page).toHaveTitle(/Road running 101 — Threkir/);

		const canonical = page.locator('link[rel="canonical"]');
		const canonicalHref = await canonical.getAttribute('href');
		expect(canonicalHref).toBeTruthy();
		expect(canonicalHref).toMatch(/^https?:\/\/.+\/learn\/road-running-101$/);

		expect(
			await page.locator('meta[property="og:title"]').getAttribute('content')
		).toContain('Road running 101');
		expect(
			await page.locator('meta[property="og:description"]').getAttribute('content')
		).toBeTruthy();
		expect(await page.locator('meta[property="og:type"]').getAttribute('content')).toBe('article');
		expect(await page.locator('meta[property="og:image"]').getAttribute('content')).toBeTruthy();

		const ldText = await page
			.locator('script[type="application/ld+json"]')
			.first()
			.textContent();
		expect(ldText).toBeTruthy();
		const ld = JSON.parse(ldText as string);
		expect(ld['@type']).toBe('Article');
		expect(ld.headline).toBe('Road running 101');
	});
});
