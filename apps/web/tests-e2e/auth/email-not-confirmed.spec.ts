import { expect, test } from '@playwright/test';

/**
 * /login — an unconfirmed-email sign-in must surface a specific,
 * actionable error (not the generic wrong-password banner) plus a
 * resend-confirmation affordance. Issue #486.
 *
 * Local Supabase runs with enable_confirmations = false
 * (apps/backend/supabase/config.toml), so a real GoTrue never returns
 * the unconfirmed-email error here — the test intercepts the token
 * endpoint and returns the error shape GoTrue sends in production. The
 * classification + copy is the contract under test, not the network.
 */

test.describe('/login unconfirmed email', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('surfaces the confirm-your-email message + resend button, not a generic error', async ({
		page
	}) => {
		// Pre-accept the cookie banner before the module reads localStorage
		// (same reason as the signIn helper) so it can't intercept clicks.
		await page.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});

		// Stand in for GoTrue's password-grant response for an account
		// that exists but hasn't confirmed its email. Both the dedicated
		// `email_not_confirmed` code and the descriptive message are set
		// so the classifier resolves it however supabase-js exposes it.
		await page.route('**/auth/v1/token?grant_type=password', async (route) => {
			await route.fulfill({
				status: 400,
				contentType: 'application/json',
				body: JSON.stringify({
					code: 'email_not_confirmed',
					error_code: 'email_not_confirmed',
					msg: 'Email not confirmed',
					error_description: 'Email not confirmed'
				})
			});
		});

		await page.goto('/login');
		await page.waitForLoadState('networkidle');

		await page.locator('input[type="email"]').fill('unconfirmed@test.local');
		await page.locator('input[type="password"]').fill('testtest');
		await page.locator('form button[type="submit"]').click();

		const banner = page.locator('.error[role="alert"]');
		await expect(banner).toBeVisible({ timeout: 5_000 });
		// The specific, actionable copy — not the generic sign-in failure.
		await expect(banner).toContainText(/confirm your email/i);
		// The resend-confirmation affordance is offered from the banner.
		await expect(
			banner.getByRole('button', { name: /resend confirmation email/i })
		).toBeVisible();

		// Still on /login (failed sign-in never navigates away).
		await expect(page).toHaveURL(/\/login/);
	});
});
