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

	test.beforeEach(async ({ page }) => {
		await page.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
	});

	test('document title + meta description match the SEO contract', async ({ page }) => {
		await page.goto('/compare');
		await expect(page).toHaveTitle(/How we compare to Strava/);
		const desc = await page.locator('meta[name="description"]').getAttribute('content');
		expect(desc ?? '').toMatch(/Strava Pro feature/i);
	});

	test('hero shows the three pricing cards with stable copy', async ({ page }) => {
		await page.goto('/compare');
		await expect(page.getByRole('heading', { name: /Everything Strava Pro has/ })).toBeVisible();
		await expect(
			page.locator('.price-card .price-label', { hasText: 'Run Onward' }),
		).toBeVisible();
		await expect(
			page.locator('.price-card .price-label', { hasText: 'Strava Free' }),
		).toBeVisible();
		await expect(
			page.locator('.price-card .price-label', { hasText: 'Strava Pro' }),
		).toBeVisible();
		await expect(page.getByText(/11\.99/)).toBeVisible();
	});

	test('every section in COMPARE_SECTIONS renders as a <h2>', async ({ page }) => {
		await page.goto('/compare');
		for (const title of [
			'Recording + privacy',
			'Analysis',
			'Segments + leaderboards',
			'Training',
			'Discovery + social',
			'Integration + data ownership',
		]) {
			await expect(page.getByRole('heading', { name: title })).toBeVisible();
		}
	});

	test('each section renders a 4-column comparison table', async ({ page }) => {
		await page.goto('/compare');
		const tables = page.locator('table.cmp-table');
		await expect(tables).toHaveCount(6);
		const firstTable = tables.first();
		await expect(firstTable.locator('thead th').nth(0)).toHaveText('Feature');
		await expect(firstTable.locator('thead th').nth(1)).toHaveText('Run Onward');
		await expect(firstTable.locator('thead th').nth(2)).toHaveText('Strava Free');
		await expect(firstTable.locator('thead th').nth(3)).toHaveText('Strava Pro');
	});

	test('cells use Yes / No / Partial labels', async ({ page }) => {
		await page.goto('/compare');
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

	test('Yes / No / Partial cells use distinct visible colors', async ({ page }) => {
		await page.goto('/compare');
		const firstTable = page.locator('table.cmp-table').first();
		const yes = firstTable.locator('td.cell.cell-yes').first();
		const no = firstTable.locator('td.cell.cell-no').first();
		const partial = page.locator('td.cell.cell-partial').first();

		await expect(yes).toBeVisible();
		await expect(no).toBeVisible();
		await expect(partial).toBeVisible();

		const yesColor = await yes.evaluate((el) => getComputedStyle(el).color);
		const noColor = await no.evaluate((el) => getComputedStyle(el).color);
		const partialColor = await partial.evaluate((el) => getComputedStyle(el).color);

		expect(yesColor).not.toEqual(noColor);
		expect(yesColor).not.toEqual(partialColor);
		expect(partialColor).not.toEqual(noColor);
	});

	test('internal feature links in the footer point at /coach + /plans + /clubs', async ({
		page,
	}) => {
		await page.goto('/compare');
		const footer = page.locator('.cmp-footer');
		await expect(footer.locator('a[href="/coach"]', { hasText: /Coach/ })).toBeVisible();
		await expect(footer.locator('a[href="/plans"]', { hasText: /plans/i })).toBeVisible();
		await expect(footer.locator('a[href="/clubs"]', { hasText: /Clubs/ })).toBeVisible();
	});

	test('external Strava link uses noopener noreferrer', async ({ page }) => {
		await page.goto('/compare');
		const stravaLink = page
			.locator('.cmp-footer a[href*="strava.com"]')
			.first();
		await expect(stravaLink).toBeVisible();
		const rel = await stravaLink.getAttribute('rel');
		expect(rel ?? '').toContain('noopener');
		expect(rel ?? '').toContain('noreferrer');
		const target = await stravaLink.getAttribute('target');
		expect(target).toBe('_blank');
	});

	test('mobile viewport collapses the 4-col table into a stacked layout', async ({ page }) => {
		await page.setViewportSize({ width: 600, height: 900 });
		await page.goto('/compare');

		const firstTable = page.locator('table.cmp-table').first();
		await expect(firstTable).toBeVisible();

		// On mobile, thead is hidden and tbody td.cell becomes block-with-label.
		const thead = firstTable.locator('thead');
		const theadDisplay = await thead.evaluate((el) => getComputedStyle(el).display);
		expect(theadDisplay).toBe('none');

		const firstCell = firstTable.locator('td.cell').first();
		await expect(firstCell).toBeVisible();
		const cellDisplay = await firstCell.evaluate((el) => getComputedStyle(el).display);
		expect(cellDisplay).toBe('flex');

		// The per-cell label is now a real text node, not just an icon.
		await expect(firstCell.locator('.cell-mobile-label').first()).toBeVisible();
	});
});
