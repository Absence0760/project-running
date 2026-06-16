import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { switchRunsToAllTime } from '../fixtures/helpers';
import { USER_A } from '../fixtures/users';

/**
 * Onboarding → first activity → dashboard-reflects-it journey. Heavier
 * than onboarding/wizard.spec.ts (which pins the wizard in isolation):
 * this threads a freshly-onboarded user from the wizard's final step
 * STRAIGHT into logging their first run and then verifies that one run
 * propagates across every post-onboarding surface — the /runs list, the
 * dashboard recent-runs panel, and the dashboard This-Week strip —
 * exercising the seams between onboarding, run creation, and the
 * dashboard rather than any single screen.
 *
 *   1. USER_A's `onboarded_at` is reset to null (beforeEach), so the
 *      layout gate (apps/web/src/routes/+layout.svelte) redirects any
 *      protected route to /onboarding — the real new-user condition.
 *      We borrow the seed user rather than minting a fresh signup
 *      because the fixture admin-creates saga users with
 *      `onboarded_at = now()` (they skip the wizard by design), and the
 *      whole suite mints auth once in globalSetup — wizard.spec.ts
 *      follows the same borrow-and-restore shape.
 *   2. /dashboard bounces to /onboarding; the step-by-step Continue
 *      flow sets units (mi), a goal (10K), a private privacy default,
 *      and finishes. The wizard does a FULL-PAGE nav to /dashboard
 *      (window.location.href, not goto) so the layout's onboarding
 *      $effect can't race the auth refresh — see the wizard page's
 *      navigateToDashboard() comment.
 *   3. Backend cross-check: `onboarded_at` is now stamped (the gate
 *      won't fire again) and the wizard's answers landed in the prefs
 *      bag + profile.
 *   4. The just-onboarded user logs their FIRST run via the /runs
 *      Add-run modal (RunEditor → createManualRun). RunEditor prefills
 *      `started_at` to NOW (nowLocalIso()), so the row lands in the
 *      current calendar week — the precondition for the This-Week strip
 *      assertion in step 7. createManualRun redirects to /runs/<id>.
 *   5. The run appears in the /runs list (All-time filter).
 *   6. /dashboard recent-runs panel shows the run (the `a.run-row`
 *      links to /runs/<id>, so we match on the href suffix).
 *   7. The dashboard This-Week strip (ThisWeekStrip.svelte) reflects the
 *      run: because it started today, exactly one of the seven day
 *      cells carries the `.logged` class — the strip is the "your week
 *      so far" ribbon that a brand-new run must light up.
 *   8. Backend cross-check on the run row (owner + this-week timestamp),
 *      then the run is deleted in finally so the seed user is left
 *      pristine for sibling specs on this serial shard.
 *
 * USER_A is the shared seed user, so beforeEach snapshots every profile
 * + prefs field the wizard touches and afterEach restores them — same
 * discipline as wizard.spec.ts, otherwise the km-based plans specs (and
 * the seed baseline of display_name = "Jared Howard") would see drift.
 */

