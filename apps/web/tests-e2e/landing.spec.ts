import { expect, test } from '@playwright/test';

/**
 * `/` — anon landing page.
 *
 * Authenticated visitors are auto-redirected to /dashboard via an
 * $effect in the page component; the marketing hero only renders for
 * unauthenticated visitors. Tests live here in isolation rather than
 * mixed with the auth flow because this is the only page anon users
 * see by default (everything else either redirects to /login or is
 * gated by `isPublic` in the layout's auth guard).
 */

test.describe('/ (landing)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor sees hero + Get Started CTA', async ({ page }) => {
		// The h1 is split across <br/>s; the accessible name is the
		// concatenated text "Plan routes. Track runs. Analyse
		// everything." Match by the leading phrase.
		await page.goto('/');
		await page.waitForLoadState('networkidle');

		await expect(
			page.getByRole('heading', { name: /Plan routes/, level: 1 })
		).toBeVisible();
		await expect(
			page.getByRole('link', { name: 'Get Started' })
		).toBeVisible();
	});

	test('Get Started link sends anon visitor to /login', async ({ page }) => {
		// Click-through pin. A regression that wired the CTA to a
		// nonexistent route would surface as a hard 404 here.
		await page.goto('/');
		await page.waitForLoadState('networkidle');
		await page.getByRole('link', { name: 'Get Started' }).click();
		await page.waitForURL(/\/login/, { timeout: 10_000 });
	});
});
