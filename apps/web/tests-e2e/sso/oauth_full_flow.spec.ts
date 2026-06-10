import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';

/**
 * SSO / OAuth login — full flow against a mock OIDC provider.
 *
 * Real Google/Apple can't run in CI, and GoTrue special-cases those two
 * providers against the real Google/Apple — so a mock can only stand in
 * as the GENERIC `keycloak` OIDC provider GoTrue accepts with a custom
 * url. config.toml's [auth.external.keycloak] points at the local
 * oauth2-mock-server (see ../scripts/start-mock-oidc.mjs + ../README in
 * tests-e2e/sso/README.md). This lane initiates the OAuth flow against
 * the REAL running app (the dev-only window.__supabase seam exposed in
 * $lib/core/supabase) and drives it to completion.
 *
 * The ONE thing not exercised is provider IDENTITY: the mock is keycloak,
 * not Google. Everything downstream of the provider redirect IS the real
 * code path — signInWithOAuth -> GoTrue authorize -> mock consent
 * (auto-approve) -> /auth/callback?code -> exchangeCodeForSession ->
 * Supabase session -> the post-OAuth age/terms gate -> the app. Because
 * GoTrue special-cases Google, swapping keycloak for google here is
 * impossible; this is the closest faithful exercise of our OAuth code.
 */

const MOCK_PORT = process.env.SSO_MOCK_OIDC_PORT ?? '9888';
const MOCK_BASE = `http://127.0.0.1:${MOCK_PORT}`;

// Stable identities for the two cases. The mock issues whichever was last
// set via POST /__identity; each test sets its own before signing in.
const NEW_USER = { sub: 'sso-e2e-new-user', email: 'sso-e2e-new@example.com' };
const RETURNING = { sub: 'sso-e2e-returning-user', email: 'sso-e2e-returning@example.com' };

async function setMockIdentity(id: { sub: string; email: string }): Promise<void> {
	const res = await fetch(`${MOCK_BASE}/__identity`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(id)
	});
	if (!res.ok) throw new Error(`mock /__identity failed: ${res.status}`);
}

/** Delete any auth user with this email so the case starts from a known state. */
async function deleteUserByEmail(email: string): Promise<void> {
	const admin = getAdminClient();
	const { data } = await admin.auth.admin.listUsers({ perPage: 200 });
	const match = data?.users?.find((u) => u.email === email);
	if (match) await admin.auth.admin.deleteUser(match.id);
}

/**
 * Initiate the keycloak OAuth sign-in from inside the real app via the
 * dev-only window.__supabase seam (the app has no Keycloak button — the
 * mock stands in for Google, which is a real button but unmockable). The
 * redirect chain runs entirely in the browser: app -> GoTrue authorize
 * -> mock auto-approve -> /auth/callback.
 */
async function startOAuth(page: import('@playwright/test').Page): Promise<void> {
	await page.goto('/login');
	await page.waitForFunction(() => '__supabase' in window, { timeout: 10_000 });
	// skipBrowserRedirect so supabase-js returns the authorize URL instead
	// of navigating from inside evaluate — that lets the PKCE code verifier
	// (stored by signInWithOAuth via @supabase/ssr's cookie storage) fully
	// commit before we navigate, so the callback's exchangeCodeForSession
	// can find it. Auto-redirecting from evaluate races the cookie write.
	const authorizeUrl = await page.evaluate(async () => {
		const sb = (
			window as unknown as {
				__supabase: {
					auth: {
						signInWithOAuth: (o: unknown) => Promise<{ data: { url: string | null }; error: unknown }>;
					};
				};
			}
		).__supabase;
		const { data, error } = await sb.auth.signInWithOAuth({
			provider: 'keycloak',
			options: {
				redirectTo: `${window.location.origin}/auth/callback`,
				skipBrowserRedirect: true
			}
		});
		if (error) throw error;
		return data.url;
	});
	if (!authorizeUrl) throw new Error('signInWithOAuth returned no authorize url');
	await page.goto(authorizeUrl);
}

test.describe('SSO OAuth — mock OIDC full flow', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('new OAuth user lands on the age/terms gate, then into the app', async ({ page }) => {
		await deleteUserByEmail(NEW_USER.email);
		await setMockIdentity(NEW_USER);

		await startOAuth(page);

		// A brand-new OAuth user has no stamped consent, so the callback
		// routes to /auth/confirm-age before any feature surface renders.
		await page.waitForURL(/\/auth\/confirm-age/, { timeout: 20_000 });
		await expect(page.getByRole('checkbox')).toHaveCount(2);

		// Tick both gates + continue.
		const boxes = page.getByRole('checkbox');
		await boxes.nth(0).check();
		await boxes.nth(1).check();
		await page.getByRole('button', { name: /continue/i }).click();

		// Past the gate the user is a fresh signup (onboarded_at null), so
		// the layout's onboarding gate routes to /onboarding. Either that
		// or /dashboard is an acceptable terminal "you're in the app now"
		// state; what matters is we left the consent gate with a real
		// session.
		await page.waitForURL(/\/(onboarding|dashboard)/, { timeout: 20_000 });

		// The session is real: the admin API now sees the keycloak user.
		const admin = getAdminClient();
		const { data } = await admin.auth.admin.listUsers({ perPage: 200 });
		const created = data?.users?.find((u) => u.email === NEW_USER.email);
		expect(created, 'GoTrue created the OAuth user').toBeTruthy();
		expect(created?.app_metadata?.provider).toBe('keycloak');
	});

	test('returning OAuth user goes straight to the app (no gate)', async ({ page, context }) => {
		// A "returning" user is one GoTrue already minted via the real
		// OAuth flow. Seed that genuinely: sign in once (creates the
		// keycloak user, lands on the consent gate), then stamp consent +
		// onboarding on the real user_profiles row, drop the local session,
		// and sign in AGAIN — the second pass must skip /auth/confirm-age.
		await deleteUserByEmail(RETURNING.email);
		await setMockIdentity(RETURNING);

		await startOAuth(page);
		await page.waitForURL(/\/auth\/confirm-age/, { timeout: 20_000 });

		const admin = getAdminClient();
		const { data: list } = await admin.auth.admin.listUsers({ perPage: 200 });
		const uid = list?.users?.find((u) => u.email === RETURNING.email)?.id;
		expect(uid, 'first sign-in created the keycloak user').toBeTruthy();
		const now = new Date().toISOString();
		const { error: upErr } = await admin.from('user_profiles').upsert({
			id: uid!,
			preferred_unit: 'km',
			subscription_tier: 'free',
			age_confirmed_at: now,
			terms_accepted_at: now,
			onboarded_at: now
		});
		if (upErr) throw upErr;

		// Clear the local session so the second sign-in is a clean
		// returning-user login, not a same-tab continuation.
		await context.clearCookies();
		await page.evaluate(() => window.localStorage.clear());

		await setMockIdentity(RETURNING);
		await startOAuth(page);

		// Consent + onboarding already satisfied: straight into the app,
		// never via the gate.
		await page.waitForURL(/\/dashboard/, { timeout: 20_000 });
		expect(page.url()).not.toMatch(/\/auth\/confirm-age/);

		await admin.auth.admin.deleteUser(uid!);
	});
});
