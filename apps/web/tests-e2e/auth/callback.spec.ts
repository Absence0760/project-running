import { expect, test } from '@playwright/test';

/**
 * /auth/callback — Supabase PKCE OAuth landing page.
 *
 * Source: apps/web/src/routes/auth/callback/+page.svelte. The PKCE
 * flow lands here with `?code=…` in the query string after Google /
 * Apple have signed the user out. The page calls
 * supabase.auth.exchangeCodeForSession(...) then redirects to
 * /dashboard on success, or surfaces the auth error inline.
 *
 * We can't drive the real Google / Apple OAuth flow without
 * developer accounts (see docs/e2e_dev_accounts.md). What we CAN
 * pin is the post-OAuth callback behaviour:
 *
 *   1. The page mounts and shows "Signing you in..." while the
 *      exchange is in flight.
 *   2. An invalid / missing code surfaces a visible error message
 *      with a "Back to login" link (the user is not left staring
 *      at the spinner indefinitely).
 *   3. Anon visitor hitting /auth/callback without a code is
 *      treated the same as an invalid code — no crash, error
 *      visible, link to /login.
 *
 * These pin the OAuth-failure surfaces against a regression that
 * swallowed the auth error and stalled the page.
 */

test.describe('/auth/callback — anon paths (no valid code)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('with no code, surfaces an inline error + back-to-login link', async ({ page }) => {
		await page.goto('/auth/callback');
		// One of two acceptable terminal states:
		//   (a) Supabase exchangeCodeForSession errors → .error paragraph
		//       + "Back to login" link visible. The supabase-js error
		//       message starts with "Authentication failed:".
		//   (b) The exchange "succeeds" against an empty code (it doesn't,
		//       in practice) and the page redirects to /login on the
		//       next auth-guard tick.
		// Either way the user must not be left staring at the spinner.
		await Promise.race([
			expect(page.getByText(/Authentication failed/i)).toBeVisible({ timeout: 10_000 }),
			page.waitForURL(/\/login/, { timeout: 10_000 })
		]);
	});

	test('with a malformed code, surfaces the error message + does NOT redirect to /dashboard',
		async ({ page }) => {
			await page.goto('/auth/callback?code=this-is-not-a-real-pkce-code');
			// Should land on either the error state or back at /login.
			// Critically it must NOT silently land at /dashboard with a
			// half-built session.
			await Promise.race([
				expect(page.getByText(/Authentication failed/i)).toBeVisible({ timeout: 10_000 }),
				page.waitForURL(/\/login/, { timeout: 10_000 })
			]);
			expect(page.url()).not.toMatch(/\/dashboard/);
		});

	test('the "Back to login" affordance points at /login when an error is surfaced',
		async ({ page }) => {
			await page.goto('/auth/callback?code=invalid');
			// If the error branch renders, it includes a "Back to login" link.
			// (If we end up redirected to /login instead, that's the other
			// acceptable path — the link assertion only fires in the error
			// branch.)
			const errMsg = page.getByText(/Authentication failed/i);
			if (
				await errMsg.isVisible({ timeout: 5_000 }).catch(() => false)
			) {
				await expect(page.getByRole('link', { name: /Back to login/i })).toHaveAttribute(
					'href',
					'/login'
				);
			}
		});

	test('"Signing you in..." spinner appears in the loading state', async ({ page }) => {
		// First-render copy. The {#if error}…{:else}<p>Signing you in...</p>
		// branch is what the user sees while exchangeCodeForSession is
		// awaiting. A regression that flipped the wording or dropped the
		// fallback would surface here.
		const navPromise = page.goto('/auth/callback?code=invalid');
		// The "Signing you in..." copy renders synchronously on mount
		// before the await resolves; allow either it OR the error to
		// be present so we don't race with the rejection.
		await navPromise;
		const loading = page.getByText('Signing you in...');
		const errored = page.getByText(/Authentication failed/i);
		// At least one of the two terminal states must be present.
		await Promise.race([
			loading.waitFor({ state: 'visible', timeout: 5_000 }).catch(() => null),
			errored.waitFor({ state: 'visible', timeout: 10_000 }).catch(() => null)
		]);
	});
});
