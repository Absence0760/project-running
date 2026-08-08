import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Gym detail surfaces — a partial read failure must not render as empty.
 *
 * `fetchGymWorkoutWithSets` returned `{workout, sets: []}` when the sets query
 * errored, and `fetchGymRoutineDetail` returned `{routine, exercises: []}` (and
 * silently dropped the planned sets) on the same shape. Both therefore drew a
 * fully-populated header over an empty body: a logged session presented as
 * having no sets, and a 5x5 routine presented as a bare exercise list — with a
 * live Start button inviting the user to run a prescription we never read.
 *
 * Both now fail the whole read so the page can offer a retry.
 */
test.describe('gym detail — a partial read failure is a failure', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const stamp = () => `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
	let workoutId: string | null = null;
	let routineId: string | null = null;

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (workoutId) {
			await admin.from('gym_workouts').delete().eq('id', workoutId);
			workoutId = null;
		}
		if (routineId) {
			await admin.from('gym_routines').delete().eq('id', routineId);
			routineId = null;
		}
	});

	test('a failed sets read shows a retry, not a workout with no sets', async ({ page }) => {
		const admin = getAdminClient();
		const now = new Date().toISOString();
		const { data: w, error } = await admin
			.from('gym_workouts')
			.insert({
				user_id: USER_A.id,
				title: `E2E sets-failure ${stamp()}`,
				started_at: now,
				last_modified_at: now,
			})
			.select('id')
			.single();
		if (error || !w) throw error ?? new Error('seed workout failed');
		workoutId = w.id as string;
		await admin.from('gym_sets').insert({
			workout_id: workoutId,
			exercise_name: 'Bench Press',
			set_index: 0,
			reps: 8,
			weight_kg: 60,
		});

		await page.route('**/rest/v1/gym_sets*', async (route) => {
			if (route.request().method() !== 'GET') return route.fallback();
			await route.fulfill({ status: 500, body: 'boom' });
		});

		await page.goto(`/gym/${workoutId}`);

		const banner = page.getByTestId('gym-detail-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');
	});

	test('a failed routine-exercises read shows a retry, not an empty routine', async ({ page }) => {
		const admin = getAdminClient();
		const { data: r, error } = await admin
			.from('gym_routines')
			.insert({ author_id: USER_A.id, title: `E2E routine-failure ${stamp()}`, exercise_count: 1 })
			.select('id')
			.single();
		if (error || !r) throw error ?? new Error('seed routine failed');
		routineId = r.id as string;
		const { data: ex } = await admin
			.from('gym_routine_exercises')
			.insert({
				routine_id: routineId,
				exercise_name: 'Back Squat',
				exercise_key: 'back squat',
				position: 0,
			})
			.select('id')
			.single();
		await admin.from('gym_routine_sets').insert({
			routine_exercise_id: (ex as { id: string }).id,
			set_index: 0,
			target_reps_min: 5,
			target_weight_kg: 60,
		});

		await page.route('**/rest/v1/gym_routine_exercises*', async (route) => {
			if (route.request().method() !== 'GET') return route.fallback();
			await route.fulfill({ status: 500, body: 'boom' });
		});

		await page.goto(`/gym/routines/${routineId}`);

		const banner = page.getByTestId('routine-load-error');
		await expect(banner).toBeVisible({ timeout: 15_000 });
		await expect(banner).toHaveAttribute('role', 'alert');
		// The Start button must not be offered against a routine we could not read.
		await expect(page.getByTestId('routine-start')).toHaveCount(0);
	});
});
