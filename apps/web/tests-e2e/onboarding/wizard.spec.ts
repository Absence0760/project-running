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

	// USER_A is the shared seed user. The Continue-flow test completes the
	// wizard, which writes preferred_unit ('mi'), display_name, primary_goal
	// + privacy_default to the profile + settings. Other specs on this shard
	// assume the seed baseline (notably the km-based plans tests), so snapshot
	// the mutated rows in beforeEach and restore them in afterEach — leaving
	// the user pristine regardless of which fields the wizard touched.
	let savedProfile: { display_name: string | null; preferred_unit: string | null; onboarded_at: string | null; date_of_birth: string | null; health_data_consent_at: string | null; gender: string | null } | null = null;
	let savedPrefs: Record<string, unknown> | null = null;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		const { data: prof } = await admin
			.from('user_profiles')
			.select('display_name, preferred_unit, onboarded_at, date_of_birth, health_data_consent_at, gender')
			.eq('id', USER_A.id)
			.single();
		savedProfile = prof ?? null;
		const { data: settings } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		savedPrefs = (settings?.prefs as Record<string, unknown> | null) ?? null;

		// Reset the Art 9 fields too: USER_A is shared, and sibling specs (or
		// the seed) may have stamped consent/gender. The DOB-without-consent
		// test asserts these stay null, so it must START from null. The lock
		// trigger (20261118) permits a direct null write.
		await admin
			.from('user_profiles')
			.update({ onboarded_at: null, health_data_consent_at: null, gender: null })
			.eq('id', USER_A.id);
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('user_profiles')
			.update({
				onboarded_at: savedProfile?.onboarded_at ?? new Date().toISOString(),
				display_name: savedProfile?.display_name ?? null,
				preferred_unit: savedProfile?.preferred_unit ?? 'km',
				date_of_birth: savedProfile?.date_of_birth ?? null,
				health_data_consent_at: savedProfile?.health_data_consent_at ?? null,
				gender: savedProfile?.gender ?? null,
			})
			.eq('id', USER_A.id);
		if (savedPrefs) {
			await admin.from('user_settings').update({ prefs: savedPrefs }).eq('user_id', USER_A.id);
		}
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

		// Step 3 — goal. Every option renders its localized
		// `onboarding.goal.<value>` label (not the raw i18n key) — guards
		// the regression where the labels were hard-coded English in the
		// helper and bypassed i18n. en labels here; the parity test pins
		// the other five locales.
		await expect(
			page.getByRole('heading', { name: /main goal/i })
		).toBeVisible();
		for (const label of [
			'Stay fit + healthy',
			'Lose weight',
			'Run a 5K',
			'Run a 10K',
			'Run a half marathon',
			'Run a marathon',
		]) {
			await expect(
				page.getByRole('radio', { name: label, exact: true })
			).toBeVisible();
		}
		await page.getByRole('radio', { name: 'Run a 10K', exact: true }).click();
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 4 — about you (skip to keep the test focused). `exact`
		// disambiguates the per-step "Skip" from the header "Skip onboarding".
		await expect(
			page.getByRole('heading', { name: /A bit about you/i })
		).toBeVisible();
		await page.getByRole('button', { name: 'Skip', exact: true }).click();

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

		// Step 7 — done. Because a goal (10K) was chosen, the goal-keyed
		// "Create my training plan" CTA is offered alongside the neutral
		// dashboard exit (runner-new discoverability nudge).
		await expect(
			page.getByRole('heading', { name: /All set/i })
		).toBeVisible();
		await expect(
			page.getByRole('button', { name: 'Create my training plan' })
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

	test('the body-weight step honours the chosen distance unit — miles asks for lbs and stores canonical kg', async ({
		page,
	}) => {
		// Regression: step 4 used to ask for weight in kg unconditionally,
		// while step 2 auto-selects miles for US/GB/LR/MM runners. An
		// imperial runner typing "154" (thinking pounds) had it stored as
		// 154 KG — a 340-lb body weight that poisons the TDEE / hydration
		// math consuming body_weight_kg. The fix derives the weight unit
		// from the distance choice, labels + parses in that unit (storage
		// stays canonical kg), and persists weight_unit so Settings agrees.
		test.setTimeout(45_000);
		await page.goto('/onboarding');

		// Step 1 — display name
		await page.getByLabel('Display name').fill('E2E Weight Unit');
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 2 — pick Miles, which flips the weight step to lbs.
		await expect(
			page.getByRole('heading', { name: /Kilometres or miles/i })
		).toBeVisible();
		await page.getByRole('radio', { name: /Miles/ }).click();
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 3 — goal (leave unset; skip via Continue).
		await expect(page.getByRole('heading', { name: /main goal/i })).toBeVisible();
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 4 — about you: the weight field now reads lbs, not kg.
		await expect(
			page.getByRole('heading', { name: /A bit about you/i })
		).toBeVisible();
		await expect(page.getByText(/Body weight in lbs/i)).toBeVisible();
		// Enter 154 lbs → 154 / 2.2046226218 = 69.85 kg canonical.
		await page.getByLabel(/Body weight in lbs/i).fill('154');
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 5 — privacy
		await page.getByRole('radio', { name: /Private/i }).click();
		await page.getByRole('button', { name: 'Continue' }).click();
		// Step 6 — notifications
		await page.getByRole('button', { name: 'Continue' }).click();
		// Step 7 — finish
		await page.getByRole('button', { name: 'Open dashboard' }).click();
		await page.waitForURL(/\/dashboard/, { timeout: 20_000 });

		const admin = getAdminClient();
		const { data: settings } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		const p = (settings?.prefs ?? {}) as Record<string, unknown>;
		// The chosen distance unit propagated to the weight_unit pref…
		expect(p.weight_unit).toBe('lbs');
		// …and the typed lbs value was stored as canonical kg, NOT verbatim.
		expect(p.body_weight_kg as number).toBeCloseTo(69.9, 1);
	});

	test('DOB entered without the health-data consent still writes user_profiles.date_of_birth (family-club minor-exclusion floor)', async ({
		page,
	}) => {
		// persona round-5 family-club: the under-18 minor-exclusion in
		// search_user_profiles keys off user_profiles.date_of_birth. The
		// onboarding DOB used to be Art 9-consent-gated, so a child who
		// declined the health-data checkbox kept a NULL DOB and stayed
		// fully discoverable. The fix decouples the DOB column write (a
		// child-safety floor) from the Art 9 consent (which still gates
		// gender + the consent timestamp). This pins that a DOB supplied
		// WITHOUT ticking consent lands on the column anyway.
		test.setTimeout(45_000);
		await page.goto('/onboarding');

		// Step 1 — display name
		await page.getByLabel('Display name').fill('DOB No Consent');
		await page.getByRole('button', { name: 'Continue' }).click();
		// Step 2 — units
		await page.getByRole('button', { name: 'Continue' }).click();
		// Step 3 — goal
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 4 — about you: fill DOB, leave the consent checkbox UNticked.
		await expect(
			page.getByRole('heading', { name: /A bit about you/i })
		).toBeVisible();
		await page.getByLabel(/Date of birth/i).fill('2010-06-15');
		// Do NOT tick the consent row.
		await page.getByRole('button', { name: 'Continue' }).click();

		// Step 5 — privacy
		await page.getByRole('radio', { name: /Private/i }).click();
		await page.getByRole('button', { name: 'Continue' }).click();
		// Step 6 — notifications
		await page.getByRole('button', { name: 'Continue' }).click();
		// Step 7 — finish
		await page.getByRole('button', { name: 'Open dashboard' }).click();
		await page.waitForURL(/\/dashboard/, { timeout: 20_000 });

		const admin = getAdminClient();
		const { data } = await admin
			.from('user_profiles')
			.select('date_of_birth, health_data_consent_at, gender')
			.eq('id', USER_A.id)
			.maybeSingle();
		// DOB persisted despite no consent — the safety floor has its input.
		expect(data?.date_of_birth).toBe('2010-06-15');
		// Art 9 fields stay null without the consent tick.
		expect(data?.health_data_consent_at).toBeNull();
		expect(data?.gender).toBeNull();
	});

	test('finishing with every optional section blank exits to /dashboard and a revisit does not bounce back to step 1 (#227)', async ({
		page,
	}) => {
		// Regression pin for issue #227: skipping every optional section
		// must never block the onboarded_at stamp — "Open dashboard" means
		// the wizard is done. The revisit at the end proves the stamp
		// actually landed server-side (the gate reads it on every load),
		// not just that the client navigated once.
		test.setTimeout(45_000);
		await page.goto('/onboarding');

		await expect(
			page.getByRole('heading', { name: /What should we call you/i })
		).toBeVisible();
		// Steps 1-6: advance without entering or choosing anything.
		for (let i = 0; i < 6; i++) {
			await page.getByRole('button', { name: 'Continue' }).click();
		}
		// Step 7 — no goal was chosen, so only the neutral exit renders.
		await expect(page.getByRole('heading', { name: /All set/i })).toBeVisible();
		await expect(
			page.getByRole('button', { name: 'Create my training plan' })
		).toHaveCount(0);
		await page.getByRole('button', { name: 'Open dashboard' }).click();
		await page.waitForURL(/\/dashboard/, { timeout: 20_000 });

		// The stamp landed server-side — the layout gate's input.
		const admin = getAdminClient();
		const { data } = await admin
			.from('user_profiles')
			.select('onboarded_at')
			.eq('id', USER_A.id)
			.maybeSingle();
		expect(data?.onboarded_at).not.toBeNull();

		// A fresh load of a protected route stays put — no bounce back to
		// the wizard's step 1.
		await page.goto('/dashboard');
		await expect(page).toHaveURL(/\/dashboard$/, { timeout: 5_000 });
	});
});
