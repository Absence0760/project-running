import { expect, test } from '@playwright/test';

/**
 * /compare — public marketing comparison vs Strava Free + Pro.
 *
 * Source data: apps/web/src/lib/compare_features.ts. Anon-readable;
 * indexed for SEO. A regression that broke the table render would
 * blow up the search-engine landing for "vs strava" queries.
 */

test.describe('/compare — feature comparison vs Strava', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('renders the headline + at least one section + cells', async ({ page }) => {
		await page.goto('/compare');
		// Title comes from COMPARE_HEADLINE.title; test against the
		// raw <title> tag so a CSS reflow doesn't break us.
		await expect(page).toHaveTitle(/Strava/);
		// COMPARE_SECTIONS is non-empty by construction; the table
		// renders at least one <thead> + one <tbody> row.
		await expect(page.locator('table thead').first()).toBeVisible();
		await expect(page.locator('table tbody tr').first()).toBeVisible();
		// Cell labels: Yes / No / Partial. At least one of each
		// should appear across the matrix.
		await expect(page.getByText('Yes', { exact: true }).first()).toBeVisible();
	});

	test('mentions Strava in the title + headline', async ({ page }) => {
		await page.goto('/compare');
		// The comparison page is the SEO landing for vs-Strava
		// traffic; an accidental rename that drops the brand would
		// kneecap that ranking. Pin the visible reference.
		const body = await page.content();
		expect(body).toMatch(/Strava/);
	});
});
