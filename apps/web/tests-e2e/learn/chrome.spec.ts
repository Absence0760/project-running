import { expect, test } from '@playwright/test';

/**
 * /learn shares the landing page's public chrome (issue #212).
 *
 * The hub, category, and guide pages render the same PublicHeader
 * (wordmark + Apps / Features / Learn / Sign In) and PublicFooter
 * (legal links) the landing page uses, so the marketing surface keeps
 * one identity when a visitor clicks "Learn" from the homepage. Pin
 * the shared pieces on all three learn routes so a regression back to
 * a hand-rolled header surfaces here.
 */

const LEARN_PAGES = ['/learn', '/learn/category/getting-started', '/learn/couch-to-5k'];

test.describe('/learn shared public chrome', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	for (const path of LEARN_PAGES) {
		test(`${path} renders the landing header (wordmark + nav links)`, async ({ page }) => {
			await page.goto(path);

			const nav = page.locator('nav.landing-nav');
			await expect(nav).toBeVisible();

			// Wordmark image logo linking home — not the old plain-text
			// "Threkir" learn-logo.
			const logo = nav.locator('a.landing-logo');
			await expect(logo).toHaveAttribute('href', '/');
			await expect(logo.locator('img[alt="Threkir"]').first()).toBeVisible();

			// Same nav links as the landing page, root-anchored so the
			// fragment targets resolve from /learn.
			await expect(nav.getByRole('link', { name: 'Apps' })).toHaveAttribute('href', '/#apps');
			await expect(nav.getByRole('link', { name: 'Features' })).toHaveAttribute(
				'href',
				'/#features'
			);
			await expect(nav.getByRole('link', { name: 'Learn' })).toHaveAttribute('href', '/learn');
			await expect(nav.locator('.nav-signin')).toHaveAttribute('href', '/login');
		});

		test(`${path} renders the landing footer with the legal links`, async ({ page }) => {
			await page.goto(path);

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
			await expect(footer.getByRole('link', { name: 'Health data' })).toHaveAttribute(
				'href',
				'/health-data-notice'
			);
		});
	}

	test('header Sign In routes to /login from /learn', async ({ page }) => {
		await page.goto('/learn');
		await page.locator('nav.landing-nav .nav-signin').click();
		await page.waitForURL(/\/login/, { timeout: 10_000 });
	});
});
