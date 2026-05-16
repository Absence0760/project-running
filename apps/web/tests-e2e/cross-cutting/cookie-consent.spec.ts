import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

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

	test('banner does NOT block centered primary CTAs (regression pin)', async ({
		browser
	}) => {
		// Earlier the banner spanned a 42rem strip at bottom-centre of
		// the viewport. It silently intercepted pointer events on
		// whatever pixels it covered — including the "Save run" button
		// on /runs/new and the floating bulk-action bar on /runs. The
		// repro: brand-new visitor enters /runs/new, fills the form,
		// clicks Save → click never lands → 30s timeout. The fix is the
		// banner's geometry (compact bottom-RIGHT corner card, not a
		// centered full-width strip). Pin the invariant by signing in
		// fresh (no consent in localStorage) and asserting the
		// /runs/new Save button is clickable while the banner is on
		// screen.
		const ctx = await browser.newContext({
			storageState: 'tests-e2e/.auth/user-a.json'
		});
		const page = await ctx.newPage();
		let plantedId: string | null = null;
		try {
			await page.goto('/runs/new');
			// Banner is visible.
			await expect(page.getByRole('dialog', { name: /Cookies/ }))
				.toBeVisible({ timeout: 10_000 });
			// Save run button is also visible AND clickable. If the
			// banner blocked pointer events, the click would never
			// resolve.
			await page.getByRole('button', { name: 'Walk', exact: true }).click();
			const numberInputs = page.locator('input[type="number"]');
			await numberInputs.nth(0).fill('1.0');
			await numberInputs.nth(1).fill('5');
			const saveBtn = page.getByRole('button', { name: 'Save run' });
			await expect(saveBtn).toBeVisible();
			// Click resolves within the assertion timeout — used to
			// hang 30s waiting for the banner to release the click.
			await saveBtn.click({ timeout: 5_000 });
			// The form's onCreated handler navigates to /runs/[id].
			// Wait for the URL change as proof the click landed.
			await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 10_000 });
			plantedId = page.url().match(/\/runs\/([0-9a-f-]+)$/)?.[1] ?? null;
		} finally {
			// Sweep the planted run so the seed's "exactly one walk"
			// invariant (relied on by runs/list.spec.ts) stays intact.
			if (plantedId) {
				const admin = getAdminClient();
				await admin.from('runs').delete().eq('id', plantedId);
			}
			await ctx.close();
		}
	});
});
