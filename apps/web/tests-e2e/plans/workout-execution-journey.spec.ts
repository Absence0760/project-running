import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan, deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Structured-workout EXECUTION → COMPLETION → PLAN-PROGRESS journey (web).
 *
 * What's built on web vs. mobile
 * ──────────────────────────────
 * The live structured-workout *execution* runner is MOBILE-ONLY. It lives
 * in `packages/run_recorder/lib/src/workout_runner.dart` (the step state
 * machine) + `apps/mobile_android/lib/widgets/workout_execution_band.dart`
 * (the in-run overlay), launched from the today-card / workout-detail
 * "Start workout" button — see docs/features/workout_execution.md and the
 * canonical-surface rule in decisions §24 (recording is a physical
 * device exception, so the live runner is additive on device, not on web).
 *
 * On WEB the equivalent end-to-end arc is "preview the planned structured
 * workout → run it for real → link the completed run back to the planned
 * workout → watch the plan's progress surface reflect it". The web
 * auto-complete-from-run write path is unwired (plans/auto-complete-from-
 * run.spec.ts), so the genuine run→workout LINKING path on web is the
 * Re-link picker on /plans/[id]/workouts/[wid] (markWorkoutCompleted with
 * a runId, fetchRelinkCandidateRuns → filterRelinkCandidates).
 *
 * The existing specs each pin one slice in isolation: workout-runner-
 * surfaces.spec.ts (structure preview + WorkoutEditor mark-done),
 * workout-relink.spec.ts (the picker's candidate rules against the SEED
 * plan), plan-progress-journey.spec.ts (full lifecycle but completes via
 * MARK-DONE, never via a linked run). None stitches "structured workout →
 * real logged run → link via picker → progress/longest-long-run/day-grid
 * propagation" into one arc. That's this spec.
 *
 * The arc, on a fresh owner-planted plan (no seed-plan mutation):
 *
 *   1. Plant a 2-build-week plan anchored to TODAY via service-role
 *      (training_plans + plan_weeks + plan_workouts): a STRUCTURED
 *      interval workout today (warmup 1.5 km + 5×1000 m @ 4:00 / 400 m
 *      jog + cooldown 1.5 km) and a long run today.
 *   2. Open the interval workout's detail page and verify the runner's
 *      "what am I about to run" half: the structure breakdown renders
 *      (warmup + repeats + cooldown rows, total ~11 km).
 *   3. Log the run for real via simulate.insertRun (the mobile recorder's
 *      job — done service-side per the simulate.ts contract).
 *   4. Link that run to the interval workout through the Re-link picker
 *      UI: seed an initial link service-side so the picker is reachable,
 *      open it, and pick our freshly-logged run. Verify the workout-
 *      detail completed-card surfaces.
 *   5. Likewise complete the long run by linking the same-day run.
 *   6. Navigate to /plans/[id] and verify the DOWNSTREAM progress
 *      propagation: the day-grid interval cell flips to .completed, the
 *      progress ring pct is non-zero and matches completed/totalActive,
 *      the phase marker renders (≥2 phases), and the "Longest long run"
 *      stat reflects the linked run's ACTUAL distance (not the planned
 *      target) — longestCompletedLongRunMetres pulls from recentRuns.
 *
 * Cleanup: service-role deletePlan (cascades weeks/workouts) + deleteRun
 * for both seeded runs in afterEach. Only this user's own planted rows are
 * touched — the seed Richmond Half plan is never read or mutated.
 */

const DAY_MS = 24 * 3600 * 1000;
const iso = (d: Date) => d.toISOString().slice(0, 10);

// 5×1000 m interval: warmup 1.5 km + 5×1000 m + 4×400 m jog recovery +
// cooldown 1.5 km. intervalTotal on the detail page = warmup + repeats
// (count × (rep + recovery)) + cooldown = 1500 + 5×(1000+400) + 1500 =
// 1500 + 7000 + 1500 = 10000 m. The detail page renders the recovery
// inside the repeats descriptor, so the rendered total is 10 km.
const INTERVAL_STRUCTURE = {
	warmup: { distance_m: 1500 },
	repeats: {
		count: 5,
		distance_m: 1000,
		pace_sec_per_km: 240,
		recovery_distance_m: 400,
		recovery_pace: 'jog'
	},
	cooldown: { distance_m: 1500 }
};

