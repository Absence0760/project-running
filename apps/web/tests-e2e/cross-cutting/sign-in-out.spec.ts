import { expect, test } from '@playwright/test';

import { signIn, signOut } from '../fixtures/helpers';
import { USER_A } from '../fixtures/users';

/**
 * Sign-in + sign-out flows. These span /login → /dashboard (or back),
 * so they don't fit cleanly under any single page's spec.
 *
 * **Important constraint** — the e2e suite's storage-state files
 * (.auth/<user>.json) hold the refresh token captured during
 * globalSetup. Calling `auth.logout()` (which calls
 * `supabase.auth.signOut()`) revokes the current refresh token
 * server-side — yes, even with `scope: 'local'`. If a test signs
 * out the user whose token is in the saved file, every subsequent
 * test that loads that file fails to authenticate.
 *
 * The fix used here: BOTH tests below use an empty starting storage
 * state and drive the form themselves. The session created mid-test
 * is ephemeral — when we sign out, the only refresh token revoked is
 * the one this test minted, never the one in the saved file. Saved
 * storage-state stays valid for every other test in the suite.
 */

test.describe('sign-in / sign-out via the form + sidebar popover', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('email form sign-in lands on /dashboard', async ({ page }) => {
		await signIn(page, USER_A);
		await expect(page).toHaveURL(/\/dashboard$/);
	});

	test('sidebar chip shows the display name, never the email, as the primary identifier', async ({
		page
	}) => {
		// Persona-hunt Round 5 (woman runner, High): when display_name is
		// null the chip must fall back to a neutral "Account", not the
		// auth email — on a shared / partner's device the email is a
		// legal-name leak. The fallback logic is unit-tested in
		// account_label.test.ts; here we pin the wiring: the name line
		// renders the display name (not the email), and the email only
		// appears on the dedicated secondary line.
		await signIn(page, USER_A);
		await expect(page).toHaveURL(/\/dashboard$/);

		const name = page.locator('.profile-btn .user-name');
		await expect(name).toHaveText('Jared Howard');
		await expect(name).not.toHaveText(USER_A.email);
		await expect(page.locator('.profile-btn .user-email')).toHaveText(USER_A.email);
	});

	test('round-trip: form sign-in → /dashboard → popover sign-out → /login', async ({
		page
	}) => {
		// Sign in via the form — this mints an ephemeral session for
		// THIS test's context only. Storage-state file is untouched.
		await signIn(page, USER_A);
		await expect(page).toHaveURL(/\/dashboard$/);

		// Sign out via the sidebar popover (the same path real users
		// hit — `.profile-btn` opens the popover, "Sign out" calls
		// `handleLogout` which calls `auth.logout()`).
		await signOut(page);

		// Confirm the auth state is actually cleared — visiting an
		// authed route should bounce back to /login.
		await page.goto('/dashboard');
		await expect(page).toHaveURL(/\/login/);
	});
});
