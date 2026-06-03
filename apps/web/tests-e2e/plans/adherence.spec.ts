import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] adherence feedback (roadmap Phase 3 — Adherence feedback).
 *
 * Two owner-only flags driven by lib/training/plan_adherence.ts:
 *   - weekly mileage drift (>20% over / under the planned week volume)
 *   - a missed long run's make-up / skip recommendation
 *
 * The pure logic is unit-tested; this pins the Svelte wiring — the
 * current-week date window, the planned-volume baseline, the run
 * summation, and the conditional render. We seed a throwaway plan whose
 * start_date puts "today" inside week 0 (status `completed` to dodge the
 * one-active-plan unique index — adherence gates on dates, not status),
 * a build week with a 40 km target, an uncompleted long run dated
 * yesterday, and two runs that over-run the week to ~52 km (+30%).
 */

test.describe('/plans/[id] adherence flags', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('over-running + a missed long run both surface their flags', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const week0Id = crypto.randomUUID();
		const week1Id = crypto.randomUUID();
		const dayMs = 24 * 3600 * 1000;
		const iso = (d: Date) => d.toISOString().slice(0, 10);
		const start = new Date(Date.now() - 3 * dayMs); // today is day 3 → week 0
		const startIso = iso(start);
		const endIso = iso(new Date(Date.now() + 35 * dayMs)); // >21d out → no RaceDayPanel
		const yesterdayIso = iso(new Date(Date.now() - dayMs));

		const runIds: string[] = [];
		try {
			await admin.from('training_plans').insert({
				id: planId,
				user_id: USER_A.id,
				name: 'e2e adherence',
				goal_event: 'distance_full',
				goal_distance_m: 42195,
				goal_time_seconds: null,
				start_date: startIso,
				end_date: endIso,
				status: 'completed',
				days_per_week: 5
			});
			// Two build weeks, equal volume → no step-back, so a missed
			// long run reads "make up" (not "recovery soon").
			await admin.from('plan_weeks').insert([
				{ id: week0Id, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 40_000 },
				{ id: week1Id, plan_id: planId, week_index: 1, phase: 'build', target_volume_m: 40_000 }
			]);
			// A long run dated yesterday, left uncompleted.
			await admin.from('plan_workouts').insert({
				week_id: week0Id,
				scheduled_date: yesterdayIso,
				kind: 'long',
				target_distance_m: 20_000
			});

			// Two runs inside week 0 summing ~52 km → +30% over the 40 km plan.
			for (let i = 0; i < 2; i++) {
				const id = await insertRun({
					user_id: USER_A.id,
					started_at: new Date(Date.now() - (i + 1) * dayMs).toISOString(),
					distance_m: 26_000,
					duration_s: 7800
				});
				runIds.push(id);
			}

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e adherence' }))
				.toBeVisible({ timeout: 10_000 });

			// Over-running drift flag.
			await expect(page.locator('.adherence-flag.drift-over')).toBeVisible();
			await expect(page.locator('.adherence-flag.drift-over')).toHaveText(/over plan/i);

			// Missed long run → make-up recommendation.
			await expect(page.locator('.adherence-flag.missed-make_up')).toBeVisible();
			await expect(page.locator('.adherence-flag.missed-make_up')).toHaveText(/long run/i);
		} finally {
			for (const id of runIds) await deleteRun(id);
			// FK cascade clears weeks + workouts when the plan goes.
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});
