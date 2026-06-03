import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] bulk editor ops (roadmap Phase 3 — Bulk operations):
 * shift the whole plan by N days, and mark a week as recovery. The pure
 * field math is unit-tested (plan_bulk_ops.ts); this pins the
 * orchestration (multi-row update + reload) end-to-end by polling the
 * DB for the mutation. Throwaway plan (status `completed` to dodge the
 * one-active unique index).
 */

test.describe('/plans/[id] bulk ops', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const dayMs = 24 * 3600 * 1000;
	const iso = (d: Date) => d.toISOString().slice(0, 10);

	test('shift plan dates moves every workout + the plan window', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const weekId = crypto.randomUUID();
		const startIso = iso(new Date(Date.now() - 3 * dayMs));
		const tempoDate = iso(new Date(Date.now() - 1 * dayMs));
		const endIso = iso(new Date(Date.now() + 35 * dayMs));
		try {
			await admin.from('training_plans').insert({
				id: planId, user_id: USER_A.id, name: 'e2e shift', goal_event: 'distance_full',
				goal_distance_m: 42195, goal_time_seconds: null, start_date: startIso, end_date: endIso,
				status: 'completed', days_per_week: 5
			});
			await admin.from('plan_weeks').insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 40_000 });
			await admin.from('plan_workouts').insert({ week_id: weekId, scheduled_date: tempoDate, kind: 'tempo', target_distance_m: 12_000, target_pace_sec_per_km: 270 });

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e shift' })).toBeVisible({ timeout: 10_000 });

			await page.locator('.shift-control input').fill('7');
			await page.getByRole('button', { name: 'Shift dates' }).click();

			const expectedTempo = iso(new Date(Date.parse(tempoDate) + 7 * dayMs));
			await expect
				.poll(async () => (await admin.from('plan_workouts').select('scheduled_date').eq('week_id', weekId).single()).data?.scheduled_date)
				.toBe(expectedTempo);
			const planRow = (await admin.from('training_plans').select('start_date').eq('id', planId).single()).data;
			expect(planRow?.start_date).toBe(iso(new Date(Date.parse(startIso) + 7 * dayMs)));
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});

	test('mark week recovery scales volume + converts quality to recovery', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const weekId = crypto.randomUUID();
		const startIso = iso(new Date(Date.now() - 3 * dayMs));
		try {
			await admin.from('training_plans').insert({
				id: planId, user_id: USER_A.id, name: 'e2e recovery', goal_event: 'distance_full',
				goal_distance_m: 42195, goal_time_seconds: null, start_date: startIso,
				end_date: iso(new Date(Date.now() + 35 * dayMs)), status: 'completed', days_per_week: 5
			});
			await admin.from('plan_weeks').insert({ id: weekId, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 40_000 });
			await admin.from('plan_workouts').insert({ week_id: weekId, scheduled_date: iso(new Date(Date.now() - dayMs)), kind: 'tempo', target_distance_m: 12_000, target_pace_sec_per_km: 270 });

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e recovery' })).toBeVisible({ timeout: 10_000 });

			await page.getByRole('button', { name: /Make recovery week/ }).first().click();

			// Volume scaled to 60%.
			await expect
				.poll(async () => (await admin.from('plan_weeks').select('target_volume_m').eq('id', weekId).single()).data?.target_volume_m)
				.toBe(24_000);
			// The tempo session became a recovery run at 60% distance, pace cleared.
			const wo = (await admin.from('plan_workouts').select('kind, target_distance_m, target_pace_sec_per_km').eq('week_id', weekId).single()).data;
			expect(wo?.kind).toBe('recovery');
			expect(wo?.target_distance_m).toBe(7_200);
			expect(wo?.target_pace_sec_per_km).toBeNull();
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});
