import { expect, test } from '@playwright/test';

/**
 * /compare — public marketing comparison vs Strava Free + Pro.
 *
 * Data source: apps/web/src/lib/compare_features.ts:
 *   - COMPARE_SECTIONS — array of CompareSection (title + rows).
 *   - COMPARE_HEADLINE — pricing strings used in the hero cards.
 *
 * Anon-readable; indexed for SEO. The page is the canonical "vs
 * Strava" landing for paid-search traffic. Regressions here break
 * the headline that converts visitors.
 */

test.describe('/compare — feature comparison vs Strava', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('document title + meta description match the SEO contract', async ({ page }) => {
		await page.goto('/compare');
		await expect(page).toHaveTitle(/How we compare to Strava/);
		const desc = await page.locator('meta[name="description"]').getAttribute('content');
		expect(desc ?? '').toMatch(/Strava Pro feature/i);
	});

	test('hero shows the three pricing cards with stable copy', async ({ page }) => {
		await page.goto('/compare');
		// Hero kicker + h1.
		await expect(page.getByRole('heading', { name: /Everything Strava Pro has/ })).toBeVisible();
		// Three named cards. Use the .price-label CSS class to disambiguate
		// from the column headers in the comparison tables further down
		// the page (which repeat the same strings 6× per table).
		await expect(page.locator('.price-card .price-label', { hasText: 'Run Onward' })).toBeVisible();
		await expect(page.locator('.price-card .price-label', { hasText: 'Strava Free' })).toBeVisible();
		await expect(page.locator('.price-card .price-label', { hasText: 'Strava Pro' })).toBeVisible();
		// Strava Pro pricing — pin the literal because if marketing
		// changes the format ($11.99 → £11.99 / per-year-only / etc.)
		// the SEO sub-headline shifts and a reviewer needs to verify.
		await expect(page.getByText(/11\.99/)).toBeVisible();
	});

	test('every section in COMPARE_SECTIONS renders as a <h2>', async ({ page }) => {
		await page.goto('/compare');
		// Pin each section title — these are the load-bearing copy
		// for the table; renaming one (e.g. 'Analysis' → 'Stats')
		// would silently rewrite the headline structure.
		for (const title of [
			'Recording + privacy',
			'Analysis',
			'Segments + leaderboards',
			'Training',
			'Discovery + social',
			'Integration + data ownership'
		]) {
			await expect(page.getByRole('heading', { name: title })).toBeVisible();
		}
	});

	test('each section renders a 4-column comparison table', async ({ page }) => {
		await page.goto('/compare');
		const tables = page.locator('table.cmp-table');
		// One table per section; COMPARE_SECTIONS has 6 entries today.
		await expect(tables).toHaveCount(6);
		// Headers on the first table: Feature / Run Onward / Strava Free / Strava Pro.
		const firstTable = tables.first();
		await expect(firstTable.locator('thead th').nth(0)).toHaveText('Feature');
		await expect(firstTable.locator('thead th').nth(1)).toHaveText('Run Onward');
		await expect(firstTable.locator('thead th').nth(2)).toHaveText('Strava Free');
		await expect(firstTable.locator('thead th').nth(3)).toHaveText('Strava Pro');
	});

	test('cells use Yes / No / Partial labels', async ({ page }) => {
		await page.goto('/compare');
		// `cellLabel` in the page converts 'yes' | 'no' | 'partial' to
		// the three labels. Verify at least one of each appears across
		// the matrix — a stricter equality would break on every data
		// edit.
		await expect(page.getByText('Yes', { exact: true }).first()).toBeVisible();
		await expect(page.getByText('No', { exact: true }).first()).toBeVisible();
		await expect(page.getByText('Partial', { exact: true }).first()).toBeVisible();
	});

	test('mentions Run Onward + Strava in the body for SEO', async ({ page }) => {
		await page.goto('/compare');
		const body = await page.content();
		expect(body).toMatch(/Run Onward/);
		expect(body).toMatch(/Strava/);
	});
});
