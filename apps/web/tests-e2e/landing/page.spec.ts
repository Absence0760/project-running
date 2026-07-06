import { expect, test } from '@playwright/test';

/**
 * `/` — anon landing page.
 *
 * Authenticated visitors are auto-redirected to /dashboard via an
 * $effect in the page component; the marketing hero only renders for
 * unauthenticated visitors. Tests live here in isolation rather than
 * mixed with the auth flow because this is the only page anon users
 * see by default (everything else either redirects to /login or is
 * gated by `isPublic` in the layout's auth guard).
 */

test.describe('/ (landing)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor sees hero + Get Started CTA', async ({ page }) => {
		// The h1 is split across <br/>s; the accessible name is the
		// concatenated text "Plan routes. Track runs. Analyse
		// everything." Match by the leading phrase.
		await page.goto('/');

		await expect(
			page.getByRole('heading', { name: /Plan routes/, level: 1 })
		).toBeVisible();
		await expect(
			page.getByRole('link', { name: 'Get Started' })
		).toBeVisible();
	});

	test('Get Started link sends anon visitor to /login', async ({ page }) => {
		// Click-through pin. A regression that wired the CTA to a
		// nonexistent route would surface as a hard 404 here.
		await page.goto('/');
		await page.getByRole('link', { name: 'Get Started' }).click();
		await page.waitForURL(/\/login/, { timeout: 10_000 });
	});

	test('top nav anchor links jump to in-page sections', async ({ page }) => {
		// The "Apps" + "Features" nav links use #apps / #features
		// fragment scrolls. Pin the targets exist so a refactor that
		// renames a section id surfaces here.
		await page.goto('/');
		await expect(page.locator('section#apps')).toBeVisible();
		await expect(page.locator('section#features')).toBeVisible();
		// Nav links carry the matching href.
		await expect(page.getByRole('link', { name: 'Apps' }).first()).toHaveAttribute(
			'href',
			'#apps'
		);
		await expect(page.getByRole('link', { name: 'Features' }).first()).toHaveAttribute(
			'href',
			'#features'
		);
	});

	test('Sign In nav link in the header routes to /login', async ({ page }) => {
		await page.goto('/');
		// The header has a 'Sign In' link with class .nav-signin —
		// disambiguate from the footer copy which uses the same text.
		await expect(page.locator('.nav-signin')).toHaveAttribute('href', '/login');
	});

	test('landing footer links all four legal + nav targets', async ({ page }) => {
		await page.goto('/');
		const footer = page.locator('footer.landing-footer');
		await expect(footer).toBeVisible();
		// Order pinned: Sign In / Apps / Features / Privacy / Terms / Cookies.
		await expect(footer.getByRole('link', { name: 'Sign In' })).toHaveAttribute(
			'href',
			'/login'
		);
		await expect(footer.getByRole('link', { name: 'Privacy' })).toHaveAttribute(
			'href',
			'/privacy'
		);
		await expect(footer.getByRole('link', { name: 'Terms' })).toHaveAttribute(
			'href',
			'/terms'
		);
		await expect(footer.getByRole('link', { name: 'Cookies' })).toHaveAttribute(
			'href',
			'/cookie-notice'
		);
	});

	test('document title + meta description match the SEO contract', async ({ page }) => {
		await page.goto('/');
		// Page title + meta description are the SERP snippet. Pin the
		// shape so a marketing copy change forces a deliberate test
		// update (rather than silently shipping wrong meta).
		const title = await page.title();
		expect(title.length).toBeGreaterThan(0);
		const desc = await page.locator('meta[name="description"]').getAttribute('content');
		expect((desc ?? '').length).toBeGreaterThan(0);
	});

	test('canonical, Open Graph, and Organization/WebSite JSON-LD are present', async ({
		page,
	}) => {
		await page.goto('/');

		// Canonical must be the apex root — the single home for the brand
		// so the www/apex CloudFront duplicate can't split ranking signal.
		const canonicalHref = await page
			.locator('link[rel="canonical"]')
			.getAttribute('href');
		expect(canonicalHref).toMatch(/^https?:\/\/[^/]+\/$/);

		expect(
			await page.locator('meta[property="og:title"]').getAttribute('content')
		).toBeTruthy();
		expect(await page.locator('meta[property="og:type"]').getAttribute('content')).toBe(
			'website'
		);
		expect(
			await page.locator('meta[property="og:image"]').getAttribute('content')
		).toBeTruthy();
		expect(await page.locator('meta[name="twitter:card"]').getAttribute('content')).toBe(
			'summary_large_image'
		);

		// The two site-wide nodes must both be emitted + parse as valid
		// JSON — the brand-query knowledge-panel / sitelinks signal.
		const ldBlocks = await page
			.locator('script[type="application/ld+json"]')
			.allTextContents();
		const types = ldBlocks.map((t) => JSON.parse(t)['@type']);
		expect(types).toContain('Organization');
		expect(types).toContain('WebSite');
	});

	test('first-paint hints: color-scheme meta + Supabase preconnect', async ({ page }) => {
		await page.goto('/');
		// color-scheme lets the UA paint the right default background
		// before CSS loads (CSP-safe flash mitigation).
		await expect(page.locator('meta[name="color-scheme"]')).toHaveAttribute(
			'content',
			'light dark'
		);
		// Preconnect to the Supabase origin every page hits on mount.
		expect(await page.locator('link[rel="preconnect"]').count()).toBeGreaterThan(0);
	});

	test('closing CTA section points anon users at /login', async ({ page }) => {
		await page.goto('/');
		// The "Ready to log your next run?" closing CTA has its own
		// "Sign in to continue" link. Anchor on the section's link.
		const cta = page.locator('section.closing-cta');
		await expect(cta).toBeVisible();
		await expect(cta.getByRole('link', { name: /Sign in to continue/ })).toHaveAttribute(
			'href',
			'/login'
		);
	});
});
