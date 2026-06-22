import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] destructive bulk ops (duplicate week / make-recovery-week /
 * shift plan) now route through a ConfirmDialog — each rewrites or re-dates a
 * chunk of the plan and can't be cleanly undone. This pins the two halves of
 * the contract: Cancel performs no mutation, Confirm runs it. Throwaway plan
 * is `completed` to dodge the one-active unique index (the bulk ops gate on
 * ownership, not status).
 */

test.describe('/plans/[id] bulk-op confirmations', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('duplicate week asks first — Cancel is a no-op, Confirm duplicates', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const week0 = crypto.randomUUID();
		const week1 = crypto.randomUUID();
		const dayMs = 24 * 3600 * 1000;
		const iso = (d: Date) => d.toISOString().slice(0, 10);
		const start = new Date(Date.now() - 3 * dayMs);
		try {
			await admin.from('training_plans').insert({
				id: planId, user_id: USER_A.id, name: 'e2e bulk confirm', goal_event: 'distance_half',
				goal_distance_m: 21097, goal_time_seconds: null, start_date: iso(start),
				end_date: iso(new Date(Date.now() + 30 * dayMs)), status: 'completed', days_per_week: 4
			});
			await admin.from('plan_weeks').insert([
				{ id: week0, plan_id: planId, week_index: 0, phase: 'base', target_volume_m: 30_000 },
				{ id: week1, plan_id: planId, week_index: 1, phase: 'base', target_volume_m: 32_000 }
			]);

			const weekCount = async () =>
				(await admin.from('plan_weeks').select('id', { count: 'exact', head: true }).eq('plan_id', planId)).count ?? 0;
			expect(await weekCount()).toBe(2);

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e bulk confirm' }))
				.toBeVisible({ timeout: 10_000 });

			const dialog = page.locator('[data-testid="bulk-confirm-dialog"]');

			// Cancel keeps the plan untouched.
			await page.getByRole('button', { name: /Duplicate week/ }).first().click();
			await expect(dialog).toBeVisible();
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			await expect(dialog).toBeHidden();
			expect(await weekCount()).toBe(2);

			// Confirm inserts the copy.
			await page.getByRole('button', { name: /Duplicate week/ }).first().click();
			await expect(dialog).toBeVisible();
			await dialog.getByRole('button', { name: 'Apply' }).click();

			await expect.poll(weekCount).toBe(3);
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});

	test('make recovery week asks first — Cancel leaves the workouts unchanged', async ({ page }) => {
		const admin = getAdminClient();
		const planId = crypto.randomUUID();
		const week0 = crypto.randomUUID();
		const tempoId = crypto.randomUUID();
		const dayMs = 24 * 3600 * 1000;
		const iso = (d: Date) => d.toISOString().slice(0, 10);
		const start = new Date(Date.now() - 3 * dayMs);
		try {
			await admin.from('training_plans').insert({
				id: planId, user_id: USER_A.id, name: 'e2e recovery confirm', goal_event: 'distance_half',
				goal_distance_m: 21097, goal_time_seconds: null, start_date: iso(start),
				end_date: iso(new Date(Date.now() + 30 * dayMs)), status: 'completed', days_per_week: 4
			});
			await admin.from('plan_weeks').insert([
				{ id: week0, plan_id: planId, week_index: 0, phase: 'build', target_volume_m: 40_000 }
			]);
			await admin.from('plan_workouts').insert([
				{ id: tempoId, week_id: week0, scheduled_date: iso(new Date(Date.now() + 2 * dayMs)), kind: 'tempo', target_distance_m: 12_000 }
			]);

			const tempoKind = async () =>
				(await admin.from('plan_workouts').select('kind').eq('id', tempoId).single()).data?.kind;
			expect(await tempoKind()).toBe('tempo');

			await page.goto(`/plans/${planId}`);
			await expect(page.getByRole('heading', { level: 1, name: 'e2e recovery confirm' }))
				.toBeVisible({ timeout: 10_000 });

			const dialog = page.locator('[data-testid="bulk-confirm-dialog"]');
			await page.getByRole('button', { name: /Make recovery week/ }).first().click();
			await expect(dialog).toBeVisible();
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			await expect(dialog).toBeHidden();

			// Quality session untouched after cancel.
			expect(await tempoKind()).toBe('tempo');
		} finally {
			await admin.from('training_plans').delete().eq('id', planId);
		}
	});
});
