import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] progress header (roadmap Phase 3 — Dashboard + run-tab
 * surfaces): the overall base→build→peak→taper phase marker and the
 * longest-long-run stat. Pure derivations are unit-tested
 * (plan_progress.ts); this pins the Svelte render. Seeds a throwaway
 * plan (status `completed` to dodge the one-active unique index — the
 * surface gates on dates/phases, not status) spanning a base + build
 * week with a completed 24 km long run in the current (base) week.
 */

test.describe('/plans/[id] progress header', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('phase marker highlights the current phase + longest long run shows', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const week0Id = crypto.randomUUID();
		const week1Id = crypto.randomUUID();
		const dayMs = 24 * 3600 * 1000;
		const iso = (d: Date) => d.toISOString().slice(0, 10);
		const startIso = iso(new Date(Date.now() - 3 * dayMs)); // today → week 0 (base)
		const endIso = iso(new Date(Date.now() + 35 * dayMs));

		try {
			await admin.from('training_plans').insert({
				id: planId,
				user_id: USER_A.id,
				name: 'e2e progress',
				goal_event: 'distance_full',
				goal_distance_m: 42195,
				goal_time_seconds: null,
				start_date: startIso,
				end_date: endIso,
				status: 'completed',
				days_per_week: 5
			});
			await admin.from('plan_weeks').insert([
				{ id: week0Id, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 30_000 },
				{ id: week1Id, plan_id: planId, week_index: 1, phase: 'build', target_volume_m: 40_000 }
			]);
			// A completed 24 km long run in the current week.
			await admin.from('plan_workouts').insert({
				week_id: week0Id,
				scheduled_date: iso(new Date(Date.now() - dayMs)),
				kind: 'long',
				target_distance_m: 24_000,
				manually_completed: true
			});

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e progress' }))
				.toBeVisible({ timeout: 10_000 });

			// Phase marker: two steps (base + build), the current (base) one active.
			const steps = page.locator('.phase-marker .phase-step');
			await expect(steps).toHaveCount(2);
			await expect(page.locator('.phase-marker .phase-step.active')).toHaveText(/Base/);

			// Longest long run stat renders the 24 km figure.
			await expect(page.locator('.longest-long .longest-value')).toBeVisible();
			await expect(page.locator('.longest-long .longest-value')).toHaveText(/24/);
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});
