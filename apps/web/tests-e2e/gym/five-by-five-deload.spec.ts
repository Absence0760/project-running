import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * five_by_five deload — the back-off a stalled lifter earns.
 *
 * nextPrescription only prescribes a deload when `params.consecutiveMisses`
 * reaches `maxConsecutiveMisses`, and no authored routine ever carries that
 * key: it is derived from logged history by progressionParamsWithStreak. Before
 * that derivation the branch was unreachable, so a lifter stuck at 100 kg was
 * told to hold 100 kg forever. This spec walks the UI proof of the fix.
 *
 * Seeded straight through the admin client (the authoring UI is already covered
 * by gym-routine-runner-journey.spec.ts) so the thread is exactly:
 *   1. A five_by_five routine at 100 kg × 5 × 5.
 *   2. Three consecutive logged sessions that fall a rep short (4 reps), the
 *      newest last — a genuine stall, not a first session.
 *   3. /gym/session/<routine> prefills the runner band with the DELOADED
 *      90 kg (100 × the default 0.9 deload factor), not the planned 100.
 * Then a fourth session that clears the bar resets the streak, so the same
 * page prescribes an increase instead — the deload must not latch.
 */
test.describe('gym five_by_five deload', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a three-session stall prescribes the back-off, and clearing it prescribes an increase', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const lift = `E2E Deload Squat ${stamp}`;
		const routineTitle = `E2E Deload Routine ${stamp}`;

		let routineId: string | null = null;
		const workoutIds: string[] = [];

		/// One logged session of `lift`: five sets at 100 kg for `reps` each.
		async function logSession(startedAt: string, reps: number) {
			const { data: workout } = await admin
				.from('gym_workouts')
				.insert({ user_id: USER_A.id, title: `E2E Deload ${stamp}`, started_at: startedAt })
				.select('id')
				.single();
			const workoutId = workout!.id as string;
			workoutIds.push(workoutId);
			await admin.from('gym_sets').insert(
				Array.from({ length: 5 }, (_, i) => ({
					workout_id: workoutId,
					set_index: i,
					exercise_name: lift,
					reps,
					weight_kg: 100,
				})),
			);
		}

		try {
			await test.step('seed a five_by_five routine at 100 kg', async () => {
				const { data: routine } = await admin
					.from('gym_routines')
					.insert({ author_id: USER_A.id, title: routineTitle, exercise_count: 1 })
					.select('id')
					.single();
				routineId = routine!.id as string;

				const { data: exercise } = await admin
					.from('gym_routine_exercises')
					.insert({
						routine_id: routineId,
						exercise_name: lift,
						exercise_key: lift.trim().toLowerCase().replace(/\s+/g, ' '),
						position: 0,
						progression: 'five_by_five',
					})
					.select('id')
					.single();

				await admin.from('gym_routine_sets').insert(
					Array.from({ length: 5 }, (_, i) => ({
						routine_exercise_id: exercise!.id,
						set_index: i,
						target_reps_min: 5,
						target_reps_max: 5,
						target_weight_kg: 100,
						rest_s: 0,
					})),
				);
			});

			await test.step('three sessions a rep short prescribe the 90 kg back-off', async () => {
				await logSession('2026-04-01T09:00:00.000Z', 4);
				await logSession('2026-04-08T09:00:00.000Z', 4);
				await logSession('2026-04-15T09:00:00.000Z', 4);

				await page.goto(`/gym/session/${routineId}`);
				await expect(page.getByTestId('gym-session-runner')).toBeVisible({ timeout: 10_000 });
				await expect(page.getByTestId('gym-exec-band')).toContainText(lift);
				// The plan says 100; the stall earns the deload to 100 × 0.9.
				await expect(page.getByTestId('gym-set-weight')).toHaveValue('90');
				await expect(page.getByTestId('gym-set-reps')).toHaveValue('5');
			});

			await test.step('clearing the bar resets the streak — an increase, not another back-off', async () => {
				await logSession('2026-04-22T09:00:00.000Z', 5);

				await page.goto(`/gym/session/${routineId}`);
				await expect(page.getByTestId('gym-session-runner')).toBeVisible({ timeout: 10_000 });
				await expect(page.getByTestId('gym-set-weight')).toHaveValue('102.5');
			});
		} finally {
			for (const id of workoutIds) await admin.from('gym_workouts').delete().eq('id', id);
			if (routineId) await admin.from('gym_routines').delete().eq('id', routineId);
		}
	});
});
