import { expect, test } from '@playwright/test';

import { signIn } from './fixtures/helpers';
import { getAdminClient } from './fixtures/local-supabase';
import { USER_A } from './fixtures/users';

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
			// button stays disabled until the JS handler is wired up.
			const submit = page.getByRole('button', { name: 'Sign Up' });
			await expect(submit).toBeEnabled({ timeout: 5_000 });

			await page.getByPlaceholder('Email address').fill(email);
			await page.getByPlaceholder('Password').fill(password);
			await submit.click();

			// Successful sign-up triggers refreshSession() then goto('/dashboard').
			// Don't assert on dashboard chrome — for a brand-new user with
			// no runs / no goal, /dashboard renders an extended loading
			// shell while the empty-state derivations resolve. The URL
			// transition is the contract: signUp() → session minted →
			// goto('/dashboard') fired (a redirect back to /login on a
			// failed signUp would mean the test broke). Sidebar nav
			// rendering is a separate proxy that the auth state lifted.
			await expect(
				page.getByRole('link', { name: /Dashboard/ }).first()
			).toBeVisible({ timeout: 10_000 });

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
});
