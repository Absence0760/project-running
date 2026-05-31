import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Behavioural proof for audit/i18n-readiness (2026-05-30) Critical W-10:
 * the app shell was migrated from physical-direction CSS to inline-logical
 * properties so it mirrors under `dir="rtl"`. The source-level completeness
 * guard lives in src/lib/rtl_css_guards.test.ts; this spec proves the
 * shell frame actually flips when the document direction is RTL.
 *
 * We don't ship an RTL locale yet (that rides with the i18n framework, W-1),
 * so the test sets document.dir at runtime — the CSS logical properties
 * respond to whatever direction the document declares.
 */
test.describe('RTL layout', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the app shell mirrors when dir=rtl', async ({ page }) => {
		await page.goto('/dashboard');

		const sidebar = page.locator('nav.sidebar');
		const main = page.locator('main.main-content');
		await expect(sidebar).toBeVisible();

		const sidesOf = (loc: typeof sidebar) =>
			loc.evaluate((el) => {
				const s = getComputedStyle(el);
				return { left: s.left, right: s.right };
			});
		const marginsOf = (loc: typeof main) =>
			loc.evaluate((el) => {
				const s = getComputedStyle(el);
				return { left: s.marginLeft, right: s.marginRight };
			});

		// Kill transitions so we assert the settled layout, not a frame
		// mid-animation (.main-content transitions margin-inline-start, so
		// the margin "slides" across when dir flips).
		await page.addStyleTag({ content: '*, *::before, *::after { transition: none !important; animation: none !important; }' });

		// LTR baseline: sidebar pinned left, content margin on the left.
		const sidebarLtr = await sidesOf(sidebar);
		const marginLtr = await marginsOf(main);
		expect(sidebarLtr.left).toBe('0px');
		expect(marginLtr.right).toBe('0px');
		const ltrMarginLeft = parseFloat(marginLtr.left);
		expect(ltrMarginLeft).toBeGreaterThan(0); // offset by the sidebar width

		// Flip the document to RTL — logical properties must mirror.
		await page.evaluate(() => document.documentElement.setAttribute('dir', 'rtl'));

		const sidebarRtl = await sidesOf(sidebar);
		const marginRtl = await marginsOf(main);
		// Sidebar now pinned to the right edge.
		expect(sidebarRtl.right).toBe('0px');
		expect(sidebarRtl.left).not.toBe('0px');
		// Content offset is now on the right, by the same sidebar width.
		expect(marginRtl.left).toBe('0px');
		expect(parseFloat(marginRtl.right)).toBeCloseTo(ltrMarginLeft, 0);
	});
});
