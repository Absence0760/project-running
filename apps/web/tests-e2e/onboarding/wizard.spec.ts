import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';
import { getAdminClient } from '../fixtures/local-supabase';

/**
 * /onboarding — post-signup wizard.
 *
 * Migration 20261016_001 added `user_profiles.onboarded_at` (null
 * for fresh signups, backfilled `now()` for every existing row).
 * The layout-level gate (apps/web/src/routes/+layout.svelte)
 * routes signed-in users with `onboarded_at = null` to /onboarding
 * before they reach any other protected route. The wizard either
 * completes (Finish button) or skips (Skip-onboarding link in
 * the header) — both stamp `onboarded_at = now()` so the gate
 * never fires again for that user.
 *
 * This spec covers:
 *   1. Existing seeded users (USER_A's `onboarded_at` is backfilled)
 *      are NOT redirected to /onboarding when they visit /dashboard.
 *   2. A user whose `onboarded_at` is reset to null IS redirected
 *      to /onboarding from any protected route.
 *   3. The wizard's Skip-onboarding header stamps `onboarded_at`
 *      and exits to /dashboard.
 *   4. The wizard's step-by-step Continue flow stamps
 *      `onboarded_at` + writes display_name, primary_goal,
 *      preferred_unit, and privacy_default on Finish.
 */

test.describe('/onboarding gate — existing user', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('seeded user with onboarded_at backfilled is not redirected', async ({
		page,
	}) => {
		await page.goto('/dashboard');
		// Stay on /dashboard, no redirect to /onboarding. A regression
		// here would mean every existing user is forced through
		// onboarding again — the migration's backfill is the contract
		// that prevents this.
		await expect(page).toHaveURL(/\/dashboard$/, { timeout: 5_000 });
	});
});

test.describe('/onboarding gate — user whose onboarded_at is null', () => {
	// We borrow USER_A but flip `onboarded_at` to null in beforeEach
	// + restore in afterEach. Avoids minting a saga user (which the
	// fixture admin-creates with onboarded_at = now() so it skips
	// the wizard by design).
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ onboarded_at: null })
			.eq('id', USER_A.id);
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({ onboarded_at: new Date().toISOString() })
			.eq('id', USER_A.id);
	});

	test('protected route redirects to /onboarding when onboarded_at is null', async ({
		page,
	}) => {
		await page.goto('/dashboard');
		await page.waitForURL(/\/onboarding/, { timeout: 10_000 });
		await expect(
			page.getByRole('heading', { name: /What should we call you/i })
		).toBeVisible({ timeout: 5_000 });
	});

	test('Skip-onboarding header link stamps onboarded_at and exits to /dashboard', async ({
		page,
	}) => {
		// 45s test-level budget — exceeds the 30s default to leave
		// room for the 20s waitForURL plus the parallelised supabase
		// writes plus the full-page navigation. The writes run inside
		// the page handler, then the page does a full reload, then
		// the new page bootstraps auth + the layout renders. Under
		// CI load (multiple shards on one runner) the cumulative
		// budget needs the extra slack.
		test.setTimeout(45_000);
		await page.goto('/onboarding');
		await expect(
			page.getByRole('heading', { name: /What should we call you/i })
		).toBeVisible({ timeout: 5_000 });

		await page.getByRole('button', { name: 'Skip onboarding' }).click();
		// 20s budget covers the parallelised user_settings +
		// user_profiles writes + the full page navigation under CI
		// load. The page uses `window.location.href = '/dashboard'`
		// (not `goto`) so the navigation is a full page reload, not
		// a client-side route change — that re-bootstraps auth from
		// the cookie which is what defeats the layout's onboarding
		// gate race. Two CI runs (26583136874 + 26584629824) tripped
		// the previous 10s budget under typical load.
		await page.waitForURL(/\/dashboard/, { timeout: 20_000 });

		// Verify `onboarded_at` was actually written, not just a
		// client-side navigation.
		const admin = getAdminClient();
		const { data } = await admin
			.from('user_profiles')
			.select('onboarded_at')
			.eq('id', USER_A.id)
			.maybeSingle();
		expect(data?.onboarded_at).not.toBeNull();
	});

	test('step-by-step Continue flow writes the answers and exits to /dashboard', async ({
		page,
	}) => {
		// 45s test-level budget — same reason as the sibling Skip
		// test above (full-page nav after parallelised writes under
		// CI load).
		test.setTimeout(45_000);
		await page.goto('/onboarding');

		// Step 1 — display name
		await expect(
			page.getByRole('heading', { name: /What should we call you/i })
		).toBeVisible();
		await page.getByLabel('Display name').fill('E2E Onboarded');
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 2 — units (default = km; switch to mi to verify a write)
		await expect(
			page.getByRole('heading', { name: /Kilometres or miles/i })
		).toBeVisible();
		await page.getByRole('radio', { name: /Miles/ }).click();
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 3 — goal
		await expect(
			page.getByRole('heading', { name: /main goal/i })
		).toBeVisible();
		await page.getByRole('radio', { name: /Run a 10K/i }).click();
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 4 — about you (skip to keep the test focused)
		await expect(
			page.getByRole('heading', { name: /A bit about you/i })
		).toBeVisible();
		await page.getByRole('button', { name: 'Skip' }).click();

		// Step 5 — privacy
		await expect(
			page.getByRole('heading', { name: /Who can see your runs/i })
		).toBeVisible();
		await page.getByRole('radio', { name: /Private/i }).click();
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 6 — notifications (skip; CDP-tier consent flow needs a
		// real Notification permission, out of scope for the wizard
		// pin)
		await expect(
			page.getByRole('heading', { name: /Notifications/i })
		).toBeVisible();
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 7 — done
		await expect(
			page.getByRole('heading', { name: /All set/i })
		).toBeVisible();
		await page.getByRole('button', { name: 'Open dashboard' }).click();

		// 20s for the same reason as the sibling Skip-onboarding
		// test above — full page nav after parallelised writes.
		await page.waitForURL(/\/dashboard/, { timeout: 20_000 });

		// Verify the writes landed.
		const admin = getAdminClient();
		const { data: profile } = await admin
			.from('user_profiles')
			.select('display_name, preferred_unit, onboarded_at')
			.eq('id', USER_A.id)
			.maybeSingle();
		expect(profile?.display_name).toBe('E2E Onboarded');
		expect(profile?.preferred_unit).toBe('mi');
		expect(profile?.onboarded_at).not.toBeNull();

		const { data: settings } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		const p = (settings?.prefs ?? {}) as Record<string, unknown>;
		expect(p.preferred_unit).toBe('mi');
		expect(p.primary_goal).toBe('10k');
		expect(p.privacy_default).toBe('private');

		// Clean up the writes so other specs in the suite see USER_A
		// in its seeded state (display_name = Jared Howard, etc).
		await admin
			.from('user_profiles')
			.update({
				display_name: 'Jared Howard',
				preferred_unit: 'mi',
			})
			.eq('id', USER_A.id);
	});
});
