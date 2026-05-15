import { expect, test } from '@playwright/test';

/**
 * /privacy, /terms, /cookie-notice — the legal route stubs.
 *
 * Both app stores reject submissions that don't have a stable
 * privacy-policy URL. These tests pin the existence + basic shape
 * so a refactor or accidental delete fails CI loudly.
 *
 * All three are public-by-design — anon viewers must reach them
 * without a login. The draft banner is intentionally loud so the
 * first reviewer of the live build asks "is this actually counsel-
 * approved?" — we test for it so a slip that hides the banner
 * before counsel review is caught.
 */

test.describe('Legal route stubs', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('/privacy renders with draft banner and a contact email', async ({ page }) => {
		await page.goto('/privacy');
		await expect(page.getByRole('heading', { name: 'Privacy Policy' })).toBeVisible();
		await expect(page.getByText(/Draft\./)).toBeVisible();
		await expect(
			page.getByRole('link', { name: /privacy@runonward\.com/ }).first()
		).toBeVisible();
		// Cross-link to /terms — important for the "consistent across docs" sanity test.
		await expect(page.getByRole('link', { name: 'Cookie Notice' }).first()).toHaveAttribute(
			'href',
			'/cookie-notice'
		);
	});

	test('/terms renders with draft banner and the subscription clause', async ({ page }) => {
		await page.goto('/terms');
		await expect(page.getByRole('heading', { name: 'Terms of Service' })).toBeVisible();
		await expect(page.getByText(/Draft\./)).toBeVisible();
		// Auto-renewal disclosure is required by Apple + Play + EU CRD;
		// a regression that drops it would fail the audit.
		await expect(page.getByText(/Auto-renewal\./)).toBeVisible();
		// 14-day right of withdrawal is the EU consumer-rights pillar.
		await expect(page.getByText(/14-day right of withdrawal/)).toBeVisible();
	});

	test('/cookie-notice lists the consent-gated trackers', async ({ page }) => {
		await page.goto('/cookie-notice');
		await expect(page.getByRole('heading', { name: 'Cookie Notice' })).toBeVisible();
		await expect(page.getByText(/Draft\./)).toBeVisible();
		// The two tables (strictly necessary / on-consent) are the
		// shape of the disclosure; pin them so a refactor doesn't
		// silently drop one tier.
		await expect(page.getByRole('heading', { name: '1. Strictly necessary' })).toBeVisible();
		await expect(page.getByRole('heading', { name: '2. Functional, on consent' })).toBeVisible();
		// Sentry must appear in the on-consent tier — that's the
		// load-on-accept gate behind the cookie banner.
		await expect(page.getByText('Sentry').first()).toBeVisible();
	});

	test('landing footer links all three legal pages', async ({ page }) => {
		await page.goto('/');
		const footer = page.locator('footer.landing-footer');
		await expect(footer).toBeVisible();
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
});
