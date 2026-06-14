import { expect, test } from '@playwright/test';

import { COMPARE_HEADLINE, COMPARE_SECTIONS } from '../../src/lib/settings/compare_features';

/**
 * /compare depth coverage — gaps the page.spec.ts smoke suite leaves
 * open. /compare is the anon "vs Strava" marketing landing; its data
 * source is compare_features.ts (COMPARE_SECTIONS + COMPARE_HEADLINE).
 *
 * page.spec.ts asserts headers / 6 tables / coloured cells / footer /
 * external-link rel / a single mobile-collapse check. This file pins
 * the parts that actually carry the conversion + a11y contract:
 *
 *   - the exact pricing strings come from COMPARE_HEADLINE (so a data
 *     edit that drops "Free" or the Strava Pro $/mo reference fails
 *     loudly here, not silently in prod).
 *   - every data cell exposes a screen-reader Yes/No/Partial label (the
 *     icon glyph alone is invisible to assistive tech) — derived from
 *     the real section data, not a hand-typed count.
 *   - the "ours" (Threkir) column is highlighted on every row.
 *   - the page works with NO cookie-consent recorded (it mounts no
 *     map / third-party SDK, unlike /live), so it must not gate behind
 *     a consent veil.
 *   - the mobile-collapse data-col labels match the real provider names.
 */

const TOTAL_ROWS = COMPARE_SECTIONS.reduce((n, s) => n + s.rows.length, 0);

test.describe('/compare — pricing + a11y depth (anon, no consent)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	// Deliberately NO consent beforeEach — the page must render fully
	// without one because it loads no IP-logging third party.

	test('hero pricing strings come verbatim from COMPARE_HEADLINE', async ({ page }) => {
		await page.goto('/compare');
		// The us card reads the literal usPrice ("Free").
		const usCard = page.locator('.price-card.us');
		await expect(usCard.locator('.price')).toHaveText(COMPARE_HEADLINE.usPrice);
		// Strava Free + Pro cards read their headline strings — pin the
		// full Pro string so a region/currency edit is a deliberate
		// visible change, not silent drift.
		await expect(page.getByText(COMPARE_HEADLINE.stravaFreePrice, { exact: true })).toBeVisible();
		await expect(page.getByText(COMPARE_HEADLINE.stravaProPrice, { exact: true })).toBeVisible();
	});

	test('renders no consent veil — the page works before any banner choice', async ({ page }) => {
		await page.goto('/compare');
		// Unlike /live the compare page mounts no MapLibre map, so there
		// must be no "Load map" gate and the tables must be immediately
		// visible to an anon visitor who never answered the banner.
		await expect(page.getByRole('button', { name: /Load map/i })).toHaveCount(0);
		await expect(page.locator('table.cmp-table').first()).toBeVisible();
	});

	test('every data cell carries a screen-reader Yes/No/Partial label', async ({ page }) => {
		await page.goto('/compare');
		// 3 provider columns × every feature row. Each .cell has a
		// .sr-only label so the meaning isn't icon-only for assistive
		// tech. Count is derived from the real data, so adding a feature
		// row keeps the test honest without editing a literal.
		const srLabels = page.locator('table.cmp-table td.cell .sr-only');
		await expect(srLabels).toHaveCount(TOTAL_ROWS * 3);
		// Each label is one of the three known strings.
		const texts = await srLabels.allInnerTexts();
		for (const t of texts) {
			expect(['Yes', 'No', 'Partial']).toContain(t.trim());
		}
	});

	test('the Threkir (ours) column is highlighted on every row', async ({ page }) => {
		await page.goto('/compare');
		// One `.cell.ours` per feature row across all sections — the
		// visual "this is us" emphasis. A regression that dropped the
		// `ours` class would flatten the comparison's whole point.
		const ours = page.locator('table.cmp-table td.cell.ours');
		await expect(ours).toHaveCount(TOTAL_ROWS);
		const bg = await ours.first().evaluate((el) => getComputedStyle(el).backgroundColor);
		// Highlight is a non-transparent tint.
		expect(bg).not.toBe('rgba(0, 0, 0, 0)');
		expect(bg).not.toBe('transparent');
	});

	test('a known feature row resolves the right support level per provider', async ({ page }) => {
		await page.goto('/compare');
		// Drive a specific data assertion off the source so a cell that
		// silently flips (e.g. our "yes" becoming "no") is caught. Find
		// the first row that is yes/no/partial across the three providers
		// distinctly so the icons are unambiguous.
		const row = COMPARE_SECTIONS.flatMap((s) => s.rows).find(
			(r) => r.ours === 'yes' && r.stravaFree === 'no'
		);
		expect(row, 'expected a yes/no row to exist in compare data').toBeTruthy();
		if (!row) return;
		const tr = page.locator('table.cmp-table tr', { hasText: row.name }).first();
		await expect(tr.locator('td.cell.ours .sr-only')).toHaveText('Yes');
		await expect(tr.locator('td[data-col="Strava Free"] .sr-only')).toHaveText('No');
	});

	test('mobile collapse labels every cell with its real provider name', async ({ page }) => {
		await page.setViewportSize({ width: 600, height: 900 });
		await page.goto('/compare');
		const firstRow = page.locator('table.cmp-table tbody tr').first();
		// Each collapsed cell injects its column name via the data-col
		// ::before label — pin all three real provider names appear.
		for (const col of ['Threkir', 'Strava Free', 'Strava Pro']) {
			await expect(firstRow.locator(`td.cell[data-col="${col}"]`)).toBeVisible();
		}
		// And the mobile per-cell text label (Yes/No/Partial) shows, not
		// just the icon.
		await expect(firstRow.locator('.cell-mobile-label').first()).toBeVisible();
	});
});
