import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan, deleteRun, insertRun, setPlanStatus } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Plan PROGRESS / COMPLETION / ADHERENCE / RE-PLAN journey.
 *
 * One brand-new training plan walked from creation through the whole
 * "am I on track?" chain — deliberately DISTINCT from the focused
 * single-slice specs (progress / adherence / auto-complete-from-run /
 * replan) and from cross-cutting/plans-journey.spec.ts (which only
 * mark-then-revert two workouts against the SEED plan and pin the
 * pct ↔ day-grid lockstep). This one owns the full lifecycle on a
 * fresh, owner-created plan and exercises the progress→completion→
 * adherence→re-plan→delete sequence end to end:
 *
 *   1. Create via the /plans/new Training wizard (PlanEditor → the
 *      Riegel → VDOT → week-phasing generator → row insert). The seed
 *      has an active plan, so the create flow gates on the
 *      Replace-plan ConfirmDialog; confirm it and land on /plans/[id].
 *   2. Verify the progress surface on the generated plan: the
 *      progress ring (.progress-ring + .pct), the today card
 *      (section.today), the phase marker (.phase-marker / base→…→taper)
 *      and the week-by-week grid (.weeks .week).
 *   3. Re-shape the plan's weeks/workouts via service-role into a
 *      deterministic base+build structure anchored to TODAY — a
 *      current build week with a markable workout today, a missed long
 *      run yesterday, and a future long run — and seed two over-running
 *      runs so the data-GATED adherence + re-plan surfaces genuinely
 *      render. (The pure derivations are unit-tested; the focused
 *      specs each seed their own throwaway plan for one slice — here
 *      we drive them all on the lifecycle plan.)
 *   4. Complete a workout by MARKING IT DONE in the day-grid modal
 *      (WorkoutEditor → markWorkoutCompleted(manual)). The web
 *      auto-complete-from-run write path is unwired
 *      (auto-complete-from-run.spec.ts), so mark-done is the real UI
 *      completion path. Verify the day flips to .completed and the
 *      progress ring pct ticks up.
 *   5. Verify the adherence banner renders: the over-running drift
 *      flag (.adherence-flag.drift-over) and the missed-long-run
 *      make-up flag (.adherence-flag.missed-make_up).
 *   6. Exercise the Re-plan flow: "Re-plan remaining weeks" →
 *      .replan-preview proposes a make-up on the next long run →
 *      Apply changes → the future long run's target_distance_m is
 *      rewritten (capped to 1.15×).
 *   7. Delete the plan via the UI: abandon the active plan from
 *      /plans, then delete the abandoned card; verify it's gone from
 *      the list.
 *
 * Cleanup: service-role deletePlan + deleteRun safety net, and the
 * seed's Richmond Half is restored to `active` (the create flow
 * demotes it to take the one-active-plan slot — same restore as
 * plans/create.spec.ts) so downstream specs see it active.
 */

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';
const DAY_MS = 24 * 3600 * 1000;
const iso = (d: Date) => d.toISOString().slice(0, 10);

