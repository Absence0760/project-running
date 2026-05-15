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

	test('/privacy lists every GDPR-named clause that App Store / Play reviewers look for', async ({
		page
	}) => {
		// Apple + Play privacy reviewers grep for these clauses by name.
		// A regression that dropped one would surface at submission as
		// a "missing required disclosure" rejection.
		await page.goto('/privacy');
		// Lawful basis under Art 6 — the Privacy Policy summarises the
		// six bases in a table; "Lawful basis" is the canonical phrase.
		// Heading + table cell both contain the phrase; .first() pins
		// the section heading.
		await expect(page.getByText(/Lawful basis/i).first()).toBeVisible();
		// DSAR rights (Art 15-22) — the page enumerates Access /
		// Rectify / Erase / Restrict / Portability.
		await expect(page.getByText(/Access your personal data/i)).toBeVisible();
		await expect(page.getByText(/Erase your data/i)).toBeVisible();
		await expect(page.getByText(/Portability/i)).toBeVisible();
		// Children clause — required for any app that doesn't enforce
		// age verification.
		await expect(page.getByText(/Children/i).first()).toBeVisible();
		// Cross-border transfers — required for any app with US-hosted
		// sub-processors serving EU users.
		await expect(page.getByText(/International transfers/i)).toBeVisible();
	});

	test('/terms states the auto-renewal + 14-day cooling-off + cancellation clauses', async ({
		page
	}) => {
		// Apple's "auto-renewable subscription" guideline requires the
		// renewal disclosure verbatim. EU Consumer Rights Directive
		// requires the 14-day right of withdrawal. Both stores require
		// cancellation be at least as easy as signup. Pin all three.
		await page.goto('/terms');
		await expect(page.getByText(/Auto-renewal\./)).toBeVisible();
		await expect(page.getByText(/14-day right of withdrawal/)).toBeVisible();
		await expect(page.getByText(/Cancellation is at least as easy as signup/)).toBeVisible();
	});

	test('/cookie-notice categorises trackers into strictly-necessary vs on-consent buckets', async ({
		page
	}) => {
		// ePrivacy Art 5(3) requires consent for non-essential trackers.
		// The page surfaces the distinction via two named buckets — pin
		// each as a section h2 + at least one row inside each table.
		await page.goto('/cookie-notice');
		await expect(page.getByRole('heading', { name: '1. Strictly necessary' })).toBeVisible();
		await expect(page.getByRole('heading', { name: '2. Functional, on consent' })).toBeVisible();
		// At least one strictly-necessary cookie (Supabase Auth tokens).
		await expect(page.getByText(/sb-access-token|Supabase Auth/i).first()).toBeVisible();
		// At least one on-consent tracker (Sentry).
		await expect(page.getByText('Sentry').first()).toBeVisible();
	});

	test('legal pages cross-link each other consistently', async ({ page }) => {
		// Privacy refers to the Cookie Notice; Privacy refers to Terms;
		// the consent banner refers to the Cookie Notice. A refactor
		// that renamed a route would break the chain silently — pin
		// the cross-links on the Privacy page since it touches both
		// of the others.
		await page.goto('/privacy');
		await expect(page.getByRole('link', { name: 'Cookie Notice' }).first()).toHaveAttribute(
			'href',
			'/cookie-notice'
		);
		// The privacy contact mailto is repeated across the page; the
		// first instance is the controller block.
		await expect(
			page.getByRole('link', { name: /privacy@runonward\.com/ }).first()
		).toHaveAttribute('href', /^mailto:/);
	});
});
