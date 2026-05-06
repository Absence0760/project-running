import type { FullConfig } from '@playwright/test';
import { chromium } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

import { ALL_USERS, type SeededUser } from './users';

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
	const baseURL =
		config.projects[0]?.use?.baseURL ?? 'http://127.0.0.1:8888';

	for (const user of ALL_USERS) {
		await signInAndSaveState(baseURL, user);
	}
}

async function signInAndSaveState(baseURL: string, user: SeededUser) {
	const browser = await chromium.launch();
	const ctx = await browser.newContext();
	const page = await ctx.newPage();

	try {
		await page.goto(`${baseURL}/login`);
		// The login form uses placeholders + type attributes, no <label>
		// elements (apps/web/src/routes/login/+page.svelte). Select by
		// type so the fixture survives placeholder copy changes.
		await page.locator('input[type="email"]').fill(user.email);
		await page.locator('input[type="password"]').fill(user.password);
		await page.getByRole('button', { name: /sign in|sign up/i }).click();

		// Wait for the post-login navigation to settle. The login flow
		// redirects to /dashboard on success; on failure the form
		// re-renders with the same /login URL and an error banner.
		await page.waitForURL(/\/(dashboard|runs|coach)$/, { timeout: 10_000 });

		const targetPath = resolve(__dirname, '..', user.storageStatePath);
		await mkdir(dirname(targetPath), { recursive: true });
		await ctx.storageState({ path: targetPath });
	} finally {
		await ctx.close();
		await browser.close();
	}
}
