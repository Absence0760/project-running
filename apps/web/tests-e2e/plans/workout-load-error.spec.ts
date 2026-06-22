import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id]/workouts/[wid] — a failed workout fetch must show a
 * "couldn't load — retry" state, NOT the "Workout not found" page that's
 * indistinguishable from a genuinely deleted workout. Pins the
 * fetchWorkout error-threading contract + the page's loadError branch +
 * retry recovery.
 */
test.describe('/plans/[id]/workouts/[wid] load error', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a failed load shows error + retry (not not-found), and retry recovers', async ({
		page
	}) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const weekId = crypto.randomUUID();
		const workoutId = crypto.randomUUID();
		const dayMs = 24 * 3600 * 1000;
		const iso = (d: Date) => d.toISOString().slice(0, 10);
		try {
			await admin.from('training_plans').insert({
				id: planId, user_id: USER_A.id, name: 'e2e workout load error', goal_event: 'distance_half',
				goal_distance_m: 21097, goal_time_seconds: null, start_date: iso(new Date()),
				end_date: iso(new Date(Date.now() + 30 * dayMs)), status: 'completed', days_per_week: 4
			});
			await admin.from('plan_weeks').insert({
				id: weekId, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 30_000
			});
			await admin.from('plan_workouts').insert({
				id: workoutId, week_id: weekId, scheduled_date: iso(new Date()), kind: 'tempo', target_distance_m: 10_000
			});

			let failNext = true;
			await page.route('**/rest/v1/plan_workouts**', async (route) => {
				if (route.request().method() === 'GET' && failNext) {
					failNext = false;
					await route.fulfill({
						status: 500,
						contentType: 'application/json',
						body: JSON.stringify({ message: 'simulated failure' })
					});
					return;
				}
				await route.fallback();
			});

			await page.goto(`/plans/${planId}/workouts/${workoutId}`);

			// Error state, NOT the not-found state.
			await expect(page.getByRole('heading', { name: "Couldn't load this workout" }))
				.toBeVisible({ timeout: 10_000 });
			await expect(page.getByRole('heading', { name: 'Workout not found' })).toHaveCount(0);

			// Retry re-fetches (now unblocked) → the workout renders.
			await page.getByRole('button', { name: 'Try again' }).click();
			await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 10_000 });
			await expect(page.getByRole('heading', { name: "Couldn't load this workout" }))
				.toHaveCount(0);
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});
