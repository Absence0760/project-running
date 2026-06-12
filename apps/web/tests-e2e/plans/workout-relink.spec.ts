import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Re-link picker on workout-detail (Training Phase-3).
 *
 * A workout that's already linked to one run can be re-linked to a
 * different completed run via the "Re-link" button → picker modal.
 * The picker MUST exclude runs already linked to another workout
 * (double-count guard) — covered by the unit suite
 * `src/lib/training/relink_candidates.test.ts`; here we pin the
 * end-to-end UI saga and that the link actually moves.
 */

const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

async function plantTodayWorkout(
	excludeId?: string
): Promise<{ workoutId: string; prevDate: string }> {
	const admin = getAdminClient();
	const { data: weeks } = await admin
		.from('plan_weeks')
		.select('id')
		.eq('plan_id', SYDNEY_HALF_PLAN_ID);
	const weekIds = (weeks ?? []).map((w) => (w as { id: string }).id);
	const today = new Date().toISOString().slice(0, 10);
	// `excludeId` lets a caller plant a SECOND distinct workout on today —
	// without it the just-moved row (now at `today`) would be re-picked.
	let query = admin
		.from('plan_workouts')
		.select('id, scheduled_date, target_distance_m')
		.in('week_id', weekIds)
		.neq('kind', 'rest')
		.not('target_distance_m', 'is', null)
		.gte('scheduled_date', today);
	if (excludeId) query = query.neq('id', excludeId);
	const { data: candidates } = await query
		.order('scheduled_date', { ascending: true })
		.limit(1);
	const row = candidates?.[0] as
		| { id: string; scheduled_date: string; target_distance_m: number }
		| undefined;
	if (!row) throw new Error('no candidate workout found to repurpose');
	const { error } = await admin
		.from('plan_workouts')
		.update({ scheduled_date: today })
		.eq('id', row.id);
	if (error) throw error;
	return { workoutId: row.id, prevDate: row.scheduled_date };
}

