import { expect, test } from '@playwright/test';

import { refreshStorageState } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';
import { clearMailpit, extractLink, waitForEmail } from '../fixtures/mailpit';
import { USER_A } from '../fixtures/users';

/**
 * /auth/reset — recovery-token landing page that finishes the password
 * reset round-trip started from /login?reset=1.
 *
 * The /login → email-send half is already covered by login.spec.ts
 * (its `forgot password` test plants an ephemeral user so the seed
 * user's password isn't disturbed). This file pins the /auth/reset
 * surface itself:
 *
 *   1. End-to-end with the seeded `runner@test.com` user — the
 *      strongest possible test that the planted-user variant in
 *      login.spec.ts can't make (a fresh user has no seeded data;
 *      this one proves the recovery doesn't damage an account that
 *      already has runs, plans, etc.). Cleanup MUST (a) reset the
 *      password back to `testtest` via the admin client AND (b)
 *      refresh USER_A's saved storage state. Supabase revokes ALL
 *      refresh tokens on every password write (even admin-driven
 *      resets to the same literal value); without (b), every
 *      downstream spec that loads .auth/user-a.json bounces to
 *      /login on its first navigation.
 *   2. Direct visit with no recovery hash → "invalid link" branch
 *      rendered (NOT bounced to /login by the layout's auth guard).
 *   3. Client-side length validation blocks submit on a too-short
 *      password.
 */

