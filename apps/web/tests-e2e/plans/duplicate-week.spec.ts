import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] duplicate-a-week bulk op (atomic duplicate_plan_week RPC).
 * The re-index is unit-pinned in pgtap; this pins the owner UI: clicking
 * Duplicate on a week inserts a copy after it, pushes the later week +7
 * days, and extends the plan. Throwaway plan (status `completed` to dodge
 * the one-active unique index — duplication doesn't gate on status).
 */

test.describe('/plans/[id] duplicate week', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Duplicate inserts a copy, re-indexes the tail, and extends the plan', async ({
		page
	}) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const week0 = crypto.randomUUID();
		const week1 = crypto.randomUUID();
		const w0Long = crypto.randomUUID();
		const w1Long = crypto.randomUUID();
		const dayMs = 24 * 3600 * 1000;
		const iso = (d: Date) => d.toISOString().slice(0, 10);
		const start = new Date(Date.now() + 7 * dayMs); // plan starts next week
		const end = new Date(Date.now() + 21 * dayMs);
		const w0Date = new Date(Date.now() + 10 * dayMs);
		const w1Date = new Date(Date.now() + 17 * dayMs);
		try {
			await admin.from('training_plans').insert({
				id: planId, user_id: USER_A.id, name: 'e2e dup week', goal_event: 'distance_10k',
				goal_distance_m: 10000, goal_time_seconds: null, start_date: iso(start),
				end_date: iso(end), status: 'completed', days_per_week: 4
			});
			await admin.from('plan_weeks').insert([
				{ id: week0, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 30_000 },
				{ id: week1, plan_id: planId, week_index: 1, phase: 'build', target_volume_m: 40_000 }
			]);
			await admin.from('plan_workouts').insert([
				{ id: w0Long, week_id: week0, scheduled_date: iso(w0Date), kind: 'long', target_distance_m: 12_000 },
				{ id: w1Long, week_id: week1, scheduled_date: iso(w1Date), kind: 'long', target_distance_m: 16_000 }
			]);

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e dup week' }))
				.toBeVisible({ timeout: 10_000 });

			// Duplicate the first week (the page renders one Duplicate button
			// per week; the first belongs to week 0).
			await page.getByRole('button', { name: 'Duplicate week' }).first().click();

			// Plan grows to three weeks, densely indexed 0..2.
			await expect
				.poll(async () =>
					(await admin.from('plan_weeks').select('week_index').eq('plan_id', planId)).data?.length
				)
				.toBe(3);
			const weeks = (
				await admin.from('plan_weeks').select('week_index').eq('plan_id', planId)
			).data?.map((r) => r.week_index).sort((a, b) => a - b);
			expect(weeks).toEqual([0, 1, 2]);

			// The former week 1 (now index 2) had its long run pushed +7 days.
			const shifted = (
				await admin.from('plan_workouts').select('scheduled_date').eq('id', w1Long).single()
			).data?.scheduled_date;
			expect(shifted).toBe(iso(new Date(w1Date.getTime() + 7 * dayMs)));

			// Plan end_date extended by a week.
			const newEnd = (
				await admin.from('training_plans').select('end_date').eq('id', planId).single()
			).data?.end_date;
			expect(newEnd).toBe(iso(new Date(end.getTime() + 7 * dayMs)));
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});
