import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan, deleteRun, insertRun, setPlanStatus } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Starter-ADOPTION → RE-LINK → ADHERENCE-DRIFT → RE-PLAN journey.
 *
 * A single training plan walked from the /plans/new built-in starter
 * picker through the "I fell behind — fix it" chain. Deliberately
 * DISTINCT from plan-progress-journey.spec.ts (which creates via the
 * Training WIZARD and COMPLETES a workout by marking it done in the
 * day-grid modal) and from the focused single-slice specs
 * (starter-plan / adherence / replan / workout-relink):
 *
 *   1. ADOPT a built-in starter (the 12-week half-marathon) through the
 *      real /plans/new picker → instantiateStarter → generatePlan →
 *      createTrainingPlan row insert, landing on /plans/[id] with a
 *      genuinely generated multi-week, multi-phase grid. (The progress
 *      journey uses the wizard; this one uses the starter library — the
 *      distinct entry point.)
 *   2. Verify the generated week grid + phase marker render on the
 *      adopted plan.
 *   3. Re-shape into a deterministic adherence/re-plan case anchored to
 *      TODAY — a current build week (week 0) holding TWO past-dated long
 *      runs (one we link a run to via the picker; one left UNcompleted to
 *      drive the missed-long flag + the re-plan make-up), a future
 *      build-week long run (week 1) for re-plan to bump, and two
 *      over-running runs inside week 0. (The starter generator picks
 *      weekdays relative to the picker start date, so the adherence /
 *      missed-long conditions aren't deterministic off the generated
 *      rows; the pure derivations are unit-tested, so we lay down a
 *      controlled shape — same technique the progress journey uses — but
 *      drive the DISTINCT Re-link link path below, not mark-done.)
 *   4. LINK a run to a past long run via the workout-detail Re-link
 *      picker (the genuine UI link path). Pre-link an initial run via
 *      service-role so the workout reads completed and exposes "Re-link",
 *      then drive the picker to move the link to a freshly-created run —
 *      and confirm the link actually moved in the DB.
 *   5. The adherence banner reflects drift: the over-running flag
 *      (.adherence-flag.drift-over) AND the still-missed long run's
 *      make-up flag (.adherence-flag.missed-make_up) — the SECOND past
 *      long run is uncompleted, so both signals render. (Note: the run we
 *      re-linked completes its OWN long run; the missed flag + re-plan
 *      both key off the OTHER, uncompleted, past long run — re-plan skips
 *      completed long runs.)
 *   6. RE-PLAN remaining weeks: "Re-plan remaining weeks" →
 *      .replan-preview proposes a make-up on the future long run (off the
 *      uncompleted missed long) → Apply changes → only the FUTURE long
 *      run's target_distance_m is rewritten (capped to 1.15×); both PAST
 *      long runs are frozen.
 *   7. Backend cross-check: the plan + its weeks/workouts, the moved
 *      link, the bumped future distance, the untouched past distances.
 *
 * Cleanup: service-role deletePlan (cascades weeks + workouts) + deleteRun
 * for every run created, and the seed's Richmond Half is restored to
 * `active` (createTrainingPlan auto-demotes the active plan to claim the
 * one-active slot — same restore as starter-plan.spec.ts) so downstream
 * specs see it active.
 */

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';
const DAY_MS = 24 * 3600 * 1000;
const iso = (d: Date) => d.toISOString().slice(0, 10);