test.describe('plan progress journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let plantedPlanId: string | null = null;
	const seededRunIds: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of seededRunIds.splice(0)) {
			await deleteRun(id).catch(() => {});
		}
		if (plantedPlanId) {
			await deletePlan(plantedPlanId).catch(() => {});
			plantedPlanId = null;
		}
		// The create flow auto-demotes the seed's active Richmond Half to
		// `completed` to claim the one-active slot. Restore it so the rest
		// of the suite (e.g. /coach active-plan default) is unaffected.
		await setPlanStatus(SEED_PLAN_ID, 'active').catch(() => {});
	});

	test('create → progress surface → mark done → adherence → re-plan → delete', async ({
		page
	}) => {
		const admin = getAdminClient();
		const name = `e2e-progress-journey ${Date.now()}`;

		// ── 1. Create via the /plans/new Training wizard ───────────
		await test.step('create the plan via the wizard', async () => {
			await page.goto('/plans');
			await page.getByRole('button', { name: /New plan/ }).first().click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });

			await modal.getByPlaceholder('Autumn half marathon').fill(name);
			// Race far enough out that the generator emits a multi-week,
			// multi-phase plan (base→build→…) and there's no RaceDayPanel.
			const startIso = iso(new Date(Date.now() + 7 * DAY_MS));
			await modal.locator('input[type="date"]').first().fill(startIso);

			const submit = modal.getByRole('button', { name: /Create plan/ });
			await expect(submit).toBeEnabled({ timeout: 5_000 });
			await submit.click();

			// Seed has an active plan → Replace-plan ConfirmDialog gates
			// the create. Confirm to proceed.
			const replace = page.locator('.modal.modal-narrow', {
				hasText: /Replace your active plan/
			});
			await expect(replace).toBeVisible({ timeout: 5_000 });
			await replace.getByRole('button', { name: 'Replace plan' }).click();

			await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
			plantedPlanId = page.url().match(/\/plans\/([0-9a-f-]+)$/)![1];
			await expect(page.getByRole('heading', { level: 1, name }))
				.toBeVisible({ timeout: 10_000 });
		});

		// ── 2. Progress surface renders on the generated plan ──────
		await test.step('progress surface renders (ring + today + phases + weeks)', async () => {
			// Progress ring + pct.
			await expect(page.locator('.progress-ring')).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.progress-ring .pct')).toBeVisible();

			// Phase marker — base→build→peak→taper steps with one active.
			const phaseSteps = page.locator('.phase-marker .phase-step');
			expect(await phaseSteps.count()).toBeGreaterThanOrEqual(2);
			await expect(page.locator('.phase-marker .phase-step.active')).toBeVisible();

			// Today card (workout / next-up / rest / race — always one).
			await expect(page.locator('section.today').first()).toBeVisible();

			// Week-by-week grid — the generator emits multiple weeks.
			const weeks = page.locator('.weeks .week');
			await expect(weeks.first()).toBeVisible({ timeout: 10_000 });
			expect(await weeks.count()).toBeGreaterThanOrEqual(2);
		});

		// ── 3. Re-shape into a deterministic adherence/re-plan case ─
		// Replace the generated weeks with a controlled base→build
		// structure anchored to today: week 0 (build) is the CURRENT
		// week with a markable workout dated today + a missed long run
		// yesterday; week 1 (build) holds a future long run for re-plan
		// to bump. Then over-run the current week with two real runs.
		let todayWorkoutId = '';
		let futureLongId = '';
		await test.step('seed the data-gated week shape + over-running runs', async () => {
			// Drop the generator's weeks (workouts cascade) and lay down ours.
			const { data: genWeeks } = await admin
				.from('plan_weeks')
				.select('id')
				.eq('plan_id', plantedPlanId);
			const genWeekIds = (genWeeks ?? []).map((w) => (w as { id: string }).id);
			if (genWeekIds.length > 0) {
				await admin.from('plan_weeks').delete().in('id', genWeekIds);
			}

			// Anchor start_date so today sits inside week 0 (day 2 of 7).
			const start = new Date(Date.now() - 2 * DAY_MS);
			await admin
				.from('training_plans')
				.update({
					start_date: iso(start),
					end_date: iso(new Date(Date.now() + 40 * DAY_MS))
				})
				.eq('id', plantedPlanId);

			const week0 = crypto.randomUUID();
			const week1 = crypto.randomUUID();
			// Two equal build weeks → no step-back, so a missed long run
			// reads "make up" (recommendation === 'make_up'), matching the
			// .adherence-flag.missed-make_up + replanMakeUp surfaces.
			await admin.from('plan_weeks').insert([
				{ id: week0, plan_id: plantedPlanId, week_index: 0, phase: 'build', target_volume_m: 40_000 },
				{ id: week1, plan_id: plantedPlanId, week_index: 1, phase: 'build', target_volume_m: 40_000 }
			]);

			todayWorkoutId = crypto.randomUUID();
			const missedLongId = crypto.randomUUID();
			futureLongId = crypto.randomUUID();
			await admin.from('plan_workouts').insert([
				// A markable easy run scheduled TODAY (the today card + the
				// day-grid cell we'll mark done).
				{
					id: todayWorkoutId,
					week_id: week0,
					scheduled_date: iso(new Date()),
					kind: 'easy',
					target_distance_m: 6_000
				},
				// A missed long run yesterday, left uncompleted → drives the
				// missed-make_up adherence flag + the re-plan make-up proposal.
				{
					id: missedLongId,
					week_id: week0,
					scheduled_date: iso(new Date(Date.now() - DAY_MS)),
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

			// Re-render the now-reshaped plan.
			await page.reload();
			await expect(page.getByRole('heading', { level: 1, name }))
				.toBeVisible({ timeout: 10_000 });
		});

		// ── 4. Complete a workout by marking it done in the modal ──
		await test.step('mark today\'s workout done → day flips + pct rises', async () => {
			const readPct = async (): Promise<number> => {
				const txt = (await page.locator('.progress-ring .pct').textContent()) ?? '';
				const m = txt.match(/(\d+)/);
				return m ? parseInt(m[1], 10) : -1;
			};
			const initialPct = await readPct();
			expect(initialPct).toBeGreaterThanOrEqual(0);
			const completedCells = page.locator('.day.completed');
			const initialCompleted = await completedCells.count();

			// Open today's cell (the only workout scheduled today) and mark
			// it done. Scope to the day-grid so the today-card's own link
			// doesn't disambiguate poorly across week sections.
			await page.locator('.day.today:not(.rest) .day-link').first().click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			await modal.getByRole('button', { name: 'Mark as done' }).click();
			await expect(modal).toHaveCount(0);

			await expect(completedCells).toHaveCount(initialCompleted + 1, { timeout: 10_000 });
			await expect.poll(readPct, { timeout: 10_000 }).toBeGreaterThan(initialPct);
		});

		// ── 5. Adherence banner renders ────────────────────────────
		await test.step('adherence flags surface (over-running + missed long run)', async () => {
			await expect(page.locator('.adherence-flag.drift-over')).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.adherence-flag.drift-over')).toHaveText(/over plan/i);

			await expect(page.locator('.adherence-flag.missed-make_up')).toBeVisible();
			await expect(page.locator('.adherence-flag.missed-make_up')).toHaveText(/long run/i);
		});

		// ── 6. Re-plan flow proposes + applies a make-up ───────────
		await test.step('re-plan proposes a make-up and Apply rewrites the future long run', async () => {
			await page.getByRole('button', { name: /Re-plan remaining weeks/ }).click();

			const preview = page.locator('.replan-preview');
			await expect(preview).toBeVisible({ timeout: 10_000 });
			await expect(preview).toHaveText(/make up a missed long run/i);

			await page.getByRole('button', { name: 'Apply changes' }).click();

			// 28 km missed, capped to 22 km × 1.15 = 25.3 km → 25300.
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
		});

		// ── 7. Delete the plan via the UI ──────────────────────────
		await test.step('abandon then delete the plan from /plans', async () => {
			await page.goto('/plans');
			const card = page.locator('.card', { hasText: name });
			await expect(card).toBeVisible({ timeout: 10_000 });

			// Active plans expose "Abandon" → ConfirmDialog.
			await card.getByRole('button', { name: 'Abandon', exact: true }).click();
			const abandonDialog = page.locator('.modal', { hasText: 'Abandon plan' });
			await expect(abandonDialog).toBeVisible({ timeout: 5_000 });
			await abandonDialog.getByRole('button', { name: 'Abandon', exact: true }).click();
			await expect(abandonDialog).toHaveCount(0);

			// Abandoned card now exposes "Delete".
			await card.getByRole('button', { name: 'Delete', exact: true }).click();
			const deleteDialog = page.locator('.modal', { hasText: 'Delete plan' });
			await expect(deleteDialog).toBeVisible({ timeout: 5_000 });
			await deleteDialog.getByRole('button', { name: 'Delete', exact: true }).click();
			await expect(deleteDialog).toHaveCount(0);

			await expect(page.locator('.card', { hasText: name })).toHaveCount(0, {
				timeout: 10_000
			});
			plantedPlanId = null; // UI delete completed; afterEach skips.
		});
	});
});
