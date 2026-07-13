import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] cycle/pregnancy adjust + pause/resume (persona runner-woman,
 * decisions §231).
 *
 * Pause/resume is always available to the plan owner. The cycle/pregnancy
 * adjust action is behind the fail-closed PUBLIC_CYCLE_PLANS_ENABLED flag AND
 * needs the runner's consented cycle prefs, so that half is skipped unless the
 * flag is on at build time (mirrors the weigh-in / coach flag-gated specs).
 */

const dayMs = 24 * 3600 * 1000;
const iso = (d: Date) => d.toISOString().slice(0, 10);
const cyclePlansEnabled = /^(1|true|yes|on)$/i.test(
	process.env.PUBLIC_CYCLE_PLANS_ENABLED ?? ''
);

test.describe('/plans/[id] pause + resume', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('pause frees the plan, resume makes it active again', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const week0 = crypto.randomUUID();
		let displacedActiveIds: string[] = [];
		try {
			// Clear any pre-existing active plan so the one-active index is free.
			// Remember which plans we displaced so the `finally` can restore
			// them — this user's seed is shared with sibling specs (e.g.
			// list.spec.ts), which expect the seeded plan to stay active.
			const { data: displaced } = await admin
				.from('training_plans')
				.select('id')
				.eq('user_id', USER_A.id)
				.eq('status', 'active');
			displacedActiveIds = (displaced ?? []).map((p) => p.id as string);
			await admin
				.from('training_plans')
				.update({ status: 'completed' })
				.eq('user_id', USER_A.id)
				.eq('status', 'active');

			await admin.from('training_plans').insert({
				id: planId,
				user_id: USER_A.id,
				name: 'e2e pause resume',
				goal_event: 'distance_half',
				goal_distance_m: 21097,
				goal_time_seconds: null,
				start_date: iso(new Date(Date.now() - 3 * dayMs)),
				end_date: iso(new Date(Date.now() + 30 * dayMs)),
				status: 'active',
				days_per_week: 4
			});
			await admin.from('plan_weeks').insert([
				{ id: week0, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 30_000 }
			]);

			const status = async () =>
				(await admin.from('training_plans').select('status').eq('id', planId).single()).data
					?.status;

			await page.goto(`/plans/${planId}`);
			await expect(
				page.getByRole('heading', { level: 1, name: 'e2e pause resume' })
			).toBeVisible({ timeout: 10_000 });

			const dialog = page.locator('[data-testid="bulk-confirm-dialog"]');

			// Pause.
			await page.getByRole('button', { name: /Pause plan/ }).click();
			await expect(dialog).toBeVisible();
			await dialog.getByRole('button', { name: 'Apply' }).click();
			await expect.poll(status).toBe('paused');

			// Resume.
			await page.getByRole('button', { name: /Resume plan/ }).click();
			await expect(dialog).toBeVisible();
			await dialog.getByRole('button', { name: 'Apply' }).click();
			await expect.poll(status).toBe('active');
		} finally {
			// Delete our own plan first (frees the one-active slot), then
			// restore the plans we displaced so the shared seed is left active
			// for sibling specs.
			await admin.from('training_plans').delete().eq('id', planId);
			if (displacedActiveIds.length) {
				await admin
					.from('training_plans')
					.update({ status: 'active' })
					.in('id', displacedActiveIds);
			}
		}
	});
});

test.describe('/plans/[id] cycle adjust (flag-gated)', () => {
	test.use({ storageState: USER_A.storageStatePath });
	test.skip(!cyclePlansEnabled, 'PUBLIC_CYCLE_PLANS_ENABLED is off');

	test('eases an upcoming menstrual-day long run by ~15%', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const week0 = crypto.randomUUID();
		const longId = crypto.randomUUID();
		// A long run 3 days out, and a last-period-start today so that day is
		// menstrual (day <5) — the adjust must ease it.
		const longDate = iso(new Date(Date.now() + 3 * dayMs));
		try {
			// Consented cycle config in the runner's universal prefs bag.
			const { data: existing } = await admin
				.from('user_settings')
				.select('prefs')
				.eq('user_id', USER_A.id)
				.maybeSingle();
			const prefs = {
				...((existing?.prefs as Record<string, unknown>) ?? {}),
				cycle_tracking_mode: 'cycle',
				cycle_length_days: 28,
				cycle_last_period_start: longDate // makes longDate day 0 = menstrual
			};
			await admin
				.from('user_settings')
				.upsert({ user_id: USER_A.id, prefs, updated_at: new Date().toISOString() });

			await admin.from('training_plans').insert({
				id: planId,
				user_id: USER_A.id,
				name: 'e2e cycle adjust',
				goal_event: 'distance_half',
				goal_distance_m: 21097,
				goal_time_seconds: null,
				start_date: iso(new Date(Date.now() - 3 * dayMs)),
				end_date: iso(new Date(Date.now() + 30 * dayMs)),
				status: 'completed',
				days_per_week: 4
			});
			await admin.from('plan_weeks').insert([
				{ id: week0, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 40_000 }
			]);
			await admin.from('plan_workouts').insert([
				{ id: longId, week_id: week0, scheduled_date: longDate, kind: 'long', target_distance_m: 20_000 }
			]);

			const longDistance = async () =>
				(await admin.from('plan_workouts').select('target_distance_m').eq('id', longId).single())
					.data?.target_distance_m;
			expect(await longDistance()).toBe(20_000);

			await page.goto(`/plans/${planId}`);
			await expect(
				page.getByRole('heading', { level: 1, name: 'e2e cycle adjust' })
			).toBeVisible({ timeout: 10_000 });

			const dialog = page.locator('[data-testid="bulk-confirm-dialog"]');
			await page.locator('[data-testid="cycle-adjust-btn"]').click();
			await expect(dialog).toBeVisible();
			await dialog.getByRole('button', { name: 'Apply' }).click();

			// 20 000 × 0.85 = 17 000.
			await expect.poll(longDistance).toBe(17_000);
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});