test.describe('structured workout execution → plan progress journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let plannedPlanId: string | null = null;
	const seededRunIds: string[] = [];

	test.beforeEach(async ({ context }) => {
		// Pre-accept cookie consent so the banner doesn't layer over modal
		// pointer events (same fix as workout-runner-surfaces.spec.ts).
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test.afterEach(async () => {
		for (const id of seededRunIds.splice(0)) {
			await deleteRun(id).catch(() => {});
		}
		if (plannedPlanId) {
			await deletePlan(plannedPlanId).catch(() => {});
			plannedPlanId = null;
		}
	});

	test('preview structured workout → log run → link via picker → plan progress reflects it', async ({
		page
	}) => {
		const admin = getAdminClient();
		const today = iso(new Date());

		let intervalWorkoutId = '';
		let longWorkoutId = '';

		// ── 1. Plant the plan (admin) anchored to TODAY ────────────
		await test.step('plant a 2-build-week plan with a structured interval + long run today', async () => {
			plannedPlanId = crypto.randomUUID();
			// Start the plan 2 days ago so TODAY sits inside week 0 and the
			// plan is "in progress" — gives the progress ring + phase marker
			// a real current week to render.
			const start = new Date(Date.now() - 2 * DAY_MS);
			const { error: planErr } = await admin.from('training_plans').insert({
				id: plannedPlanId,
				user_id: USER_A.id,
				name: `e2e-exec-journey ${Date.now()}`,
				// goal_event / goal_distance_m / days_per_week / source are all
				// NOT NULL on training_plans (the create wizard supplies them;
				// a direct insert must too).
				goal_event: 'distance_half',
				goal_distance_m: 21097,
				days_per_week: 4,
				source: 'manual',
				// status 'abandoned', NOT 'active': /plans/[id] loads by id and
				// its progress/adherence surfaces compute from workouts + linked
				// runs regardless of status (the detail page never gates the
				// progress UI on plan.status). But `training_plans_one_active`
				// is a DB partial-unique index (one active plan per user) and
				// USER_A's seed Richmond Half is already active, so a second
				// active plan dup-keys it on insert (the status CHECK only
				// admits active/completed/abandoned — no 'draft').
				status: 'abandoned',
				start_date: iso(start),
				end_date: iso(new Date(Date.now() + 26 * DAY_MS))
			});
			if (planErr) throw planErr;

			const week0 = crypto.randomUUID();
			const week1 = crypto.randomUUID();
			// Two DIFFERENT phases so orderedPlanPhases().length > 1 → the
			// phase marker renders (build then peak).
			const { error: weekErr } = await admin.from('plan_weeks').insert([
				{ id: week0, plan_id: plannedPlanId, week_index: 0, phase: 'build', target_volume_m: 40_000 },
				{ id: week1, plan_id: plannedPlanId, week_index: 1, phase: 'peak', target_volume_m: 44_000 }
			]);
			if (weekErr) throw weekErr;

			intervalWorkoutId = crypto.randomUUID();
			longWorkoutId = crypto.randomUUID();
			// A rest day so totalActive (kind != 'rest') is a controlled
			// denominator: 2 active workouts (interval + long) in week 0.
			const restId = crypto.randomUUID();
			const { error: woErr } = await admin.from('plan_workouts').insert([
				{
					id: intervalWorkoutId,
					week_id: week0,
					scheduled_date: today,
					kind: 'interval',
					target_distance_m: 11_000,
					target_pace_sec_per_km: 240,
					structure: INTERVAL_STRUCTURE
				},
				{
					id: longWorkoutId,
					week_id: week0,
					scheduled_date: iso(new Date(Date.now() - DAY_MS)),
					kind: 'long',
					target_distance_m: 24_000
				},
				{
					id: restId,
					week_id: week0,
					scheduled_date: iso(new Date(Date.now() - 2 * DAY_MS)),
					kind: 'rest'
				}
			]);
			if (woErr) throw woErr;
		});

		// ── 2. Structure preview (the runner's "what am I about to run") ─
		await test.step('workout-detail renders the structured-interval breakdown', async () => {
			await page.goto(`/plans/${plannedPlanId}/workouts/${intervalWorkoutId}`);
			const steps = page.locator('ol.steps li');
			await expect(steps).toHaveCount(3, { timeout: 10_000 });
			await expect(steps.nth(0).locator('.step-kind')).toHaveText('Warmup');
			await expect(steps.nth(1).locator('.step-kind')).toHaveText('Repeats');
			await expect(steps.nth(2).locator('.step-kind')).toHaveText('Cooldown');
			// Repeats descriptor: 5× · 1 km · jog recovery.
			await expect(steps.nth(1)).toContainText(/5×/);
			await expect(steps.nth(1)).toContainText(/jog/i);
			// Rendered total = warmup + 5×(rep+recovery) + cooldown = 10 km.
			await expect(page.locator('.total')).toContainText('10');
			// Not yet completed → no completed-card.
			await expect(page.locator('.completed-card')).toHaveCount(0);
		});

		// ── 3. Log the run for real (the mobile recorder's job) ────
		let intervalRunId: string | null = null;
		let longRunId: string | null = null;
		await test.step('log the interval + long runs via the recorder (simulate.insertRun)', async () => {
			// The interval session, logged today, ~11 km in ~50 min.
			intervalRunId = await insertRun({
				user_id: USER_A.id,
				started_at: `${today}T06:30:00Z`,
				distance_m: 11_050,
				duration_s: 3000,
				source: 'app',
				metadata: { activity_type: 'run' }
			});
			seededRunIds.push(intervalRunId);

			// The long run, logged yesterday — its ACTUAL distance (25.4 km)
			// deliberately differs from the planned 24 km so the "Longest
			// long run" stat below proves it reads the linked run's actual,
			// not the workout target.
			const longDate = iso(new Date(Date.now() - DAY_MS));
			longRunId = await insertRun({
				user_id: USER_A.id,
				started_at: `${longDate}T06:00:00Z`,
				distance_m: 25_400,
				duration_s: 9000,
				source: 'app',
				metadata: { activity_type: 'run' }
			});
			seededRunIds.push(longRunId);
		});

		// ── 4. Link the interval run via the Re-link picker UI ─────
		// The "Re-link" picker is only reachable once a workout is linked
		// (the detail page shows Re-link when completed_run_id is set). To
		// drive the genuine run→workout linking UI we seed an initial link
		// service-side, then MOVE it to our freshly-logged run via the
		// picker — exercising markWorkoutCompleted(runId) +
		// fetchRelinkCandidateRuns end to end.
		await test.step('link the logged interval run to the planned workout via the picker', async () => {
			// Initial throwaway link so the Re-link affordance appears.
			const seedLink = await insertRun({
				user_id: USER_A.id,
				started_at: `${today}T05:00:00Z`,
				distance_m: 11_000,
				duration_s: 3100,
				source: 'app',
				metadata: { activity_type: 'run' }
			});
			seededRunIds.push(seedLink);
			const { error: linkErr } = await admin
				.from('plan_workouts')
				.update({ completed_run_id: seedLink, completed_at: new Date().toISOString() })
				.eq('id', intervalWorkoutId);
			if (linkErr) throw linkErr;

			await page.goto(`/plans/${plannedPlanId}/workouts/${intervalWorkoutId}`);
			await expect(page.locator('.completed-card')).toBeVisible({ timeout: 10_000 });

			await page.getByRole('button', { name: 'Re-link' }).click();
			const modal = page.locator('[data-testid="relink-modal"]');
			await expect(modal).toBeVisible({ timeout: 10_000 });

			// Our freshly-logged interval run is offered (in-window, not
			// linked elsewhere). Pick it — the link moves to it.
			const target = modal.locator(`button.relink-run[data-run-id="${intervalRunId}"]`);
			await expect(target).toBeVisible({ timeout: 10_000 });
			await expect(target).not.toHaveClass(/current/);
			await target.click();

			await expect(modal).toBeHidden({ timeout: 10_000 });
			await expect(page.locator('.completed-card')).toBeVisible();

			// The link is now our logged run.
			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('plan_workouts')
							.select('completed_run_id')
							.eq('id', intervalWorkoutId)
							.maybeSingle();
						return (data as { completed_run_id: string | null } | null)?.completed_run_id;
					},
					{ timeout: 10_000 }
				)
				.toBe(intervalRunId);
		});

		// ── 5. Link the long run too ───────────────────────────────
		await test.step('link the logged long run to the planned long workout', async () => {
			// Same picker path: seed a throwaway link to surface Re-link,
			// then move it to the real long run.
			const seedLong = await insertRun({
				user_id: USER_A.id,
				started_at: `${iso(new Date(Date.now() - DAY_MS))}T05:00:00Z`,
				distance_m: 24_000,
				duration_s: 9100,
				source: 'app',
				metadata: { activity_type: 'run' }
			});
			seededRunIds.push(seedLong);
			await admin
				.from('plan_workouts')
				.update({ completed_run_id: seedLong, completed_at: new Date().toISOString() })
				.eq('id', longWorkoutId);

			await page.goto(`/plans/${plannedPlanId}/workouts/${longWorkoutId}`);
			await expect(page.locator('.completed-card')).toBeVisible({ timeout: 10_000 });
			await page.getByRole('button', { name: 'Re-link' }).click();
			const modal = page.locator('[data-testid="relink-modal"]');
			await expect(modal).toBeVisible({ timeout: 10_000 });
			const target = modal.locator(`button.relink-run[data-run-id="${longRunId}"]`);
			await expect(target).toBeVisible({ timeout: 10_000 });
			await target.click();
			await expect(modal).toBeHidden({ timeout: 10_000 });

			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('plan_workouts')
							.select('completed_run_id')
							.eq('id', longWorkoutId)
							.maybeSingle();
						return (data as { completed_run_id: string | null } | null)?.completed_run_id;
					},
					{ timeout: 10_000 }
				)
				.toBe(longRunId);
		});

		// ── 6. Plan-detail reflects the completed structured workout ─
		await test.step('plan progress surface propagates the completed linked workouts', async () => {
			await page.goto(`/plans/${plannedPlanId}`);

			// Progress ring renders and is non-zero (both active workouts now
			// linked → 2/2 = 100%, since the only non-rest workouts are the
			// interval + long).
			const ring = page.locator('.progress-ring');
			await expect(ring).toBeVisible({ timeout: 10_000 });
			const pctText = (await page.locator('.progress-ring .pct').textContent()) ?? '';
			const pct = parseInt(pctText.match(/(\d+)/)?.[1] ?? '-1', 10);
			expect(pct).toBe(100);
			// The "x / y" badge confirms the completed/active denominator.
			await expect(page.locator('.progress-ring .done')).toHaveText('2 / 2');

			// Phase marker renders (build + peak → ≥2 phases) with one active.
			const phaseSteps = page.locator('.phase-marker .phase-step');
			expect(await phaseSteps.count()).toBeGreaterThanOrEqual(2);
			await expect(page.locator('.phase-marker .phase-step.active')).toBeVisible();

			// The day-grid interval cell flipped to .completed (carries the
			// Interval label) — the downstream of linking the run.
			const intervalCell = page.locator('.day.completed', {
				hasText: /Interval/i
			});
			await expect(intervalCell.first()).toBeVisible({ timeout: 10_000 });

			// "Longest long run" reflects the LINKED RUN's actual distance
			// (25.4 km), not the planned target (24 km) —
			// longestCompletedLongRunMetres prefers actualById from
			// recentRuns. The km-preferring seed user formats it as "25.4 km".
			const longest = page.locator('.stat-chip[title="Longest long run"] .stat-value');
			await expect(longest).toBeVisible({ timeout: 10_000 });
			await expect(longest).toContainText(/25\.4/);
		});
	});
});
