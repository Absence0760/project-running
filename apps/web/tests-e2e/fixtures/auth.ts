import type { FullConfig } from '@playwright/test';
import { chromium } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

import { signIn } from './helpers';
import { ALL_USERS, type SeededUser } from './users';
// @ts-expect-error — sibling .mjs imports run fine under tsx but the
// types are intentionally untyped (this file is plain JS so the same
// helper can be imported from vite.config.ts too).
import { checkEnvIsolation, formatGuardError } from '../../scripts/env_isolation.mjs';

/**
 * Playwright globalSetup — sign each seeded user in once via the UI
 * and save the storage state to disk.
 *
 * Spec files then attach the storage state via:
 *
 *   test.use({ storageState: USER_A.storageStatePath });
 *
 * to skip the form submit on every test. The first-time login is the
 * only place a real `/login` form interaction happens; everything
 * downstream rides on the persisted Supabase session cookie.
 *
 * We deliberately use the UI (not `supabase.auth.signInWithPassword`
 * called directly) so this fixture exercises the actual sign-in path
 * once per CI run. If sign-in is broken, every spec fails fast in
 * globalSetup with a clear "could not sign in user A" rather than
 * cascading into 18 confusing 401-from-the-app failures.
 *
 * Resolved relative to the apps/web/tests-e2e directory.
 */
export default async function globalSetup(config: FullConfig) {
	// Dev/prod isolation: refuse to run e2e against a non-local stack.
	// Same rule as the Vite dev guard. A test run that hits prod can
	// (a) corrupt prod data via the seeded-user fixtures, and
	// (b) burn live Stripe / Anthropic spend on every test. Belt-and-
	// braces: even if PUBLIC_SUPABASE_URL points local for the dev
	// server, an inherited shell-level SUPABASE_URL pointing at prod
	// is enough to compromise the test run.
	const result = checkEnvIsolation(process.env);
	if (result.override) {
		console.warn(
			'[env-isolation] ALLOW_PROD_URL_IN_DEV=true — Playwright guard bypassed.'
		);
	} else if (!result.ok) {
		throw new Error(formatGuardError(result, { scope: 'playwright' }));
	}

	const baseURL =
		config.projects[0]?.use?.baseURL ?? 'http://localhost:7777';

	for (const user of ALL_USERS) {
		await signInAndSaveState(baseURL, user);
	}
}

async function signInAndSaveState(baseURL: string, user: SeededUser) {
	const browser = await chromium.launch();
	const ctx = await browser.newContext({ baseURL });
	const page = await ctx.newPage();

	try {
		await signIn(page, user);

		// Bake an accepted cookie-consent into the persisted storageState so
		// every signed-in spec inherits it. Without this the GDPR banner
		// floats above the page footer and silently intercepts pointer
		// events on .kudos-btn, .star-btn, and review-form submits during
		// e2e — manifesting as cascading "element is not stable" failures
		// far from the real cause.
		await page.evaluate(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});

		// Wait for the post-login navigation to settle. The login flow
		// redirects to /dashboard on success; on failure the form
		// re-renders with the same /login URL and an error banner.
		try {
			await page.waitForURL(/\/(dashboard|runs|coach)$/, { timeout: 10_000 });
		} catch (err) {
			if (process.env.E2E_SKIP_AUTH_FAILURES) {
				console.warn(
					`[auth fixture] Sign-in for ${user.email} did not redirect — final URL ${page.url()}. ` +
						`Skipping due to E2E_SKIP_AUTH_FAILURES.`
				);
				return;
			}
			const errorText = await page.locator('.error-banner, .alert-error, [role="alert"]').textContent().catch(() => '<no error banner>');
			throw new Error(
				`auth fixture: ${user.email} did not redirect after sign-in. ` +
					`Final URL: ${page.url()}. Error banner: "${errorText}".`
			);
		}

		// storageStatePath is already absolute (resolved at module-load
		// in users.ts).
		await mkdir(dirname(user.storageStatePath), { recursive: true });
		await ctx.storageState({ path: user.storageStatePath });
	} finally {
		await ctx.close();
		await browser.close();
	}
}
