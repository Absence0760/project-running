import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] missed-session re-planning (roadmap Phase 3 — the training
 * moat). The engine (plan_replan.ts) is unit-tested; this pins the
 * preview → apply UI: a plan with a missed long run in a past build week
 * should propose bumping the next future long run, and applying it writes
 * the new distance. Throwaway plan (status `completed` to dodge the
 * one-active unique index; re-planning gates on dates, not status).
 */

test.describe('/plans/[id] re-plan', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a missed long run proposes a make-up on the next long, and Apply writes it', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const week0 = crypto.randomUUID();
		const week1 = crypto.randomUUID();
		const missedId = crypto.randomUUID();
		const nextLongId = crypto.randomUUID();
		const dayMs = 24 * 3600 * 1000;
		const iso = (d: Date) => d.toISOString().slice(0, 10);
		const start = new Date(Date.now() - 10 * dayMs); // week 0 fully past
		try {
			await admin.from('training_plans').insert({
				id: planId, user_id: USER_A.id, name: 'e2e replan', goal_event: 'distance_full',
				goal_distance_m: 42195, goal_time_seconds: null, start_date: iso(start),
				end_date: iso(new Date(Date.now() + 60 * dayMs)), status: 'completed', days_per_week: 5
			});
			await admin.from('plan_weeks').insert([
				{ id: week0, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 40_000 },
				{ id: week1, plan_id: planId, week_index: 1, phase: 'build', target_volume_m: 42_000 }
			]);
			await admin.from('plan_workouts').insert([
				// Missed long run, 8 days ago, uncompleted.
				{ id: missedId, week_id: week0, scheduled_date: iso(new Date(Date.now() - 8 * dayMs)), kind: 'long', target_distance_m: 28_000 },
				// Next long run, in the future, planned 22 km.
				{ id: nextLongId, week_id: week1, scheduled_date: iso(new Date(Date.now() + 4 * dayMs)), kind: 'long', target_distance_m: 22_000 }
			]);

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e replan' }))
				.toBeVisible({ timeout: 10_000 });

			await page.getByRole('button', { name: /Re-plan remaining weeks/ }).click();

			// Preview shows a make-up change.
			const preview = page.locator('.replan-preview');
			await expect(preview).toBeVisible();
			await expect(preview).toHaveText(/make up a missed long run/i);

			await page.getByRole('button', { name: 'Apply changes' }).click();

			// 28 km missed, capped to 22 km * 1.15 = 25.3 km → 25300.
			await expect
				.poll(async () => (await admin.from('plan_workouts').select('target_distance_m').eq('id', nextLongId).single()).data?.target_distance_m)
				.toBe(25_300);
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});
