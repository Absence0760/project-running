import { expect, test } from '@playwright/test';

/**
 * Cookie-consent banner on every page until accepted/rejected.
 *
 * Spec is at apps/web/src/lib/components/CookieConsentBanner.svelte;
 * persistence is in apps/web/src/lib/consent.svelte.ts under the
 * localStorage key `cookie_consent` with shape:
 *   { choice: 'accepted' | 'rejected', timestamp: number }
 *
 * The banner only shows when the choice is null. Accept reloads
 * (so the hooks.client.ts Sentry init can re-evaluate the gate);
 * Reject keeps the page in place but stops the banner from showing
 * again.
 */

test.describe('Cookie consent banner', () => {
	// Start every test with no consent stored.
	test.use({ storageState: { cookies: [], origins: [] } });

	test('shows on first visit to the landing page', async ({ page }) => {
		await page.goto('/');
		await expect(page.getByRole('dialog', { name: /Cookies/ })).toBeVisible();
		await expect(page.getByRole('button', { name: 'Accept' })).toBeVisible();
		await expect(page.getByRole('button', { name: 'Reject' })).toBeVisible();
	});

	test('Reject hides the banner without reloading + persists the choice', async ({
		page
	}) => {
		await page.goto('/');
		const banner = page.getByRole('dialog', { name: /Cookies/ });
		await expect(banner).toBeVisible();

		await page.getByRole('button', { name: 'Reject' }).click();
		await expect(banner).toBeHidden();

		// localStorage persists across navigation but not reloads in
		// this same context — check via localStorage directly.
		const stored = await page.evaluate(() => localStorage.getItem('cookie_consent'));
		expect(stored).not.toBeNull();
		expect(JSON.parse(stored!).choice).toBe('rejected');

		// Navigate to another page — banner should NOT reappear.
		await page.goto('/privacy');
		await expect(page.getByRole('dialog', { name: /Cookies/ })).toHaveCount(0);
	});

	test('Accept stores the choice and the banner disappears', async ({ page }) => {
		await page.goto('/');
		// Accept triggers window.location.reload() — wait for the
		// resulting load to settle so the assertion is stable.
		const navPromise = page.waitForLoadState('load');
		await page.getByRole('button', { name: 'Accept' }).click();
		await navPromise;

		const stored = await page.evaluate(() => localStorage.getItem('cookie_consent'));
		expect(stored).not.toBeNull();
		expect(JSON.parse(stored!).choice).toBe('accepted');

		// Banner should be gone after the reload.
		await expect(page.getByRole('dialog', { name: /Cookies/ })).toHaveCount(0);
	});

	test('banner does NOT show when a choice is already stored', async ({ context, page }) => {
		// Seed the storage state with an accepted choice BEFORE the
		// first goto so the banner has no chance to flash.
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		await page.goto('/');
		await expect(page.getByRole('dialog', { name: /Cookies/ })).toHaveCount(0);

		// Same for a rejected choice — never show.
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'rejected', timestamp: Date.now() })
			);
		});
		await page.goto('/privacy');
		await expect(page.getByRole('dialog', { name: /Cookies/ })).toHaveCount(0);
	});

	test('banner links to /cookie-notice for the full disclosure', async ({ page }) => {
		await page.goto('/');
		const banner = page.getByRole('dialog', { name: /Cookies/ });
		const link = banner.getByRole('link', { name: 'Learn more' });
		await expect(link).toHaveAttribute('href', '/cookie-notice');
	});
});
