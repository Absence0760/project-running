import { expect, type Page } from '@playwright/test';

import type { SeededUser } from './users';

/**
 * Drive the email-password sign-in form. Shared by globalSetup
 * (fixtures/auth.ts) and the smoke spec's unauthenticated tests so
 * the hydration-wait + selector behaviour stays in one place.
 *
 * Returns once the post-login redirect has settled — caller is
 * responsible for asserting the destination URL if it cares.
 *
 * Why the explicit `networkidle` wait: Playwright can click the
 * submit button before Svelte 5 has bound `onsubmit`. With nothing
 * preventing default, the form's native GET submit fires and the
 * page navigates to /login?email=...&password=... — visually
 * identical to "still on /login" but with no auth POST attempted.
 * Waiting for networkidle covers Vite HMR connection + the dynamic
 * imports for `auth.svelte.ts` + `@supabase/ssr`.
 */
export async function signIn(page: Page, user: SeededUser) {
	await page.goto('/login');
	await page.waitForLoadState('networkidle');

	await page.locator('input[type="email"]').fill(user.email);
	await page.locator('input[type="password"]').fill(user.password);
	await page.locator('form button[type="submit"]').click();
}

/**
 * Click through the sidebar profile menu → Sign out. Asserts the
 * post-logout redirect to /login.
 */
export async function signOut(page: Page) {
	await page.locator('.profile-btn').click();
	await page.getByRole('button', { name: 'Sign out' }).click();
	await expect(page).toHaveURL(/\/login/);
}

/**
 * The /runs page defaults its date filter to "today" (so cold loads
 * aren't slow on heavy users). For seed-data assertions we always
 * want everything — switch to "All time" via the toolbar select.
 *
 * The select is a native <select bind:value={dateRange}> with
 * aria-label="Date range" and an option `<option value="all">All time</option>`.
 */
export async function switchRunsToAllTime(page: Page) {
	await page.getByLabel('Date range').selectOption('all');
}
