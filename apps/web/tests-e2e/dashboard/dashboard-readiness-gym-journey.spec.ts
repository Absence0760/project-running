import { expect, test, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun, setUserSetting } from '../fixtures/simulate';

/**
 * End-to-end readiness journey: gym sessions folding into the dashboard
 * fitness/fatigue/form (CTL/ATL/TSB) trio — the cross-modal load
 * computation the round-2 dashboard-drilldown journey did NOT cover.
 *
 * The sibling `dashboard/gym-readiness.spec.ts` pins the *disclosure*
 * (the Fitness card's "factored in" ↔ "excluded" note). This journey
 * pins the slice it leaves untested: that the gym load actually MOVES
 * the readiness numbers, and that the `exclude_gym_from_readiness`
 * pref is a recoverable, run-only opt-out.
 *
 * Grounding: lifts feed the SAME daily-stress series as runs
 * (lift_load.ts#liftsFromSetHistory → training_load.ts
 * #computeTrainingLoadSeries). A lift adds positive `liftStress` on its
 * day → daily stress rises → the ATL EWMA (7-day halflife) climbs, and
 * TSB = ctl − atl falls. So including a recent heavy gym session raises
 * ATL (fatigue) and lowers TSB (form) vs the run-only curve; the
 * `exclude_gym_from_readiness=true` opt-out (decisions §134, settings.md
 * universal pref default false) drops `readinessLifts` to [] and the
 * run-only curve is recovered byte-for-byte (separable provenance,
 * training_load.ts § "Separable provenance").
 *
 * Walk: log-run+gym → readiness-includes-gym (ATL↑, TSB↓, "factored in"
 * note) → toggle-pref → readiness-excludes-gym (ATL back down, TSB back
 * up, "excluded" note). An ephemeral saga user gives a clean readiness
 * canvas (the seeded user already carries gym + run rows that would
 * muddy the direction-of-change assertion).
 *
 * The training-load CURVE itself is an SVG (TrainingLoadChart) — this
 * spec never reads chart paint geometry. It asserts on the Fitness
 * card's numeric `.fitness-value` cells (CTL/ATL/TSB, dashboard
 * +page.svelte lines 1164-1195) and the `data-testid="gym-readiness-note"`
 * disclosure (lines 1205-1215).
 */

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
	);
}

/** Local-date ISO for `daysAgo` days back, midday-anchored so it lands
 *  squarely on its own local calendar day regardless of tz offset. */
function daysAgoIso(daysAgo: number): string {
	const d = new Date();
	d.setHours(12, 0, 0, 0);
	d.setDate(d.getDate() - daysAgo);
	return d.toISOString();
}

/** Read the numeric value out of the Fitness-card metric whose label
 *  matches `labelRe` (CTL/ATL/TSB). The card renders one
 *  `.fitness-metric` per metric; each has a `.fitness-label` + a
 *  `.fitness-value`. TSB carries a leading sign which parseFloat eats. */
async function readFitnessMetric(page: Page, labelRe: RegExp): Promise<number> {
	const metric = page
		.locator('.fitness-card .fitness-metric')
		.filter({ has: page.locator('.fitness-label', { hasText: labelRe }) });
	await expect(metric).toBeVisible({ timeout: 10_000 });
	const raw = (await metric.locator('.fitness-value').textContent())?.trim() ?? '';
	const n = parseFloat(raw.replace('+', ''));
	expect(Number.isFinite(n), `metric ${labelRe} parsed from "${raw}"`).toBe(true);
	return n;
}