test.describe('/auth/reset', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('full round-trip: seeded user → email → reset → sign in with new password', async ({
		page,
		context,
		browser,
		baseURL
	}) => {
		const newPassword = 'newpass-987';
		const admin = getAdminClient();
		try {
			await clearMailpit();

			await page.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});

			await page.goto('/login?reset=1');
			await expect(page.getByRole('heading', { name: 'Reset your password' }))
				.toBeVisible({ timeout: 5_000 });
			await page.getByPlaceholder('Email address').fill(USER_A.email);
			await page.getByRole('button', { name: 'Send reset link' }).click();
			await expect(page.getByText(/sent a password reset link/))
				.toBeVisible({ timeout: 10_000 });

			const msg = await waitForEmail({ to: USER_A.email, timeoutMs: 15_000 });
			const link = extractLink(msg);
			expect(link).toContain('/auth/reset');

			const resetPage = await context.newPage();
			await resetPage.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});
			await resetPage.goto(link);
			await expect(resetPage.getByRole('heading', { name: 'Set a new password' }))
				.toBeVisible({ timeout: 10_000 });

			await resetPage.getByPlaceholder('New password', { exact: true }).fill(newPassword);
			await resetPage.getByPlaceholder('Confirm new password').fill(newPassword);
			await resetPage.getByRole('button', { name: 'Update password' }).click();
			await resetPage.waitForURL(/\/dashboard/, { timeout: 15_000 });
			await resetPage.close();

			const fresh = await page.context().browser()!.newContext();
			const verifyPage = await fresh.newPage();
			await verifyPage.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});
			await verifyPage.goto('/login');
			await verifyPage.getByPlaceholder('Email address').fill(USER_A.email);
			await verifyPage.getByPlaceholder('Password').fill(newPassword);
			await verifyPage.getByRole('button', { name: 'Sign In' }).click();
			await verifyPage.waitForURL(/\/dashboard/, { timeout: 15_000 });
			await fresh.close();
		} finally {
			// Hard guarantee: every downstream spec assumes runner@test.com
			// can sign in with `testtest`. Admin-reset even if the test
			// body threw before the rotation step, so a mid-test crash
			// can't poison the rest of the suite.
			try {
				await admin.auth.admin.updateUserById(USER_A.id, { password: USER_A.password });
			} catch (_) {
				/* best-effort */
			}
			// Supabase revokes ALL of a user's refresh tokens on password
			// change — including the admin-driven reset above. Re-mint
			// USER_A's saved storage state so the rest of the suite (which
			// reads .auth/user-a.json once per spec) doesn't bounce back
			// to /login.
			try {
				await refreshStorageState(browser, baseURL ?? 'http://localhost:7777', USER_A);
			} catch (_) {
				/* best-effort — the user's downstream specs will skip-skip
				   anyway if this also fails, but most likely the form
				   sign-in works as soon as admin sets the password back. */
			}
		}
	});

	test('invalid / missing token renders the "invalid link" branch — not a /login redirect',
		async ({ page }) => {
			await page.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});

			await page.goto('/auth/reset');
			// The page must NOT be bounced to /login by the global auth
			// guard. The recovery flow is a special anon-allowed surface;
			// a bounce to /login would strand a user whose link expired
			// with no path forward except staring at the sign-in form.
			await expect(page.getByText(/reset link is invalid or has expired/i))
				.toBeVisible({ timeout: 10_000 });
			expect(page.url()).toContain('/auth/reset');

			const cta = page.getByRole('link', { name: /Request a new link/i });
			await expect(cta).toBeVisible();
			await expect(cta).toHaveAttribute('href', '/login?reset=1');
		});

	test('anon guard: /auth/reset renders shell-less (no sidebar) even with no session',
		async ({ page }) => {
			// The layout's auth guard would otherwise redirect anon
			// visitors on protected paths to /login. /auth/reset is a
			// special anon-allowed surface — adding it to the layout's
			// shellLessExact list is what keeps a user mid-recovery off
			// the sidebar and free of the auth-guard bounce. This test
			// pins that contract: if a future refactor drops /auth/reset
			// from the anon-allowed list, this fails immediately rather
			// than as a hard-to-trace recovery-flow regression.
			await page.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});

			await page.goto('/auth/reset');
			await expect(page.getByRole('heading', { name: 'Set a new password' }))
				.toBeVisible({ timeout: 10_000 });
			// The app shell isn't rendered for shell-less routes; the
			// signed-in sidebar should not appear. The Dashboard nav
			// link is the cheapest available shell-presence marker.
			await expect(page.getByRole('link', { name: /^Dashboard$/ })).toHaveCount(0);
			expect(page.url()).toContain('/auth/reset');
		});

	test('client-side length validation blocks a too-short password', async ({
		page,
		context,
		browser,
		baseURL
	}) => {
		const admin = getAdminClient();
		try {
			await clearMailpit();
			await page.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});

			await page.goto('/login?reset=1');
			await page.getByPlaceholder('Email address').fill(USER_A.email);
			await page.getByRole('button', { name: 'Send reset link' }).click();
			await expect(page.getByText(/sent a password reset link/))
				.toBeVisible({ timeout: 10_000 });

			const msg = await waitForEmail({ to: USER_A.email, timeoutMs: 15_000 });
			const link = extractLink(msg);

			const resetPage = await context.newPage();
			await resetPage.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});
			await resetPage.goto(link);
			await expect(resetPage.getByRole('heading', { name: 'Set a new password' }))
				.toBeVisible({ timeout: 10_000 });

			// `minlength=6` on the <input> means the browser's native
			// form-validation step blocks the submit before the JS
			// handler runs. The URL must NOT navigate to /dashboard and
			// the form must stay on /auth/reset.
			await resetPage.getByPlaceholder('New password', { exact: true }).fill('shrt');
			await resetPage.getByPlaceholder('Confirm new password').fill('shrt');
			await resetPage.getByRole('button', { name: 'Update password' }).click();
			await resetPage.waitForTimeout(500);
			expect(resetPage.url()).toContain('/auth/reset');
			await expect(resetPage.getByRole('heading', { name: 'Set a new password' })).toBeVisible();
			await resetPage.close();
		} finally {
			// The token has been consumed by the supabase-js URL parser
			// but no updateUser ran — the seed password is intact. Reset
			// defensively anyway so a transient redirect that DID rotate
			// can't poison the suite.
			try {
				await admin.auth.admin.updateUserById(USER_A.id, { password: USER_A.password });
			} catch (_) {
				/* best-effort */
			}
			// Admin password write revokes refresh tokens whether the
			// password actually changed value or not, so re-mint the
			// saved storage state for the rest of the suite.
			try {
				await refreshStorageState(browser, baseURL ?? 'http://localhost:7777', USER_A);
			} catch (_) {
				/* best-effort */
			}
		}
	});
});
