import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { repurposeTodayWorkout } from '../fixtures/plan-today';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Auto-complete a planned workout from a matching logged run.
 *
 * The audit found that `autoMatchRunToPlanWorkout` (apps/web/src/lib/
 * data.ts:2565) implements the canonical match algorithm (same user,
 * same calendar date, target distance within ±25%, sorted by delta)
 * — but it isn't wired into any UI path today. `/runs/new` →
 * `createManualRun()` does not invoke it; nothing else does either
 * (`grep -r autoMatchRunToPlanWorkout apps/web/src` returns one hit:
 * the definition itself).
 *
 * So the end-to-end UI saga ("log a run via /runs/new → matching
 * workout auto-completes") can't pass today — there's no production
 * code path that closes the loop. Tracked as a `test.skip` with the
 * canonical TODO so the gap is visible.
 *
 * We DO pin the read-side of the contract: when `completed_run_id`
 * is set on a plan_workouts row, the workout-detail page renders
 * the `.completed-card` and the in-grid editor's "Mark not done"
 * button is disabled with an explanatory title. The seed already
 * has one such workout (2026-04-05 long run, auto-matched by the
 * seed UPDATE to the 2026-04-05 21km run) and
 * `plans/workout-runner-surfaces.spec.ts:265` covers the editor
 * side. This file pins the workout-detail render of an auto-matched
 * workout, planting the link via service-role so the assertion
 * doesn't drift if the seed UPDATE changes.
 */

const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

interface PlantedFixture {
	workoutId: string;
	runId: string;
	originalCompletedRunId: string | null;
	originalManuallyCompleted: boolean;
	originalCompletedAt: string | null;
}

test.describe('Plan auto-complete from linked run', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test('log a matching run via /runs/new → today\'s workout auto-marks done', async ({
		page
	}) => {
		const admin = getAdminClient();
		const { workoutId, undo } = await repurposeTodayWorkout();
		const { data: workoutRow } = await admin
			.from('plan_workouts')
			.select('target_distance_m, completed_run_id, manually_completed, completed_at')
			.eq('id', workoutId)
			.maybeSingle();
		const target = (workoutRow as { target_distance_m: number })
			.target_distance_m;

		const original = {
			completed_run_id:
				(workoutRow as { completed_run_id: string | null })
					.completed_run_id ?? null,
			manually_completed:
				(workoutRow as { manually_completed: boolean })
					.manually_completed ?? false,
			completed_at:
				(workoutRow as { completed_at: string | null }).completed_at ?? null
		};

		let newRunId: string | null = null;
		try {
			await page.goto('/runs/new');
			await expect(
				page.getByRole('heading', { level: 1, name: 'Add a run' })
			).toBeVisible({ timeout: 10_000 });

			const distanceKm = target / 1000;
			const numberInputs = page.locator('input[type="number"]');
			await numberInputs.nth(0).fill(distanceKm.toString());
			await numberInputs.nth(1).fill('30');

			await page.getByRole('button', { name: 'Save run' }).click();
			await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 15_000 });
			newRunId = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];

			await expect
				.poll(
					async () => {
						const { data } = await admin
							.from('plan_workouts')
							.select('completed_run_id')
							.eq('id', workoutId)
							.maybeSingle();
						return (data as { completed_run_id: string | null } | null)
							?.completed_run_id;
					},
					{ timeout: 10_000 }
				)
				.toBe(newRunId);

			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${workoutId}`);
			await expect(page.locator('.completed-card')).toBeVisible({
				timeout: 10_000
			});
			await expect(
				page.getByRole('button', { name: 'Unlink' })
			).toBeVisible({ timeout: 10_000 });
		} finally {
			await admin
				.from('plan_workouts')
				.update({
					completed_run_id: original.completed_run_id,
					manually_completed: original.manually_completed,
					completed_at: original.completed_at
				})
				.eq('id', workoutId);
			if (newRunId) {
				await deleteRun(newRunId).catch(() => {});
			}
			await undo();
		}
	});

	test('planted completed_run_id surfaces as a completed-card on workout-detail', async ({
		page
	}) => {
		// Pin the read-side contract: a plan_workouts row with
		// `completed_run_id` non-null renders the .completed-card
		// + Unlink button on the workout-detail page. This is the
		// exact UI a real auto-match would land at; pinning the
		// render keeps the contract stable even while the write
		// path is unwired.
		const today = new Date().toISOString().slice(0, 10);
		const admin = getAdminClient();

		// Repurpose today's plan workout into a matchable target, then
		// plant a matching run + service-role link.
		const { workoutId, undo } = await repurposeTodayWorkout();
		const { data: workoutRow } = await admin
			.from('plan_workouts')
			.select('target_distance_m, completed_run_id, manually_completed, completed_at')
			.eq('id', workoutId)
			.maybeSingle();
		const target = (workoutRow as { target_distance_m: number })
			.target_distance_m;

		const planted: PlantedFixture = {
			workoutId,
			runId: '',
			originalCompletedRunId:
				(workoutRow as { completed_run_id: string | null })
					.completed_run_id ?? null,
			originalManuallyCompleted:
				(workoutRow as { manually_completed: boolean })
					.manually_completed ?? false,
			originalCompletedAt:
				(workoutRow as { completed_at: string | null }).completed_at ??
				null
		};

		try {
			// Insert a run that satisfies the ±25 % match window for
			// the workout's target distance.
			planted.runId = await insertRun({
				user_id: USER_A.id,
				started_at: `${today}T07:00:00Z`,
				duration_s: Math.round(target * 0.33),
				distance_m: target,
				source: 'app',
				metadata: { activity_type: 'run' }
			});

			// Simulate what an auto-match would do: link the run to
			// the workout via the service-role client.
			const { error } = await admin
				.from('plan_workouts')
				.update({
					completed_run_id: planted.runId,
					completed_at: new Date().toISOString()
				})
				.eq('id', workoutId);
			if (error) throw error;

			// Workout-detail renders the completed-card + Unlink
			// button (because completed_run_id is non-null).
			await page.goto(
				`/plans/${SYDNEY_HALF_PLAN_ID}/workouts/${workoutId}`
			);
			await expect(page.locator('.completed-card')).toBeVisible({
				timeout: 10_000
			});
			await expect(
				page.getByRole('button', { name: 'Unlink' })
			).toBeVisible({ timeout: 10_000 });

			// Per the workout-runner-surfaces.spec.ts:265 pattern —
			// in the in-grid editor for an auto-matched row, the
			// Mark button is disabled with an explanatory title.
			await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
			const todaySection = page.locator('section.today');
			await expect(todaySection).toBeVisible({ timeout: 10_000 });
			await todaySection.locator('.today-link').click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			const markBtn = modal.getByRole('button', {
				name: /Mark (as done|not done)/
			});
			await expect(markBtn).toBeDisabled();
			const title = await markBtn.getAttribute('title');
			expect(title ?? '').toMatch(/A run is linked/);
		} finally {
			// Clear the link first so the workout-row update doesn't
			// trip an FK constraint when the run row deletes.
			await admin
				.from('plan_workouts')
				.update({
					completed_run_id: planted.originalCompletedRunId,
					manually_completed: planted.originalManuallyCompleted,
					completed_at: planted.originalCompletedAt
				})
				.eq('id', workoutId);
			if (planted.runId) {
				await deleteRun(planted.runId).catch(() => {});
			}
			await undo();
		}
	});
});