test.describe('dashboard readiness — gym sessions fold into CTL/ATL/TSB', () => {
	test('log run + gym → readiness includes gym fatigue → toggle pref → readiness excludes it', async ({
		browser,
	}) => {
		const admin = getAdminClient();
		let users: SagaUser[] = [];
		const runIds: string[] = [];
		const workoutIds: string[] = [];

		try {
			users = await createSagaUsers(1, { displayNames: ['Readiness Gym'] });
			const subject = users[0];

			// ── Setup: a small run-only base, then a heavy recent gym block ──
			await test.step('plant recent runs (run-only base) + heavy recent gym sessions', async () => {
				// Spread modest daily-ish runs across the last fortnight so the
				// EWMAs reach a non-zero, settled run-only baseline (loadNow is
				// only non-null once CTL/ATL > 0; computeTrainingLoadSeries warms
				// up first, so any qualifying run in-window yields a real curve).
				for (let d = 1; d <= 12; d++) {
					if (d % 2 === 0) continue; // every other day — 6 easy runs
					runIds.push(
						await insertRun({
							user_id: subject.id,
							started_at: daysAgoIso(d),
							distance_m: 8000,
							duration_s: 2700,
						}),
					);
				}

				// Two heavy gym sessions, today + yesterday, so the lift load
				// lands inside the 7-day ATL window where it moves fatigue the
				// most. High tonnage (5×5 @ 100 kg + 5×5 @ 80 kg ≈ 4,500 kg per
				// session) so the contribution is unmistakable but still under
				// kLiftStressCap (150) — well clear of saturation.
				for (const ago of [0, 1]) {
					const { data: w, error: wErr } = await admin
						.from('gym_workouts')
						.insert({
							user_id: subject.id,
							title: 'Heavy lower',
							started_at: daysAgoIso(ago),
							duration_s: 3600,
						})
						.select('id')
						.single();
					if (wErr || !w) throw new Error(`gym_workouts insert: ${wErr?.message}`);
					workoutIds.push(w.id as string);
					const sets = [] as {
						workout_id: string;
						set_index: number;
						exercise_name: string;
						reps: number;
						weight_kg: number;
						rpe: number;
					}[];
					for (let i = 0; i < 5; i++)
						sets.push({ workout_id: w.id, set_index: i, exercise_name: 'Back squat', reps: 5, weight_kg: 100, rpe: 8 });
					for (let i = 0; i < 5; i++)
						sets.push({ workout_id: w.id, set_index: 5 + i, exercise_name: 'Romanian deadlift', reps: 5, weight_kg: 80, rpe: 8 });
					const { error: sErr } = await admin.from('gym_sets').insert(sets);
					if (sErr) throw new Error(`gym_sets insert: ${sErr.message}`);
				}

				// Start from the documented default (universal pref, default
				// false) so the first dashboard load includes gym in readiness.
				await setUserSetting(subject.id, 'exclude_gym_from_readiness', false);
			});

			const ctx = await browser.newContext({ storageState: subject.storageStatePath });
			// Saga users have not accepted the cookie banner — pre-accept so the
			// GDPR banner can't float over the Fitness card.
			await ctx.addInitScript(setConsentAccepted);
			const page = await ctx.newPage();

			let atlIncluded = 0;
			let tsbIncluded = 0;
			let ctlIncluded = 0;

			try {
				// ── Phase 1: gym IS in the readiness curve ──────────────────
				await test.step('readiness includes gym — note says "factored in", capture ATL/TSB', async () => {
					await page.goto('/dashboard');

					// The transparency note confirms a recent lift is moving the
					// curve (hasRecentLift && !excludeGymFromReadiness).
					const note = page.getByTestId('gym-readiness-note');
					await expect(note).toBeVisible({ timeout: 10_000 });
					await expect(note).toContainText(/factored into your fatigue/i);

					ctlIncluded = await readFitnessMetric(page, /CTL/i);
					atlIncluded = await readFitnessMetric(page, /ATL/i);
					tsbIncluded = await readFitnessMetric(page, /TSB/i);

					// Sanity: a real, settled curve (runs alone put CTL/ATL > 0).
					expect(ctlIncluded).toBeGreaterThan(0);
					expect(atlIncluded).toBeGreaterThan(0);
				});

				// ── Phase 2: opt out — gym drops from the readiness curve ────
				await test.step('toggle exclude_gym_from_readiness → note flips to "excluded"', async () => {
					await setUserSetting(subject.id, 'exclude_gym_from_readiness', true);
					await page.goto('/dashboard');
					const note = page.getByTestId('gym-readiness-note');
					await expect(note).toBeVisible({ timeout: 10_000 });
					await expect(note).toContainText(/excluded/i);
				});

				// ── Phase 3: the numbers prove the gym load was real ────────
				await test.step('excluding gym lowers ATL (fatigue) and raises TSB (form)', async () => {
					const ctlExcluded = await readFitnessMetric(page, /CTL/i);
					const atlExcluded = await readFitnessMetric(page, /ATL/i);
					const tsbExcluded = await readFitnessMetric(page, /TSB/i);

					// Gym load adds positive daily stress → ATL climbs, TSB
					// (ctl − atl) falls. Dropping it must therefore LOWER ATL and
					// RAISE TSB vs the gym-included readiness. This is the whole
					// point of the pref, and the assertion the disclosure-only
					// sibling spec can't make.
					expect(atlExcluded).toBeLessThan(atlIncluded);
					expect(tsbExcluded).toBeGreaterThan(tsbIncluded);

					// CTL (42-day halflife) also drops a little when lifts leave,
					// but ATL moves far more — so form (TSB) genuinely improves,
					// it isn't a CTL artefact. Pin the dominant effect: the
					// ATL drop exceeds the CTL drop.
					expect(atlIncluded - atlExcluded).toBeGreaterThan(ctlIncluded - ctlExcluded);
				});

				// ── Phase 4: recoverable — flip back, gym is folded in again ─
				await test.step('revert pref → gym is folded back into the readiness curve', async () => {
					await setUserSetting(subject.id, 'exclude_gym_from_readiness', false);
					await page.goto('/dashboard');
					const note = page.getByTestId('gym-readiness-note');
					await expect(note).toBeVisible({ timeout: 10_000 });
					await expect(note).toContainText(/factored into your fatigue/i);

					// Same canvas, pref restored → the gym-included numbers return
					// (the run-only ↔ run+gym curve is fully separable + recoverable).
					expect(await readFitnessMetric(page, /ATL/i)).toBeCloseTo(atlIncluded, 0);
					expect(await readFitnessMetric(page, /TSB/i)).toBeCloseTo(tsbIncluded, 0);
				});
			} finally {
				await ctx.close();
			}
		} finally {
			// Clean up every planted row + the pref, then the saga user (CASCADE
			// also strips any straggler gym_sets / runs, but be explicit).
			for (const id of workoutIds) {
				await admin.from('gym_workouts').delete().eq('id', id);
			}
			for (const id of runIds) {
				await admin.from('runs').delete().eq('id', id);
			}
			if (users.length > 0) {
				// The pref lives on the saga user's user_settings row, dropped by
				// the auth.users CASCADE in deleteSagaUsers — no separate
				// clearUserSettingKey needed once the user is gone.
				await deleteSagaUsers(users);
			}
		}
	});
});
