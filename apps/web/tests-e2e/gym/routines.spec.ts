import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym/routines — the gym-programming P1 slice (docs/features/gym_programming.md).
 *
 * Covers: the routine library self-hides when empty and lists once a routine
 * exists; the builder creates a routine from scratch (title + exercise +
 * target sets) and persists the three-table plan; the detail screen renders
 * the planned targets and deletes (cascade); "Save as routine" promotes a
 * logged workout; "Repeat last" instantiates a prior session into a fresh log.
 *
 * Each run uses a unique title/exercise so rows never collide in the shared
 * seed DB, and cleans up its own backend rows.
 */
test.describe('/gym/routines — build, library, detail, promote, repeat', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('library self-hides empty, builder creates a routine, detail + delete', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Routine ${stamp}`;
		const exercise = `E2E Press ${stamp}`;

		// Clear any pre-existing routines for this user so the empty-state
		// assertion is deterministic in the shared seed DB.
		await admin.from('gym_routines').delete().eq('author_id', USER_A.id);

		// Empty state: the list self-hides, the empty card shows.
		await page.goto('/gym/routines');
		await expect(page.getByTestId('routine-empty')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('routine-list')).toHaveCount(0);

		// Build a routine from scratch.
		await page.getByTestId('routine-new').click();
		await expect(page).toHaveURL(/\/gym\/routines\/new$/);
		await page.getByTestId('routine-title').fill(title);
		await page.getByTestId('routine-exercise-name').first().fill(exercise);
		await page.getByTestId('routine-set-reps').first().fill('5');
		await page.getByTestId('routine-set-weight').first().fill('80');
		await page.getByTestId('routine-save').click();

		// Lands on the detail screen; backend rows exist.
		await expect(page.getByTestId('routine-exercises')).toBeVisible({ timeout: 10_000 });
		const { data: routines } = await admin
			.from('gym_routines')
			.select('id, title, exercise_count')
			.eq('author_id', USER_A.id)
			.eq('title', title);
		expect(routines?.length).toBe(1);
		const routineId = routines![0].id as string;
		expect(routines![0].exercise_count).toBe(1);

		const { data: exRows } = await admin
			.from('gym_routine_exercises')
			.select('id, exercise_name, exercise_key, position')
			.eq('routine_id', routineId);
		expect(exRows?.length).toBe(1);
		expect(exRows![0].exercise_key).toBe(exercise.trim().toLowerCase());

		const { data: setRows } = await admin
			.from('gym_routine_sets')
			.select('target_reps_min, target_weight_kg')
			.eq('routine_exercise_id', exRows![0].id);
		expect(setRows?.length).toBe(1);
		expect(Number(setRows![0].target_reps_min)).toBe(5);
		expect(Number(setRows![0].target_weight_kg)).toBe(80);

		// Detail renders the planned target reps.
		await expect(page.getByTestId('routine-exercises')).toContainText(exercise);

		// The library now lists it (self-hide cleared).
		await page.goto('/gym/routines');
		await expect(page.getByTestId('routine-list')).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.routine-row', { hasText: title })).toBeVisible();

		// Delete via the confirm dialog → cascade.
		await page.goto(`/gym/routines/${routineId}`);
		await page.getByTestId('routine-delete').click();
		await page.getByRole('button', { name: 'Delete', exact: true }).last().click();
		await expect(page).toHaveURL(/\/gym\/routines$/, { timeout: 10_000 });

		const { data: afterDelete } = await admin
			.from('gym_routines')
			.select('id')
			.eq('id', routineId);
		expect(afterDelete?.length ?? 0).toBe(0);
		const { data: exAfter } = await admin
			.from('gym_routine_exercises')
			.select('id')
			.eq('routine_id', routineId);
		expect(exAfter?.length ?? 0).toBe(0);
	});

	test('save-as-routine promotes a logged workout', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Log ${stamp}`;
		const exercise = `E2E Row ${stamp}`;

		// Seed a logged workout directly so the test is focused on promotion.
		const { data: w } = await admin
			.from('gym_workouts')
			.insert({ user_id: USER_A.id, title })
			.select('id')
			.single();
		const workoutId = w!.id as string;
		await admin.from('gym_sets').insert([
			{ workout_id: workoutId, set_index: 0, exercise_name: exercise, reps: 8, weight_kg: 60 },
			{ workout_id: workoutId, set_index: 1, exercise_name: exercise, reps: 8, weight_kg: 60 },
		]);

		try {
			await page.goto(`/gym/${workoutId}`);
			await page.getByTestId('gym-save-as-routine').click();
			// The RoutineEditor opens prefilled with the workout title + exercise.
			await expect(page.getByTestId('routine-title')).toHaveValue(title, { timeout: 10_000 });
			await expect(page.getByTestId('routine-exercise-name').first()).toHaveValue(exercise);
			await page.getByTestId('routine-save').click();
			// Wait for the success toast so the multi-step insert has committed
			// before we assert on the backend rows.
			await expect(page.locator('.toast', { hasText: 'Routine saved' })).toBeVisible({
				timeout: 10_000,
			});

			const { data: routines } = await admin
				.from('gym_routines')
				.select('id, exercise_count')
				.eq('author_id', USER_A.id)
				.eq('title', title);
			expect(routines?.length).toBe(1);
			expect(routines![0].exercise_count).toBe(1);

			// Two logged sets → two planned sets on the promoted exercise.
			const { data: exRows } = await admin
				.from('gym_routine_exercises')
				.select('id')
				.eq('routine_id', routines![0].id);
			const { data: setRows } = await admin
				.from('gym_routine_sets')
				.select('id')
				.eq('routine_exercise_id', exRows![0].id);
			expect(setRows?.length).toBe(2);

			await admin.from('gym_routines').delete().eq('id', routines![0].id);
		} finally {
			await admin.from('gym_workouts').delete().eq('id', workoutId);
		}
	});

	test('repeat-last instantiates a prior session into a new log', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Repeat ${stamp}`;
		const exercise = `E2E Curl ${stamp}`;

		const { data: w } = await admin
			.from('gym_workouts')
			.insert({ user_id: USER_A.id, title })
			.select('id')
			.single();
		const workoutId = w!.id as string;
		await admin
			.from('gym_sets')
			.insert([{ workout_id: workoutId, set_index: 0, exercise_name: exercise, reps: 10, weight_kg: 15 }]);

		let createdId: string | null = null;
		try {
			await page.goto(`/gym/${workoutId}`);
			await page.getByTestId('gym-repeat-last').click();
			// GymEditor opens prefilled with the prior exercise; saving creates a
			// new, distinct workout (a fresh log).
			await expect(page.getByPlaceholder('Exercise name').first()).toHaveValue(exercise, {
				timeout: 10_000,
			});
			await page.getByRole('button', { name: 'Save workout' }).click();
			await expect(page).toHaveURL(/\/gym$/, { timeout: 10_000 });

			const { data: logged } = await admin
				.from('gym_workouts')
				.select('id, title')
				.eq('user_id', USER_A.id)
				.eq('title', title);
			// Two workouts with this title now: the seed + the repeated log.
			expect(logged!.length).toBe(2);
			createdId = (logged!.find((r) => r.id !== workoutId)?.id as string) ?? null;
			expect(createdId).not.toBeNull();
		} finally {
			if (createdId) await admin.from('gym_workouts').delete().eq('id', createdId);
			await admin.from('gym_workouts').delete().eq('id', workoutId);
		}
	});
});
