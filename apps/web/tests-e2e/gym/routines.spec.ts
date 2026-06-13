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

	test('a failed routines load shows an error + retry, and retry recovers', async ({ page }) => {
		let failNext = true;
		await page.route('**/rest/v1/gym_routines**', async (route) => {
			if (route.request().method() === 'GET' && failNext) {
				failNext = false;
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated failure' }),
				});
				return;
			}
			await route.fallback();
		});

		await page.goto('/gym/routines');
		// Error state, not the empty state masquerading as "no routines".
		await expect(page.locator('.error-banner')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('routine-empty')).toHaveCount(0);

		await page.getByRole('button', { name: 'Retry' }).click();
		// Retry re-fetches (now unblocked) → the real empty-or-list state renders.
		await expect(page.locator('.error-banner')).toHaveCount(0, { timeout: 10_000 });
	});

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

	test('builder persists superset grouping, set-type, rest + progression', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Superset ${stamp}`;
		const exA = `E2E A ${stamp}`;
		const exB = `E2E B ${stamp}`;

		await admin.from('gym_routines').delete().eq('author_id', USER_A.id).eq('title', title);

		await page.goto('/gym/routines/new');
		await page.getByTestId('routine-title').fill(title);

		// First exercise: a warm-up set + 60s rest, linear progression, supersetted
		// with the next exercise.
		await page.getByTestId('routine-exercise-name').nth(0).fill(exA);
		await page.getByTestId('routine-set-type').nth(0).selectOption('warmup');
		await page.getByTestId('routine-set-reps').nth(0).fill('5');
		await page.getByTestId('routine-set-weight').nth(0).fill('40');
		await page.getByTestId('routine-set-rest').nth(0).fill('60');
		await page.getByTestId('routine-superset-toggle').nth(0).check();
		await page.locator('.exercise-block').nth(0).getByTestId('routine-progression').selectOption('linear');

		// Add a second exercise to complete the superset.
		await page.getByTestId('routine-add-exercise').click();
		await page.getByTestId('routine-exercise-name').nth(1).fill(exB);
		await page.getByTestId('routine-set-reps').nth(1).fill('8');
		await page.getByTestId('routine-set-weight').nth(1).fill('20');

		await page.getByTestId('routine-save').click();
		await expect(page.getByTestId('routine-exercises')).toBeVisible({ timeout: 10_000 });

		const { data: routines } = await admin
			.from('gym_routines')
			.select('id')
			.eq('author_id', USER_A.id)
			.eq('title', title);
		expect(routines?.length).toBe(1);
		const routineId = routines![0].id as string;

		try {
			const { data: exRows } = await admin
				.from('gym_routine_exercises')
				.select('id, exercise_name, position, superset_group, superset_order, progression')
				.eq('routine_id', routineId)
				.order('position', { ascending: true });
			expect(exRows?.length).toBe(2);
			// Both exercises share one superset group, ordered 0 then 1.
			expect(exRows![0].superset_group).not.toBeNull();
			expect(exRows![0].superset_group).toBe(exRows![1].superset_group);
			expect(exRows![0].superset_order).toBe(0);
			expect(exRows![1].superset_order).toBe(1);
			expect(exRows![0].progression).toBe('linear');

			const { data: setA } = await admin
				.from('gym_routine_sets')
				.select('set_type, rest_s, target_weight_kg')
				.eq('routine_exercise_id', exRows![0].id);
			expect(setA?.length).toBe(1);
			expect(setA![0].set_type).toBe('warmup');
			expect(setA![0].rest_s).toBe(60);
			expect(Number(setA![0].target_weight_kg)).toBe(40);
		} finally {
			await admin.from('gym_routines').delete().eq('id', routineId);
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
