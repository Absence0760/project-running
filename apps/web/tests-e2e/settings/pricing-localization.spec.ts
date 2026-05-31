import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/upgrade — currency localisation of the Pro price.
 *
 * The price is built by apps/web/src/lib/format/format_price.ts using
 * Intl.NumberFormat against navigator.language. The amount is a raw,
 * unconverted USD figure: locale drives the NUMBER format (comma vs dot
 * decimal, symbol placement) but the currency STAYS USD. Rendering a
 * localized symbol (£ / €) over a USD charge would misrepresent what the
 * user is billed — an EU Omnibus / consumer-protection problem
 * (audit-findings 2026-05-30 Medium [regional], commit 9805a5ed).
 *
 * So: en-US sees `$9.99`; en-GB sees `US$9.99`; de-DE sees `9,99 $`.
 * The format_price.test.ts unit-test covers the helper in isolation;
 * this spec proves the helper is actually wired through to the rendered
 * page — so a future refactor that hard-codes a `$` constant, OR one
 * that reintroduces a misleading localized symbol over the USD amount,
 * fails CI.
 *
 * Each browser context overrides `locale` at the Playwright level,
 * which sets the `Accept-Language` header AND the `navigator.language`
 * value at runtime — both of which are what format_price.ts reads.
 */

test.describe('Pro price — currency localisation', () => {
	test('en-US locale renders the $ price', async ({ browser }) => {
		const ctx = await browser.newContext({
			storageState: USER_A.storageStatePath,
			locale: 'en-US'
		});
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/upgrade');
			await expect(page.locator('.tier-pro .price-amount')).toContainText('$9.99');
		} finally {
			await ctx.close();
		}
	});

	test('en-GB locale keeps USD (US$), not a fake £', async ({ browser }) => {
		const ctx = await browser.newContext({
			storageState: USER_A.storageStatePath,
			locale: 'en-GB'
		});
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/upgrade');
			const text = await page.locator('.tier-pro .price-amount').textContent();
			expect(text).toContain('9.99');
			// The charge is in USD; the page must NOT imply a GBP price.
			expect(text).not.toContain('£');
			expect(text).toMatch(/US\$/);
		} finally {
			await ctx.close();
		}
	});

	test('de-DE locale uses comma decimal but keeps USD, not a fake €', async ({ browser }) => {
		const ctx = await browser.newContext({
			storageState: USER_A.storageStatePath,
			locale: 'de-DE'
		});
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/upgrade');
			const text = await page.locator('.tier-pro .price-amount').textContent();
			// Locale drives the number format (comma decimal); currency
			// stays USD — no euro symbol over an unconverted USD amount.
			expect(text).toMatch(/9,99/);
			expect(text).not.toContain('€');
			expect(text).toContain('$');
		} finally {
			await ctx.close();
		}
	});

	test('CTA button localises the same way as the price block', async ({ browser }) => {
		// The "Get Pro" button has `Get Pro — ${priceLabel}/mo`. If a
		// future refactor used a raw constant in the button while using
		// the helper in the price block, the price block test would still
		// pass and the button would silently drift. Pin both to the same
		// USD-with-locale-formatting output.
		const ctx = await browser.newContext({
			storageState: USER_A.storageStatePath,
			locale: 'en-GB'
		});
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/upgrade');
			await expect(
				page.getByRole('button', { name: /Get Pro — US\$9\.99\/mo/ })
			).toBeVisible();
		} finally {
			await ctx.close();
		}
	});
});
