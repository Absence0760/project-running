import { expect, test } from '@playwright/test';

/**
 * Signup-confirmation landing on the wrong route (issue #363).
 *
 * The confirmation link only lands on /auth/callback when the hosted
 * Supabase project's Site URL + Redirect-URLs allow-list say so — a
 * dashboard setting no code can enforce. When it is wrong the link lands
 * on the Site URL instead (`/?code=<pkce>`), where detectSessionInUrl
 * still exchanges the code and mints a LIVE session while the
 * confirm_age_and_terms() retry and the GDPR Art 8 consent gate never
 * run, leaving age_confirmed_at / terms_accepted_at unset.
 *
 * The app now fails closed: any stray code lands back on /auth/callback,
 * which owns the consent path. Pin it, and pin that the routes which own
 * their own `code` are not hijacked.
 */

test.describe('Stray signup-confirmation landing', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a PKCE code on the app root is routed to /auth/callback', async ({ page }) => {
		await page.goto('/?code=e2e-stray-confirmation-code');

		await expect(page).toHaveURL(/\/auth\/callback\?code=e2e-stray-confirmation-code/, {
			timeout: 10_000,
		});
		// The callback owns the exchange; a bogus code fails it and shows
		// the recovery affordance rather than silently seating a session.
		await expect(page.getByRole('link', { name: /back to (sign in|login)/i })).toBeVisible();
	});

	test('the Strava OAuth return keeps its own code', async ({ page }) => {
		// /settings/integrations is auth-gated, so a logged-out visit
		// bounces to /login — the point is that it is NOT hijacked to
		// /auth/callback on the way.
		await page.goto('/settings/integrations?code=strava-code&scope=read&state=s');

		await expect(page).not.toHaveURL(/\/auth\/callback/);
	});

	test('an ordinary root visit is untouched', async ({ page }) => {
		await page.goto('/');

		await expect(page).not.toHaveURL(/\/auth\/callback/);
	});
});
