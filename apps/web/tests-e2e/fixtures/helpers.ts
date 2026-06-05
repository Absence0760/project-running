import { chromium, expect, type Browser, type Page } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

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
	// Pre-accept the GDPR cookie banner so it doesn't float over the
	// post-sign-in surface and intercept pointer events on the sidebar
	// popover (signOut) or any bottom-of-screen affordance. The auth
	// fixture's globalSetup bakes this into the persisted storageState
	// for the cached-cookie path; tests that sign in fresh with an
	// empty storageState (sign-in-out spec) need it injected here.
	//
	// Must run BEFORE goto — the consent.svelte.ts module reads
	// localStorage once on first import, so a post-goto setItem leaves
	// the module's $state stale until a full page reload. addInitScript
	// fires on every navigation in this page, so the consent module
	// sees the accepted choice on /login AND on the post-sign-in
	// redirect to /dashboard.
	await page.addInitScript(() => {
		localStorage.setItem(
			'cookie_consent',
			JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
		);
	});

	await page.goto('/login');
	await page.waitForLoadState('networkidle');

	await page.locator('input[type="email"]').fill(user.email);
	await page.locator('input[type="password"]').fill(user.password);
	await page.locator('form button[type="submit"]').click();
}

/**
 * Re-mint the user's persisted storage state via the UI sign-in form.
 * Use after any test that rotates the user's password (or admin-resets
 * it). Supabase revokes ALL of a user's refresh tokens whenever the
 * password changes — including the one captured during globalSetup —
 * so without this every downstream spec that reads `storageStatePath`
 * bounces back to /login.
 *
 * The browser arg lets the caller share its existing chromium instance
 * (the test fixture's `browser`) instead of paying a fresh launch.
 */
export async function refreshStorageState(
	browser: Browser,
	baseURL: string,
	user: SeededUser
) {
	const ctx = await browser.newContext({ baseURL });
	const page = await ctx.newPage();
	try {
		await signIn(page, user);
		await page.waitForURL(/\/(dashboard|runs|coach)$/, { timeout: 10_000 });
		await page.evaluate(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		await mkdir(dirname(user.storageStatePath), { recursive: true });
		await ctx.storageState({ path: user.storageStatePath });
	} finally {
		await ctx.close();
	}
}

// chromium import kept available for callers that need to spin up a
// fresh browser when no fixture-managed one is in scope.
export { chromium };

/**
 * Click through the sidebar profile menu → Sign out. Asserts the
 * post-logout redirect to /login.
 */
export async function signOut(page: Page) {
	await page.locator('.profile-btn').click();
	// Class-based selector instead of role/name: the popover lives
	// inside `<div role="menu">`, which under ARIA semantics gives its
	// children an implicit `menuitem` role rather than `button`, so
	// `getByRole('button', { name: 'Sign out' })` no longer matches
	// the popover item. `.popover-danger` is the only Sign-out button
	// on the page (the profile-btn's a11y label contains the phrase
	// "sign out" but is not styled with that class).
	await page.locator('.popover-danger').click();
	await expect(page).toHaveURL(/\/login/);
}

/**
 * The /history page defaults its date filter to "today" (so cold loads
 * aren't slow on heavy users). For seed-data assertions we always
 * want everything — switch to "All time" via the toolbar select.
 *
 * The select is a native <select bind:value={dateRange}> with
 * aria-label="Date range" and an option `<option value="all">All time</option>`.
 *
 * When the account has a second modality (a logged lift/meal), /history
 * opens on the unified timeline and the run-list toolbar — including the
 * Date-range select — only renders under the "Runs" kind chip. Drop into
 * the run list first when that chip is present so the select exists.
 */
export async function switchRunsToAllTime(page: Page) {
	const runsChip = page.getByRole('button', { name: 'Runs', exact: true });
	if (await runsChip.count()) await runsChip.first().click();
	await page.getByLabel('Date range').selectOption('all');
}
