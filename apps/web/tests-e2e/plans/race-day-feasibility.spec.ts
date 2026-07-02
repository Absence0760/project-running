import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] RaceDayPanel goal-feasibility signal (lib/runs/race_day.ts
 * #goalFeasibility). When a plan has BOTH a goal time and recent qualifying
 * efforts, the panel grades the goal against a Riegel projection off those
 * efforts and surfaces an ahead / on-track / behind / far-behind line.
 *
 * The pure verdict logic is unit-tested; this pins the Svelte wiring — the
 * data-derived projection is computed even when a goal is set, and the
 * feasibility line renders with the right verdict class. We seed a plan whose
 * race is ~10 days out (inside the 21-day RaceDayPanel window), a 3:36:40
 * marathon goal, and a single recent 10K in 50:00 — which Riegel-projects to
 * ~3:50 for the marathon, i.e. slower than goal → the "behind" verdict.
 */

test.describe('/plans/[id] race-day goal feasibility', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a goal the recent fitness undershoots shows the behind verdict', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const week0Id = crypto.randomUUID();
		const dayMs = 24 * 3600 * 1000;
		const iso = (d: Date) => d.toISOString().slice(0, 10);
		const startIso = iso(new Date(Date.now() - 60 * dayMs));
		const endIso = iso(new Date(Date.now() + 10 * dayMs)); // 10d out → panel shows
		const runIds: string[] = [];
		try {
			await admin.from('training_plans').insert({
				id: planId,
				user_id: USER_A.id,
				name: 'e2e feasibility',
				goal_event: 'distance_full',
				goal_distance_m: 42195,
				goal_time_seconds: 13000, // 3:36:40
				start_date: startIso,
				end_date: endIso,
				status: 'completed',
				days_per_week: 5
			});
			await admin.from('plan_weeks').insert([
				{ id: week0Id, plan_id: planId, week_index: 0, phase: 'peak', target_volume_m: 40_000 }
			]);

			// A recent 10 km in 50:00 → Riegel-projects a ~3:50 marathon,
			// slower than the 3:36:40 goal → "behind".
			const id = await insertRun({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 5 * dayMs).toISOString(),
				distance_m: 10_000,
				duration_s: 3000
			});
			runIds.push(id);

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e feasibility' }))
				.toBeVisible({ timeout: 10_000 });

			const feas = page.locator('.feasibility.feas-behind');
			await expect(feas).toBeVisible();
			await expect(feas).toHaveText(/behind goal/i);
			// The delta magnitude (13:21 slower) is rendered.
			await expect(feas).toHaveText(/13:21/);
		} finally {
			for (const rid of runIds) await deleteRun(rid);
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});