test.describe('plan adherence + re-plan journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let plantedPlanId: string | null = null;
	const seededRunIds: string[] = [];

	test.afterEach(async () => {
		for (const id of seededRunIds.splice(0)) {
			await deleteRun(id).catch(() => {});
		}
		if (plantedPlanId) {
			await deletePlan(plantedPlanId).catch(() => {});
			plantedPlanId = null;
		}
		// createTrainingPlan auto-completes the seed's active Richmond Half to
		// claim the one-active slot. Restore it so the rest of the suite is
		// unaffected.
		await setPlanStatus(SEED_PLAN_ID, 'active').catch(() => {});
	});

	test('adopt starter → re-link a run → adherence drift → re-plan future weeks', async ({
		page
	}) => {
		const admin = getAdminClient();

		// ── 1. Adopt the half-marathon starter via the real picker ─────
		await test.step('adopt a built-in starter from /plans/new', async () => {
			await page.goto('/plans/new');
			await expect(
				page.getByRole('heading', { level: 2, name: 'Start from a built-in plan' })
			).toBeVisible({ timeout: 10_000 });

			await page.getByLabel('Starter plan').selectOption('half_12wk');
			// Scope to the starter section — the from-scratch PlanEditor also has a
			// "Create plan" submit button.
			await page
				.locator('.starter-picker')
				.getByRole('button', { name: 'Create plan' })
				.click();

			await page.waitForURL(/\/plans\/[0-9a-f-]{36}$/, { timeout: 15_000 });
			plantedPlanId = page.url().match(/\/plans\/([0-9a-f-]+)$/)![1];

			// The 12-week half starter persisted as USER_A's active plan.
			const { data } = await admin
				.from('training_plans')
				.select('name, status, goal_event')
				.eq('id', plantedPlanId)
				.single();
			expect(data?.goal_event).toBe('distance_half');
			expect(data?.status).toBe('active');
		});

		// ── 2. The generated grid renders on the adopted plan ──────────
		await test.step('generated week grid + phase marker render', async () => {
			const weeks = page.locator('.weeks .week');
			await expect(weeks.first()).toBeVisible({ timeout: 10_000 });
			// A 12-week half plan emits many weeks.
			expect(await weeks.count()).toBeGreaterThanOrEqual(2);

			// Multi-phase plan → the phase marker shows >1 step with one active.
			const phaseSteps = page.locator('.phase-marker .phase-step');
			expect(await phaseSteps.count()).toBeGreaterThanOrEqual(2);
			await expect(page.locator('.phase-marker .phase-step.active')).toBeVisible();
		});

		// ── 3. Re-shape into a deterministic adherence / re-plan case ──
		// Replace the generated weeks with a controlled build→build shape
		// anchored to today: week 0 (current) holds TWO past long runs —
		// `relinkLongId` (we link a run to it via the picker) and
		// `missedLongId` (left uncompleted → drives the missed-make_up flag
		// + the re-plan make-up; re-plan skips completed long runs, so the
		// re-linked one can't be the make-up source). Week 1 (future) holds
		// a long run for re-plan to bump. Two over-running runs inside week
		// 0 trip drift-over.
		let relinkLongId = '';
		let missedLongId = '';
		let futureLongId = '';
		await test.step('seed the data-gated week shape + over-running runs', async () => {
			const { data: genWeeks } = await admin
				.from('plan_weeks')
				.select('id')
				.eq('plan_id', plantedPlanId);
			const genWeekIds = (genWeeks ?? []).map((w) => (w as { id: string }).id);
			if (genWeekIds.length > 0) {
				await admin.from('plan_weeks').delete().in('id', genWeekIds);
			}

			// Anchor start_date so today sits inside week 0 (day 4 of 7).
			const start = new Date(Date.now() - 3 * DAY_MS);
			await admin
				.from('training_plans')
				.update({
					start_date: iso(start),
					end_date: iso(new Date(Date.now() + 40 * DAY_MS))
				})
				.eq('id', plantedPlanId);

			const week0 = crypto.randomUUID();
			const week1 = crypto.randomUUID();
			// Two equal build weeks → no step-back, so a missed long run reads
			// "make up" (recommendation === 'make_up'), matching the
			// .adherence-flag.missed-make_up + the replan make-up proposal.
			await admin.from('plan_weeks').insert([
				{ id: week0, plan_id: plantedPlanId, week_index: 0, phase: 'build', target_volume_m: 40_000 },
				{ id: week1, plan_id: plantedPlanId, week_index: 1, phase: 'build', target_volume_m: 40_000 }
			]);

			relinkLongId = crypto.randomUUID();
			missedLongId = crypto.randomUUID();
			futureLongId = crypto.randomUUID();
			// Distinct past dates — the (week_id, scheduled_date) one-per-day
			// unique constraint forbids two workouts on the same week-day.
			await admin.from('plan_workouts').insert([
				// Past long run we link a run to via the Re-link picker (step 4).
				{
					id: relinkLongId,
					week_id: week0,
					scheduled_date: iso(new Date(Date.now() - 3 * DAY_MS)),
					kind: 'long',
					target_distance_m: 20_000
				},
				// Past long run left UNcompleted → missed-make_up flag + the
				// re-plan make-up source. 28 km → the cap math below.
				{
					id: missedLongId,
					week_id: week0,
					scheduled_date: iso(new Date(Date.now() - 1 * DAY_MS)),
					kind: 'long',
					target_distance_m: 28_000
				},
				// A future long run (planned 22 km) that re-plan bumps.
				{
					id: futureLongId,
					week_id: week1,
					scheduled_date: iso(new Date(Date.now() + 5 * DAY_MS)),
					kind: 'long',
					target_distance_m: 22_000
				}
			]);

			// Two real runs inside week 0 summing ~52 km → +30% over the
			// 40 km plan → the drift-over flag.
			for (let i = 0; i < 2; i++) {
				const id = await insertRun({
					user_id: USER_A.id,
					started_at: new Date(Date.now() - (i + 1) * DAY_MS).toISOString(),
					distance_m: 26_000,
					duration_s: 7800
				});
				seededRunIds.push(id);
			}
		});

		// ── 4. Link a run to a past long run via the Re-link picker ────
		// The workout-detail Re-link affordance only appears once a run is
		// linked, so pre-link an initial run via service-role, then drive
		// the picker to MOVE the link to a freshly-created run — the genuine
		// UI link path. Operates on `relinkLongId`, leaving `missedLongId`
		// uncompleted for the adherence + re-plan beats.
		let initialRunId = '';
		let relinkTargetId = '';
		await test.step('re-link a past long run to a different run', async () => {
			// initialRun: pre-linked. relinkTarget: the in-window run we move to.
			initialRunId = await insertRun({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 3 * DAY_MS + 6 * 3600 * 1000).toISOString(),
				distance_m: 19_500,
				duration_s: 6000,
				metadata: { activity_type: 'run' }
			});
			seededRunIds.push(initialRunId);
			relinkTargetId = await insertRun({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 3 * DAY_MS + 9 * 3600 * 1000).toISOString(),
				distance_m: 20_400,
				duration_s: 6200,
				metadata: { activity_type: 'run' }
			});
			seededRunIds.push(relinkTargetId);

			const { error } = await admin
				.from('plan_workouts')
				.update({ completed_run_id: initialRunId, completed_at: new Date().toISOString() })
				.eq('id', relinkLongId);
			if (error) throw error;

			await page.goto(`/plans/${plantedPlanId}/workouts/${relinkLongId}`);
			await expect(page.locator('.completed-card')).toBeVisible({ timeout: 10_000 });

			await page.getByRole('button', { name: 'Re-link' }).click();
			const modal = page.locator('[data-testid="relink-modal"]');
			await expect(modal).toBeVisible({ timeout: 10_000 });

			// The initial run shows as current; the target is offered as
			// eligible (seed runs may also appear — assert on ids).
			await expect(
				modal.locator(`button.relink-run[data-run-id="${initialRunId}"]`)
			).toHaveClass(/current/, { timeout: 10_000 });
			const targetButton = modal.locator(
				`button.relink-run[data-run-id="${relinkTargetId}"]`
			);
			await expect(targetButton).toBeVisible({ timeout: 10_000 });
			await expect(targetButton).not.toHaveClass(/current/);

			await targetButton.click();

			// The link flips to the target run.
			await expect
				.poll(
					async () =>
						(
							await admin
								.from('plan_workouts')
								.select('completed_run_id')
								.eq('id', relinkLongId)
								.maybeSingle()
						).data?.completed_run_id,
					{ timeout: 10_000 }
				)
				.toBe(relinkTargetId);
			await expect(modal).toBeHidden({ timeout: 10_000 });
		});

		// ── 5. Adherence banner reflects drift on the plan detail ──────
		await test.step('adherence banner shows over-running + missed-long', async () => {
			await page.goto(`/plans/${plantedPlanId}`);
			const overFlag = page.locator('.adherence-flag.drift-over');
			await expect(overFlag).toBeVisible({ timeout: 10_000 });
			await expect(overFlag).toHaveText(/over plan/i);

			// The still-uncompleted long run drives the make-up flag.
			const missedFlag = page.locator('.adherence-flag.missed-make_up');
			await expect(missedFlag).toBeVisible();
			await expect(missedFlag).toHaveText(/long run/i);
		});

		// ── 6. Re-plan proposes + applies a future-only make-up ────────
		await test.step('re-plan bumps the FUTURE long run, freezes the past', async () => {
			await page.getByRole('button', { name: /Re-plan remaining weeks/ }).click();

			const preview = page.locator('.replan-preview');
			await expect(preview).toBeVisible({ timeout: 10_000 });
			await expect(preview).toHaveText(/make up a missed long run/i);

			await page.getByRole('button', { name: 'Apply changes' }).click();

			// 28 km missed long, capped to 22 km future × 1.15 = 25.3 km → 25300.
			await expect
				.poll(
					async () =>
						(
							await admin
								.from('plan_workouts')
								.select('target_distance_m')
								.eq('id', futureLongId)
								.single()
						).data?.target_distance_m,
					{ timeout: 10_000 }
				)
				.toBe(25_300);

			// Both PAST long runs are frozen — re-plan never mutates the past.
			const { data: pastRows } = await admin
				.from('plan_workouts')
				.select('id, target_distance_m')
				.in('id', [relinkLongId, missedLongId]);
			const byId = new Map(
				(pastRows ?? []).map((r) => [
					(r as { id: string }).id,
					(r as { target_distance_m: number }).target_distance_m
				])
			);
			expect(byId.get(relinkLongId)).toBe(20_000);
			expect(byId.get(missedLongId)).toBe(28_000);
		});

		// ── 7. Backend cross-check the plan + its rows ─────────────────
		await test.step('backend cross-check the plan, link, and distances', async () => {
			const { data: planRow } = await admin
				.from('training_plans')
				.select('id, status, goal_event')
				.eq('id', plantedPlanId)
				.single();
			expect(planRow?.status).toBe('active');

			const { data: weekRows } = await admin
				.from('plan_weeks')
				.select('id')
				.eq('plan_id', plantedPlanId);
			expect((weekRows ?? []).length).toBe(2);

			// The re-link landed on the target run; the missed long stayed
			// uncompleted; the future long carries the bumped distance.
			const { data: relinkRow } = await admin
				.from('plan_workouts')
				.select('completed_run_id, target_distance_m')
				.eq('id', relinkLongId)
				.single();
			expect(relinkRow?.completed_run_id).toBe(relinkTargetId);
			expect(relinkRow?.target_distance_m).toBe(20_000);

			const { data: missedRow } = await admin
				.from('plan_workouts')
				.select('completed_run_id, target_distance_m')
				.eq('id', missedLongId)
				.single();
			expect(missedRow?.completed_run_id).toBeNull();
			expect(missedRow?.target_distance_m).toBe(28_000);

			const { data: futureRow } = await admin
				.from('plan_workouts')
				.select('target_distance_m')
				.eq('id', futureLongId)
				.single();
			expect(futureRow?.target_distance_m).toBe(25_300);
		});
	});
});
