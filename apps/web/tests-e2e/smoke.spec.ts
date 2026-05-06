import { expect, test } from '@playwright/test';

import { signIn, signOut, switchRunsToAllTime } from './fixtures/helpers';
import { RUNNER_PUBLIC_RUN_ID } from './fixtures/seeded-data';
import { USER_A } from './fixtures/users';

/**
 * Smoke spec — "is the site broken?" coverage.
 *
 * Six tests, three describe blocks:
 *   - Sign-in / sign-out — exercises the unauthenticated form + the
 *     authenticated logout affordance. globalSetup also drives the
 *     login form once per user; a focused test makes the failure
 *     mode explicit ("login broken" vs "every authenticated test
 *     broken in the same way").
 *   - Authenticated navigation — /dashboard, /runs, /runs/[id]. These
 *     prove the SPA shell loads, the Supabase queries return rows,
 *     and the run-detail map mounts.
 *   - Anonymous share path — /share/run/<public-id> is the only
 *     route deliberately reachable without auth. Catches regressions
 *     that accidentally gate it behind a login redirect.
 *
 * Selectors prefer accessible roles + text, falling back to scoped
 * class names for the bits without obvious aria handles (the sidebar
 * profile button, run-card list rows). Tests assert ">= N" counts so
 * they're stable as the seed grows.
 */

test.describe('Sign-in / sign-out', () => {
	// Drop globalSetup's saved session — these tests drive the form themselves.
	test.use({ storageState: { cookies: [], origins: [] } });

	test('signs in via the email form and lands on /dashboard', async ({
		page
	}) => {
		await signIn(page, USER_A);
		await expect(page).toHaveURL(/\/dashboard$/);
	});

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
});

test.describe('Authenticated session — User A', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/dashboard renders with seeded mileage + recent runs', async ({
		page
	}) => {
		await page.goto('/dashboard');

		// "Mileage" + "Recent Runs" are h2's on the dashboard. Asserting
		// them proves the page rendered past the loading skeleton AND
		// the per-section components loaded their seeded data.
		await expect(
			page.getByRole('heading', { name: /mileage/i, level: 2 })
		).toBeVisible();
		await expect(
			page.getByRole('heading', { name: /recent runs/i, level: 2 })
		).toBeVisible();
	});

	test('/runs lists the seeded runs (after switching to All time)', async ({
		page
	}) => {
		await page.goto('/runs');
		await switchRunsToAllTime(page);

		// runner has 12 generated runs + 1 pinned ("E2E demo public run")
		// = 13 minimum. Assert >= 13 to stay stable if the seed grows.
		const cards = page.locator('.run-card');
		await expect(cards.first()).toBeVisible();
		expect(await cards.count()).toBeGreaterThanOrEqual(13);
	});

	test('/runs/[id] mounts the run-detail page (title)', async ({ page }) => {
		// Use the pinned runner public run so this test is deterministic.
		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		// Run-detail fetches the row + (lazily) the track via Storage.
		// networkidle guarantees those settle before we assert.
		await page.waitForLoadState('networkidle');

		// Title is the metadata.title we seeded. If the run loaded, the
		// h1 reflects it. We don't assert the map mounts — the seeded
		// run has no track in Storage so RunMap never renders. The
		// data-flow spec covers track rendering against runs that do
		// have tracks.
		await expect(
			page.getByRole('heading', { name: 'E2E demo public run', level: 1 })
		).toBeVisible();
	});

	test('sign-out clears the session and redirects to /login', async ({
		page
	}) => {
		await page.goto('/dashboard');
		await signOut(page);

		// After sign-out, /dashboard requires auth — should bounce to
		// /login (or a return_to-decorated variant of it).
		await page.goto('/dashboard');
		await expect(page).toHaveURL(/\/login/);
	});
});

test.describe('Anonymous share path', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('/share/run/[public-id] loads without auth', async ({ page }) => {
		// Stub the clip-public-track Edge Function — we don't run
		// `supabase functions serve` alongside tests, and RunShareView
		// calls this for non-owner viewers (decisions §33). Without
		// the stub the await hangs and `loading` never flips off.
		// Returning [] here is the same shape the EF returns for a
		// run with no track in Storage (the seed shape).
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);

		await page.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// share-page chrome + the run-meta block. The seeded run has no
		// track in Storage so we don't assert on the map. The chrome
		// + run-meta combo confirms anon read of the runs row succeeded
		// via the public_runs view (no auth, no 404).
		await expect(page.getByRole('link', { name: 'Run Onward' })).toBeVisible();
		await expect(page.locator('.run-meta')).toBeVisible({ timeout: 10_000 });
	});
});