test.describe('Workout re-link picker', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('re-link a workout from one run to a different run', async ({ page }) => {
		const admin = getAdminClient();
		const today = new Date().toISOString().slice(0, 10);
		const { workoutId, prevDate } = await plantTodayWorkout();
		const { data: workoutRow } = await admin
			.from('plan_workouts')
			.select('target_distance_m, completed_run_id, manually_completed, completed_at')
			.eq('id', workoutId)
			.maybeSingle();
		const target = (workoutRow as { target_distance_m: number }).target_distance_m;
		const original = {
			completed_run_id:
				(workoutRow as { completed_run_id: string | null }).completed_run_id ?? null,
			manually_completed:
				(workoutRow as { manually_completed: boolean }).manually_completed ?? false,
			completed_at: (workoutRow as { completed_at: string | null }).completed_at ?? null
		};

		let runA: string | null = null;
		let runB: string | null = null;
		try {
			// runA: currently linked to the workout. runB: a second
			// in-window run the user wants to re-link to.
			runA = await insertRun({
				user_id: USER_A.id,
				started_at: `${today}T07:00:00Z`,
				duration_s: Math.round(target * 0.33),
				distance_m: target,
				source: 'app',
				metadata: { activity_type: 'run' }
			});
			runB = await insertRun({
				user_id: USER_A.id,
				started_at: `${today}T17:00:00Z`,
				duration_s: Math.round(target * 0.34),
				distance_m: target * 1.02,
				source: 'app',
				metadata: { activity_type: 'run' }
			});

			const { error } = await admin
				.from('plan_workouts')
				.update({ completed_run_id: runA, completed_at: new Date().toISOString() })
				.eq('id', workoutId);
			if (error) throw error;

			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${workoutId}`);
			await expect(page.locator('.completed-card')).toBeVisible({ timeout: 10_000 });

			await page.getByRole('button', { name: 'Re-link' }).click();
			const modal = page.locator('[data-testid="relink-modal"]');
			await expect(modal).toBeVisible({ timeout: 10_000 });

			// runA shows as the current link; runB is offered as an eligible
			// re-link target. (The seed user has its own in-window runs too, so
			// assert on the specific runs by id rather than an exact count.)
			await expect(modal.locator(`button.relink-run[data-run-id="${runA}"]`)).toHaveClass(
				/current/,
				{ timeout: 10_000 }
			);
			const runBButton = modal.locator(`button.relink-run[data-run-id="${runB}"]`);
			await expect(runBButton).toBeVisible({ timeout: 10_000 });
			await expect(runBButton).not.toHaveClass(/current/);

			// Re-link to runB specifically.
			await runBButton.click();

			// The link flips to runB.
			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('plan_workouts')
							.select('completed_run_id')
							.eq('id', workoutId)
							.maybeSingle();
						return (data as { completed_run_id: string | null } | null)?.completed_run_id;
					},
					{ timeout: 10_000 }
				)
				.toBe(runB);

			await expect(modal).toBeHidden({ timeout: 10_000 });
			await expect(page.locator('.completed-card')).toBeVisible({ timeout: 10_000 });
		} finally {
			await admin
				.from('plan_workouts')
				.update({
					completed_run_id: original.completed_run_id,
					manually_completed: original.manually_completed,
					completed_at: original.completed_at
				})
				.eq('id', workoutId);
			if (runA) await deleteRun(runA).catch(() => {});
			if (runB) await deleteRun(runB).catch(() => {});
			await admin
				.from('plan_workouts')
				.update({
					scheduled_date: prevDate,
					completed_run_id: null,
					manually_completed: false,
					completed_at: null
				})
				.eq('id', workoutId);
		}
	});

	test('picker excludes a run already linked to another workout', async ({ page }) => {
		const admin = getAdminClient();
		const today = new Date().toISOString().slice(0, 10);

		// Move TWO of the plan's workouts to today so we can link a run
		// to one and verify it's hidden from the other's picker.
		const { workoutId: workoutId1, prevDate: prev1 } = await plantTodayWorkout();
		// workout2 only needs to OWN runFree (so runFree is excluded from
		// workout1's picker) — it must NOT be moved to today as well, which would
		// collide with workout1 on the (week_id, scheduled_date) one-per-day
		// constraint. Pick a distinct workout and leave its date untouched.
		const { data: weeks } = await admin
			.from('plan_weeks')
			.select('id')
			.eq('plan_id', SYDNEY_HALF_PLAN_ID);
		const weekIds = (weeks ?? []).map((w) => (w as { id: string }).id);
		const { data: w2cands } = await admin
			.from('plan_workouts')
			.select('id')
			.in('week_id', weekIds)
			.neq('kind', 'rest')
			.not('target_distance_m', 'is', null)
			.neq('id', workoutId1)
			.limit(1);
		const workoutId2 = (w2cands?.[0] as { id: string } | undefined)?.id;
		if (!workoutId2) throw new Error('no second workout to hold runFree');

		const { data: w1Row } = await admin
			.from('plan_workouts')
			.select('target_distance_m')
			.eq('id', workoutId1)
			.maybeSingle();
		const target = (w1Row as { target_distance_m: number }).target_distance_m;

		let runForW1: string | null = null;
		let runFree: string | null = null;
		try {
			runForW1 = await insertRun({
				user_id: USER_A.id,
				started_at: `${today}T06:00:00Z`,
				duration_s: Math.round(target * 0.33),
				distance_m: target,
				source: 'app',
				metadata: { activity_type: 'run' }
			});
			runFree = await insertRun({
				user_id: USER_A.id,
				started_at: `${today}T18:00:00Z`,
				duration_s: Math.round(target * 0.34),
				distance_m: target,
				source: 'app',
				metadata: { activity_type: 'run' }
			});

			// Link runForW1 to workout1, and link runFree to workout2 as
			// its current pick (so workout2's picker shows runFree as
			// current, and workout1's picker must NOT offer runFree).
			await admin
				.from('plan_workouts')
				.update({ completed_run_id: runForW1, completed_at: new Date().toISOString() })
				.eq('id', workoutId1);
			await admin
				.from('plan_workouts')
				.update({ completed_run_id: runFree, completed_at: new Date().toISOString() })
				.eq('id', workoutId2);

			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${workoutId1}`);
			await expect(page.locator('.completed-card')).toBeVisible({ timeout: 10_000 });
			await page.getByRole('button', { name: 'Re-link' }).click();
			const modal = page.locator('[data-testid="relink-modal"]');
			await expect(modal).toBeVisible({ timeout: 10_000 });

			// workout1's picker shows its current run (runForW1) but must NOT
			// offer runFree — it's linked to workout2 (the double-count guard).
			// Seed runs may also appear, so assert on these two specifically.
			await expect(
				modal.locator(`button.relink-run[data-run-id="${runForW1}"]`)
			).toHaveClass(/current/, { timeout: 10_000 });
			await expect(modal.locator(`button.relink-run[data-run-id="${runFree}"]`)).toHaveCount(0);
		} finally {
			await admin
				.from('plan_workouts')
				.update({ completed_run_id: null, completed_at: null, manually_completed: false })
				.in('id', [workoutId1, workoutId2]);
			if (runForW1) await deleteRun(runForW1).catch(() => {});
			if (runFree) await deleteRun(runFree).catch(() => {});
			// Only workout1 was moved; restore its date. workout2 kept its own.
			await admin
				.from('plan_workouts')
				.update({ scheduled_date: prev1 })
				.eq('id', workoutId1);
		}
	});
});
