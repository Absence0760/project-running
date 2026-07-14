import { expect, test } from '@playwright/test';

/**
 * /privacy, /terms, /cookie-notice, /health-data-notice — the legal pages.
 *
 * Both app stores reject submissions that don't have a stable
 * privacy-policy URL, and Apple + Play privacy reviewers grep for
 * specific clauses by name — these tests pin the existence + shape so
 * a refactor or accidental delete fails CI loudly.
 *
 * All four are public-by-design — anon viewers must reach them without
 * a login. The pages are complete legal text (decisions §243); the only
 * permitted "unfinished" surface is the operator-facts pending banner
 * driven by src/lib/legal/operator.ts — never a TODO placeholder or a
 * "Draft" banner. If a fact is filled in operator.ts, the pending copy
 * for it must disappear without any other edit.
 */

const PAGES = [
	{ path: '/privacy', title: 'Privacy Policy' },
	{ path: '/terms', title: 'Terms of Service' },
	{ path: '/cookie-notice', title: 'Cookie Notice' },
	{ path: '/health-data-notice', title: 'Consumer Health Data Privacy Policy' },
];

test.describe('Legal pages', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	for (const { path, title } of PAGES) {
		test(`${path} renders anonymously with no draft markers`, async ({ page }) => {
			await page.goto(path);
			await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible();
			await expect(page.getByText(/^Last updated: \d{4}-\d{2}-\d{2}$/)).toBeVisible();

			const body = await page.locator('.legal-page').innerText();
			expect(body).not.toMatch(/TODO/);
			expect(body).not.toMatch(/\bDraft\b\./);
			expect(body).not.toMatch(/published as a placeholder/i);
			expect(body).not.toMatch(/to be confirmed|not yet operative|working scaffold/i);
		});
	}

	test('/privacy lists every GDPR-named clause that App Store / Play reviewers look for', async ({
		page
	}) => {
		// Apple + Play privacy reviewers grep for these clauses by name.
		// A regression that dropped one would surface at submission as
		// a "missing required disclosure" rejection.
		await page.goto('/privacy');
		await expect(page.getByText(/Lawful basis/i).first()).toBeVisible();
		await expect(page.getByText(/Access your personal data/i)).toBeVisible();
		await expect(page.getByText(/Erase your data/i)).toBeVisible();
		await expect(page.getByText(/Portability/i)).toBeVisible();
		await expect(page.getByText(/Children/i).first()).toBeVisible();
		await expect(page.getByText(/International transfers/i)).toBeVisible();
		await expect(
			page.getByRole('link', { name: /privacy@threkir\.com/ }).first()
		).toHaveAttribute('href', /^mailto:/);
	});

	test('/privacy states the 48-hour live-ping retention, not the stale 24h figure', async ({
		page
	}) => {
		await page.goto('/privacy');
		const body = await page.locator('.legal-page').innerText();
		expect(body).toContain('Live spectator pings');
		expect(body).toMatch(/Live spectator pings[^\n]*48 hours/);
	});

	test('/terms states the subscription pillars + marketplace + DMCA clauses', async ({
		page
	}) => {
		// Apple's auto-renewable-subscription guideline requires the
		// renewal disclosure; the EU Consumer Rights Directive requires
		// the 14-day right of withdrawal; both stores require cancelling
		// be at least as easy as signup. The marketplace + DMCA sections
		// back the Stripe Connect rail and the §512 safe harbor.
		await page.goto('/terms');
		await expect(page.getByText(/Auto-renewal\./)).toBeVisible();
		await expect(page.getByText(/14-day right of withdrawal/)).toBeVisible();
		await expect(page.getByText(/Cancellation is at least as easy as signup/)).toBeVisible();
		const body = await page.locator('.legal-page').innerText();
		expect(body).toContain('merchant of record');
		expect(body).toContain('dmca@threkir.com');
	});

	test('/cookie-notice categorises trackers into necessary vs consent-gated buckets', async ({
		page
	}) => {
		// ePrivacy Art 5(3) requires consent for non-essential trackers.
		await page.goto('/cookie-notice');
		await expect(page.getByRole('heading', { name: '1. Strictly necessary' })).toBeVisible();
		await expect(
			page.getByRole('heading', { name: '2. Preferences + on-device caches' })
		).toBeVisible();
		await expect(page.getByRole('heading', { name: '3. Consent-gated' })).toBeVisible();
		// At least one strictly-necessary cookie (Supabase Auth tokens)
		// and one consent-gated tracker (Sentry).
		await expect(page.getByText(/sb-access-token/i).first()).toBeVisible();
		await expect(page.getByText('Sentry').first()).toBeVisible();
	});

	test('/cookie-notice discloses GPC as honoured', async ({ page }) => {
		await page.goto('/cookie-notice');
		await expect(page.getByText('Global Privacy Control (GPC) is honoured.')).toBeVisible();
		await expect(page.getByTestId('manage-cookie-preferences')).toBeVisible();
	});

	test('legal pages cross-link each other consistently', async ({ page }) => {
		await page.goto('/privacy');
		await expect(page.getByRole('link', { name: 'Cookie Notice' }).first()).toHaveAttribute(
			'href',
			'/cookie-notice'
		);
		await page
			.getByRole('link', { name: 'Consumer Health Data Privacy Policy' })
			.click();
		await expect(
			page.getByRole('heading', { level: 1, name: 'Consumer Health Data Privacy Policy' })
		).toBeVisible();
	});

	test('landing footer links all four legal pages', async ({ page }) => {
		await page.goto('/');
		const footer = page.locator('footer.landing-footer');
		await expect(footer).toBeVisible();
		await expect(footer.getByRole('link', { name: 'Privacy' })).toHaveAttribute(
			'href',
			'/privacy'
		);
		await expect(footer.getByRole('link', { name: 'Terms' })).toHaveAttribute('href', '/terms');
		await expect(footer.getByRole('link', { name: 'Cookies' })).toHaveAttribute(
			'href',
			'/cookie-notice'
		);
		await expect(footer.getByRole('link', { name: 'Health data' })).toHaveAttribute(
			'href',
			'/health-data-notice'
		);
	});
});
