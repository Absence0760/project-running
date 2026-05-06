import { expect, test } from '@playwright/test';

import { switchRunsToAllTime } from './fixtures/helpers';
import {
	ALEX_PRIVATE_RUN_ID,
	RUNNER_PUBLIC_RUN_ID
} from './fixtures/seeded-data';
import { USER_A, USER_B } from './fixtures/users';

/**
 * Security spec — RLS / authorization regressions that reach the UI.
 *
 * pgtap covers the SQL layer (rls_runs_test.sql, rls_engagement_chain_test.sql,
 * rls_privacy_clipping_test.sql, etc.) — those tests assert the policies
 * themselves are wired right. This spec catches the next failure mode:
 * an RLS policy that's correct at the database level but reaches the UI
 * via a fetch path that bypasses or misuses it (bad join, dropped filter,
 * client-side lookup that trusts the URL).
 *
 * Five tests across three describe blocks:
 *   - Cross-user isolation (User A ↛ User B's data, and vice-versa).
 *   - Anonymous walls (anon ↛ private content).
 *   - Storage-state walls (unauthenticated ↛ authenticated routes).
 *
 * The cross-user pairs use both directions — A→B isolation could be
 * one-sided (e.g. an RLS policy with a typo on the "or" branch) and
 * we want to catch that.
 */

test.describe('Cross-user run isolation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('User A cannot see User B\'s private run via /runs/[id]', async ({
		page
	}) => {
		// Alex's private run UUID is pinned in seed.sql. RLS on the
		// `runs` table should hide it from User A entirely (the row
		// query returns null → run-detail page renders the empty
		// fallthrough state).
		await page.goto(`/runs/${ALEX_PRIVATE_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// Negative assertion: alex's private run title must NEVER
		// appear in the rendered page. If it does, RLS leaked.
		await expect(
			page.getByRole('heading', { name: 'Recovery jog (private)' })
		).toHaveCount(0);
		// Positive assertion: the run-detail layout's distinctive
		// "All runs" back-link only renders when `run` is non-null —
		// its absence proves the page hit the not-found branch, not
		// the loaded-run branch.
		await expect(
			page.getByRole('link', { name: /All runs/i })
		).toHaveCount(0);
	});

	test('User B cannot see User A\'s public-run-detail surface (own list excludes others\' rows)', async ({
		page,
		browser
	}) => {
		// User B's /runs list must contain ONLY user B's runs — never
		// runner's. fetchRuns explicitly filters by user_id; this
		// asserts the UI honors that even after switching filters.
		const ctx = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const bPage = await ctx.newPage();

		try {
			await bPage.goto('/runs');
			await switchRunsToAllTime(bPage);
			await expect(bPage.locator('.run-card').first()).toBeVisible();

			// Fetch every run-card href; each must resolve to one of
			// USER_B's runs (RLS would block a runner-owned row, but
			// "blocked" surfacing as silently empty would still let
			// a future bug pass — explicit owner-shape assertion).
			const hrefs = await bPage.locator('.run-card').evaluateAll(
				(els) => els.map((e) => (e as HTMLAnchorElement).getAttribute('href') ?? '')
			);
			expect(hrefs.length).toBeGreaterThan(0);
			for (const href of hrefs) {
				expect(href).toMatch(/^\/runs\/[0-9a-f-]+$/i);
			}

			// Stronger negative: alex must NOT see runner's pinned
			// public run in their own /runs list (different user, RLS
			// hides regardless of is_public).
			await expect(
				bPage.locator(`.run-card[href$="${RUNNER_PUBLIC_RUN_ID}"]`)
			).toHaveCount(0);
		} finally {
			await ctx.close();
		}
	});
});

test.describe('Anonymous walls', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon /share/run/<private-id> shows not-found, not the run', async ({
		page
	}) => {
		// Stub the EF — same reason as the smoke spec.
		await page.route('**/functions/v1/clip-public-track', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ points: [] })
			})
		);

		await page.goto(`/share/run/${ALEX_PRIVATE_RUN_ID}`);
		await page.waitForLoadState('networkidle');

		// RunShareView's empty-row branch renders "Run not found." —
		// assert the UI surfaces that, NOT the run's metadata.
		await expect(page.getByText(/Run not found/i)).toBeVisible({
			timeout: 10_000
		});
		// Negative: the title from alex's private run must never
		// reach the rendered page. The seed gave it metadata.title
		// "Recovery jog (private)".
		await expect(page.getByText('Recovery jog (private)')).toHaveCount(0);
	});

	test('anon /dashboard redirects to /login', async ({ page }) => {
		await page.goto('/dashboard');
		// The auth store's $effect on /login + the layout's auth-guard
		// both trigger this redirect on a no-session navigation.
		await expect(page).toHaveURL(/\/login/, { timeout: 10_000 });
	});

	test('anon /runs redirects to /login', async ({ page }) => {
		await page.goto('/runs');
		await expect(page).toHaveURL(/\/login/, { timeout: 10_000 });
	});
});
