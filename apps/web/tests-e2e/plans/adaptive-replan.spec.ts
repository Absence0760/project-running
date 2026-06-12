import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] adaptive (trend-based) re-plan — generator v2 P1. The engine
 * (plan_adaptive_replan.ts) is unit-tested; this pins the UI path that the
 * manual re-plan doesn't exercise: three completed weeks well under plan
 * form a sustained trend, so "Adaptive re-plan" opens the preview WITH a
 * trend reason + confidence badge, and applying writes the make-up.
 * Throwaway plan (status `completed` to dodge the one-active unique index;
 * re-planning gates on dates, not status). Planned volume is set far above
 * any real mileage the seed user might have in-window, so the three weeks
 * are deterministically "under" without seeding runs.
 */

test.describe('/plans/[id] adaptive re-plan', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a sustained under-running trend proposes a badged adaptive re-plan', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const dayMs = 24 * 3600 * 1000;
		const iso = (d: Date) => d.toISOString().slice(0, 10);
		const start = new Date(Date.now() - 21 * dayMs); // weeks 0-2 fully past
		const weekIds = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
		const nextLongId = crypto.randomUUID();

		try {
			await admin.from('training_plans').insert({
				id: planId, user_id: USER_A.id, name: 'e2e adaptive replan', goal_event: 'distance_full',
				goal_distance_m: 42195, goal_time_seconds: null, start_date: iso(start),
				end_date: iso(new Date(Date.now() + 60 * dayMs)), status: 'completed', days_per_week: 5,
			});
			await admin.from('plan_weeks').insert([
				{ id: weekIds[0], plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 200_000 },
				{ id: weekIds[1], plan_id: planId, week_index: 1, phase: 'build', target_volume_m: 200_000 },
				{ id: weekIds[2], plan_id: planId, week_index: 2, phase: 'build', target_volume_m: 200_000 },
				{ id: weekIds[3], plan_id: planId, week_index: 3, phase: 'build', target_volume_m: 200_000 },
			]);
			await admin.from('plan_workouts').insert([
				// A missed long run in week 0 gives the conservative engine a safe make-up.
				{ id: crypto.randomUUID(), week_id: weekIds[0], scheduled_date: iso(new Date(Date.now() - 17 * dayMs)), kind: 'long', target_distance_m: 28_000 },
				// The next long run, in the future, planned 22 km.
				{ id: nextLongId, week_id: weekIds[3], scheduled_date: iso(new Date(Date.now() + 3 * dayMs)), kind: 'long', target_distance_m: 22_000 },
			]);

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e adaptive replan' }))
				.toBeVisible({ timeout: 10_000 });

			await page.getByRole('button', { name: 'Adaptive re-plan' }).click();

			const preview = page.locator('.replan-preview');
			await expect(preview).toBeVisible({ timeout: 10_000 });
			// The distinguishing element: the trend reason + confidence badge.
			await expect(preview.locator('.replan-adaptive-badge')).toHaveText(/under your plan/i);
			await expect(preview.locator('.replan-adaptive-badge')).toHaveText(/high confidence/i);

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