const uniqueText = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test.describe('onboarding → first run → dashboard journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let savedProfile: {
		display_name: string | null;
		preferred_unit: string | null;
		onboarded_at: string | null;
	} | null = null;
	let savedPrefs: Record<string, unknown> | null = null;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		const { data: prof } = await admin
			.from('user_profiles')
			.select('display_name, preferred_unit, onboarded_at')
			.eq('id', USER_A.id)
			.single();
		savedProfile = prof ?? null;
		const { data: settings } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		savedPrefs = (settings?.prefs as Record<string, unknown> | null) ?? null;

		// Reset to the fresh-signup condition so the layout gate routes
		// us through /onboarding. The lock trigger (20261118) permits a
		// direct null write to onboarded_at.
		await admin
			.from('user_profiles')
			.update({ onboarded_at: null })
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
			})
			.eq('id', USER_A.id);
		if (savedPrefs) {
			await admin
				.from('user_settings')
				.update({ prefs: savedPrefs })
				.eq('user_id', USER_A.id);
		}
	});

	test('new user completes onboarding, logs a first run, and the dashboard reflects it', async ({
		page,
	}) => {
		// 60s budget: the wizard's full-page nav (after parallelised
		// writes, under CI load — wizard.spec.ts uses 45s for the wizard
		// alone) PLUS a run create + three surface verifications.
		test.setTimeout(60_000);
		const admin = getAdminClient();
		const runNotes = uniqueText('e2e-onboarding-first-run');

		// Captured from the create redirect so every later surface
		// addresses the SAME run, and drives best-effort teardown.
		let runId = '';

		try {
			// ── 1-2. The gate routes to /onboarding; complete the wizard ──
			await test.step('a null-onboarded_at user is gated into the wizard and completes it', async () => {
				await page.goto('/dashboard');
				await page.waitForURL(/\/onboarding/, { timeout: 10_000 });

				// Step 1 — display name. Use a unique name so the write is
				// observable and can't collide with the seed value.
				await expect(
					page.getByRole('heading', { name: /What should we call you/i })
				).toBeVisible({ timeout: 5_000 });
				await page.getByLabel('Display name').fill('E2E First-Run');
				await page.getByRole('button', { name: 'Continue' }).click();

				// Step 2 — units. Default is km (or the locale default); pick
				// Miles to make the write observable downstream.
				await expect(
					page.getByRole('heading', { name: /Kilometres or miles/i })
				).toBeVisible();
				await page.getByRole('radio', { name: /Miles/ }).click();
				await page.getByRole('button', { name: 'Continue' }).click();

				// Step 3 — goal.
				await expect(
					page.getByRole('heading', { name: /main goal/i })
				).toBeVisible();
				await page.getByRole('radio', { name: /Run a 10K/i }).click();
				await page.getByRole('button', { name: 'Continue' }).click();

				// Step 4 — about you. Skip to keep the run-propagation focus.
				// `exact` disambiguates the per-step "Skip" from the header
				// "Skip onboarding".
				await expect(
					page.getByRole('heading', { name: /A bit about you/i })
				).toBeVisible();
				await page.getByRole('button', { name: 'Skip', exact: true }).click();

				// Step 5 — privacy. Pick Private so the first run we log a few
				// steps later isn't silently public.
				await expect(
					page.getByRole('heading', { name: /Who can see your runs/i })
				).toBeVisible();
				await page.getByRole('radio', { name: /Private/i }).click();
				await page.getByRole('button', { name: 'Continue' }).click();

				// Step 6 — notifications. Continue past (CDP-tier permission
				// is out of scope, same as wizard.spec.ts).
				await expect(
					page.getByRole('heading', { name: /Notifications/i })
				).toBeVisible();
				await page.getByRole('button', { name: 'Continue' }).click();

				// Step 7 — done. The "Open dashboard" button persists the
				// answers + stamps onboarded_at, then full-page-navs.
				await expect(
					page.getByRole('heading', { name: /All set/i })
				).toBeVisible();
				await page.getByRole('button', { name: 'Open dashboard' }).click();

				// 20s for the full-page nav after parallelised writes — same
				// budget wizard.spec.ts proved out under CI load.
				await page.waitForURL(/\/dashboard/, { timeout: 20_000 });
			});

			// ── 3. The wizard's writes landed (gate won't re-fire) ──────
			await test.step('onboarding-completed flag + answers are persisted', async () => {
				const { data: profile } = await admin
					.from('user_profiles')
					.select('display_name, preferred_unit, onboarded_at')
					.eq('id', USER_A.id)
					.maybeSingle();
				expect(profile?.onboarded_at).not.toBeNull();
				expect(profile?.display_name).toBe('E2E First-Run');
				expect(profile?.preferred_unit).toBe('mi');

				const { data: settings } = await admin
					.from('user_settings')
					.select('prefs')
					.eq('user_id', USER_A.id)
					.maybeSingle();
				const p = (settings?.prefs ?? {}) as Record<string, unknown>;
				expect(p.primary_goal).toBe('10k');
				expect(p.privacy_default).toBe('private');
			});

			// ── 4. Log the first run via the /runs Add-run modal ────────
			await test.step('the onboarded user logs their first run', async () => {
				await page.goto('/runs');

				// A just-onboarded user may have an empty list, so don't wait
				// for an existing card — go straight for the Add-run button.
				await page.getByRole('button', { name: '+ Add run' }).click();

				// RunEditor: started_at prefills to NOW (nowLocalIso) — leave
				// it so the row lands in the current calendar week, which is
				// what the This-Week strip assertion (step 7) depends on. The
				// number inputs are distance (#0), duration-min (#1),
				// duration-sec (#2). The single <textarea> is the run notes.
				await page.locator('input[type="number"]').first().fill('5'); // distance (mi pref)
				await page.locator('input[type="number"]').nth(1).fill('30'); // duration min
				await page.locator('textarea').fill(runNotes);

				await page.locator('form button[type="submit"]').click();

				// createManualRun → handleRunCreated does goto('/runs/<id>').
				await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 10_000 });
				runId = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];

				// Settle the INSERT before the service-role read.
				await page.waitForLoadState('networkidle');
				const { data: row } = await admin
					.from('runs')
					.select('user_id, distance_m')
					.eq('id', runId)
					.single();
				expect(row?.user_id).toBe(USER_A.id);
				expect((row?.distance_m ?? 0) > 0).toBe(true);
			});

			// ── 5. The run shows in the /runs list ──────────────────────
			await test.step('the first run appears in the /runs list', async () => {
				await page.goto('/runs');
				await switchRunsToAllTime(page);
				await expect(
					page.locator(`.run-card[href$="${runId}"]`)
				).toBeVisible({ timeout: 10_000 });
			});

			// ── 6-7. The dashboard reflects the run ─────────────────────
			await test.step('the dashboard recent-runs + This-Week strip reflect the run', async () => {
				await page.goto('/dashboard');

				// Recent-runs panel: each row is an `a.run-row` linking to
				// /runs/<id>, so match on the href suffix.
				await expect(
					page.locator(`a.run-row[href$="/runs/${runId}"]`)
				).toBeVisible({ timeout: 10_000 });

				// This-Week strip: the run started today, so exactly one day
				// cell carries the `.logged` class. The strip windows on the
				// REAL calendar week containing now (current_week.ts), and a
				// fresh seed user has at most this single run inside it. Use
				// >= 1 rather than == 1 to stay robust if a sibling run on the
				// shared user happens to fall in the same week — the contract
				// under test is "the new run lights up the strip", not the
				// exact count.
				const strip = page.locator('.week-strip');
				await expect(strip).toBeVisible({ timeout: 10_000 });
				await expect(
					strip.locator('.day.logged').first()
				).toBeVisible({ timeout: 10_000 });
			});

			// ── 8. Backend cross-check: the run is in the current week ──
			await test.step('the run row is owned by the user and falls in the current week', async () => {
				const { data: row } = await admin
					.from('runs')
					.select('user_id, started_at, source')
					.eq('id', runId)
					.single();
				expect(row?.user_id).toBe(USER_A.id);
				expect(row?.source).toBe('app');
				// started_at is "now" ± the wizard/create wall-clock — assert
				// it's within the last hour so the This-Week placement is
				// genuinely "today", not a stale fixture row.
				const ageMs = Date.now() - new Date(row!.started_at).getTime();
				expect(ageMs).toBeGreaterThanOrEqual(0);
				expect(ageMs).toBeLessThan(60 * 60 * 1000);
			});
		} finally {
			// Safety net: sweep the created run regardless of where the
			// journey failed, so the shared seed user is left pristine.
			if (runId) {
				await admin.from('runs').delete().eq('id', runId);
			}
		}
	});
});
