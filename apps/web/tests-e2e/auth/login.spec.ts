import { expect, test } from '@playwright/test';

import { signIn } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { clearMailpit, extractLink, waitForEmail } from '../fixtures/mailpit';
import { USER_A } from '../fixtures/users';

/**
 * /login — auth surface for the email-form path.
 *
 * The successful-sign-in flow is in cross-cutting/sign-in-out.spec.ts
 * because it spans /login → /dashboard and is the seam between
 * unauthenticated and authenticated app states. This file holds the
 * /login-only behaviours: failed sign-ins that stay on /login, the
 * page rendering for an anon visitor, and (in future rounds) the
 * OAuth-button affordances + reset-password flow.
 */

test.describe('/login', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('rejects an unknown email/password combo and stays on /login', async ({
		page
	}) => {
		await signIn(page, {
			...USER_A,
			email: 'noone@nowhere.test',
			password: 'wrong-password'
		});

		// Stay on /login (the form re-renders with an error banner).
		// We don't assert the error copy — it may shift; the URL
		// behaviour is the security contract.
		await expect(page).toHaveURL(/\/login/);
	});

	test('sign-up: ?signup=1 → fill form → land on /dashboard with a fresh user', async ({
		page
	}) => {
		// First-time onboarding gate: a regression here means new users
		// can't create accounts. Local Supabase has enable_confirmations
		// = false (apps/backend/supabase/config.toml) so signUp returns
		// a session immediately — no email-click step to mock.
		const email = `e2e-signup-${Date.now()}@test.local`;
		const password = 'testtest';
		let userId: string | null = null;

		try {
			await page.goto('/login?signup=1');
			// Heading flips to "Create an account" when isSignUp=true.
			await expect(
				page.getByRole('heading', { name: 'Create an account' })
			).toBeVisible({ timeout: 5_000 });

			// Wait for the post-onMount `hydrated` flag — the submit
			// button stays disabled until both the JS handler is wired
			// up AND the consent boxes are ticked. Don't assert
			// `toBeEnabled` here — the age + ToS gate keeps it disabled
			// until further down. The pre-fill disabled state IS the
			// contract; signup-age-gate.spec.ts pins that.
			const submit = page.getByRole('button', { name: 'Sign Up' });

			await page.getByPlaceholder('Email address').fill(email);
			await page.getByPlaceholder('Password').fill(password);

			// Age gate + ToS acceptance: both required to enable Submit.
			// Re-verify the disabled-until-checked contract here so a
			// regression that quietly skipped one box would fail loudly.
			await expect(submit).toBeDisabled();
			await page.getByLabel(/I confirm I am 16 years of age or older/).check();
			await expect(submit).toBeDisabled();
			await page.getByLabel(/I have read and agree to the/).check();
			await expect(submit).toBeEnabled();

			await submit.click();

			// Successful sign-up triggers refreshSession() then
			// goto('/dashboard'). Migration 20261016_001 added the
			// `onboarded_at` column + the layout-level gate routes new
			// users to /onboarding before they reach /dashboard — so a
			// fresh signup lands on /onboarding, not /dashboard. Assert
			// the URL transition off /login + onto /onboarding as the
			// signup-success contract. The wizard's behaviour itself is
			// pinned in `tests-e2e/onboarding/wizard.spec.ts`; here we
			// only verify the routing handoff fired.
			await page.waitForURL(/\/onboarding/, { timeout: 10_000 });
			await expect(
				page.getByRole('heading', { name: /What should we call you/i })
			).toBeVisible({ timeout: 5_000 });

			// Capture the new auth.users.id for cleanup.
			const admin = getAdminClient();
			const { data: list } = await admin.auth.admin.listUsers({
				page: 1,
				perPage: 200
			});
			userId = list?.users?.find((u) => u.email === email)?.id ?? null;
		} finally {
			if (userId) {
				try {
					await getAdminClient().auth.admin.deleteUser(userId);
				} catch (_) {
					/* best-effort */
				}
			}
		}
	});

	test('forgot password: link → email → reset → sign in with new password', async ({
		page,
		context
	}) => {
		// End-to-end recovery flow:
		//   1. Plant a fresh user with a known starting password.
		//   2. /login → "Forgot your password?" → fill email → submit.
		//   3. The handler calls supabase.auth.resetPasswordForEmail
		//      which delivers a recovery email into the local Mailpit.
		//   4. Read the email from Mailpit, extract the action URL,
		//      navigate to it (the URL hash carries the recovery token
		//      which supabase-js consumes on /auth/reset).
		//   5. /auth/reset shows the "Set a new password" form. Fill +
		//      submit → updateUser → signed in via the recovery session
		//      → goto('/dashboard').
		//   6. Sign out, then sign in with the NEW password. Proves the
		//      password actually rotated server-side, not just locally.
		//   7. Cleanup: delete the planted user.
		const email = `e2e-forgot-${Date.now()}@test.local`;
		const oldPassword = 'oldpass-123';
		const newPassword = 'newpass-456';
		let userId: string | null = null;

		const admin = getAdminClient();
		try {
			const { data: created, error: createErr } = await admin.auth.admin.createUser({
				email,
				password: oldPassword,
				email_confirm: true
			});
			if (createErr || !created?.user) throw createErr ?? new Error('createUser failed');
			userId = created.user.id;

			// Stamp `onboarded_at` on the auto-created user_profiles
			// row so the layout-level onboarding gate doesn't redirect
			// the sign-in to /onboarding (the test is about password
			// rotation, not the wizard). Migration 20261016_001 added
			// the column. Same pattern as the saga-users fixture.
			await admin
				.from('user_profiles')
				.upsert({
					id: userId,
					preferred_unit: 'km',
					subscription_tier: 'free',
					onboarded_at: new Date().toISOString()
				});

			await clearMailpit();

			// Step 1-2: request the reset. The "Forgot your password?"
			// toggle on /login flips a $state without an explicit
			// hydration gate; the test deep-links via ?reset=1 (the
			// canonical URL also handed out by typing /login?reset=1)
			// to avoid racing the toggle click against Svelte 5
			// hydration. The mount-via-URL path is the equivalent
			// surface — in fact a notification email's link resolves
			// to this URL so the deep-link must work anyway.
			await page.goto('/login?reset=1');
			await expect(page.getByRole('heading', { name: 'Reset your password' }))
				.toBeVisible({ timeout: 5_000 });

			// In reset mode the password input is hidden — only email +
			// "Send reset link" is visible.
			await expect(page.getByPlaceholder('Password')).toHaveCount(0);
			await page.getByPlaceholder('Email address').fill(email);
			await page.getByRole('button', { name: 'Send reset link' }).click();

			// Step 3: confirmation banner. The exact wording is non-
			// committal so this isn't a user-enumeration oracle.
			await expect(page.getByText(/sent a password reset link/))
				.toBeVisible({ timeout: 10_000 });

			// Step 4: read the email out of Mailpit, extract the link.
			const msg = await waitForEmail({ to: email, timeoutMs: 15_000 });
			const link = extractLink(msg);
			expect(link).toContain('/auth/reset');

			// Step 5: visit the reset link in a new page (a fresh tab
			// captures the supabase-js URL-hash consumption cleanly,
			// without competing auth state from the /login tab).
			// Mailpit gives us the verify-link form
			//   <supabase>/auth/v1/verify?token=...&type=recovery&redirect_to=<origin>/auth/reset
			// which 302s to the origin with the access_token in the hash.
			const resetPage = await context.newPage();
			await resetPage.goto(link);
			await expect(resetPage.getByRole('heading', { name: 'Set a new password' }))
				.toBeVisible({ timeout: 10_000 });

			// getByPlaceholder is substring-matching, so "New password"
			// would also match "Confirm new password" — use exact.
			await resetPage.getByPlaceholder('New password', { exact: true }).fill(newPassword);
			await resetPage.getByPlaceholder('Confirm new password').fill(newPassword);
			await resetPage.getByRole('button', { name: 'Update password' }).click();
			await resetPage.waitForURL(/\/dashboard/, { timeout: 15_000 });
			await resetPage.close();

			// Step 6: sign in with the NEW password from a fresh browser
			// context (no carried-over session) to prove the rotation
			// landed server-side, not just on the recovery session.
			// supabase.auth.signInWithPassword would 400 if the password
			// hadn't actually rotated.
			const fresh = await page.context().browser()!.newContext();
			const verifyPage = await fresh.newPage();
			await verifyPage.goto('/login');
			await verifyPage.getByPlaceholder('Email address').fill(email);
			await verifyPage.getByPlaceholder('Password').fill(newPassword);
			await verifyPage.getByRole('button', { name: 'Sign In' }).click();
			await verifyPage.waitForURL(/\/dashboard/, { timeout: 15_000 });
			await fresh.close();
		} finally {
			if (userId) {
				try {
					await admin.auth.admin.deleteUser(userId);
				} catch (_) {
					/* best-effort */
				}
			}
		}
	});
});
