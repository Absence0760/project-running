import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/upgrade — currency localisation of the Pro price.
 *
 * The price is built by apps/web/src/lib/format_price.ts using
 * Intl.NumberFormat against navigator.language. A user in en-US sees
 * $9.99; en-GB sees £9.99; de-DE sees 9,99 €. The format_price.test.ts
 * unit-test covers the helper in isolation; this spec proves the
 * helper is actually wired through to the rendered page so a
 * future refactor (e.g. someone reintroducing a hard-coded '$')
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
			await page.waitForLoadState('networkidle');
			await expect(page.locator('.price-amount')).toContainText('$9.99');
		} finally {
			await ctx.close();
		}
	});

	test('en-GB locale renders the £ price', async ({ browser }) => {
		const ctx = await browser.newContext({
			storageState: USER_A.storageStatePath,
			locale: 'en-GB'
		});
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/upgrade');
			await page.waitForLoadState('networkidle');
			await expect(page.locator('.price-amount')).toContainText('£9.99');
		} finally {
			await ctx.close();
		}
	});

	test('de-DE locale renders the € price + comma decimal', async ({ browser }) => {
		const ctx = await browser.newContext({
			storageState: USER_A.storageStatePath,
			locale: 'de-DE'
		});
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/upgrade');
			await page.waitForLoadState('networkidle');
			const text = await page.locator('.price-amount').textContent();
			// Both "9,99 €" and "€9,99" formats are valid Intl outputs;
			// Chromium emits "9,99 €" for de-DE today. Pin to the
			// substring that matters: comma decimal + euro sign.
			expect(text).toMatch(/9,99/);
			expect(text).toMatch(/€/);
		} finally {
			await ctx.close();
		}
	});

	test('CTA button also localises (not just the price block)', async ({ browser }) => {
		// The "Get Pro" button has `Get Pro — ${priceLabel}/mo`. If a
		// future refactor used the raw constant in the button while
		// using the helper in the price block, the price block test
		// would still pass and the button would silently drift back to
		// USD. Pin both.
		const ctx = await browser.newContext({
			storageState: USER_A.storageStatePath,
			locale: 'en-GB'
		});
		const page = await ctx.newPage();
		try {
			await page.goto('/settings/upgrade');
			await page.waitForLoadState('networkidle');
			await expect(
				page.getByRole('button', { name: /Get Pro — £9\.99\/mo/ })
			).toBeVisible();
		} finally {
			await ctx.close();
		}
	});
});
