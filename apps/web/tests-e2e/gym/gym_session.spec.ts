import { expect, test, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym/session/[routineId] — the gym guided-session runner (gym_programming.md
 * P2: expandRoutineSteps + gym_adherence + the GymWorkoutRunner shape).
 *
 * Covers the execution loop end to end: starting a routine renders the first
 * step with its target prefilled; completing a set advances the step counter;
 * a rest timer appears between sets when rest_s > 0 and Skip-rest advances;
 * skipping a set marks it missed and continues; finishing persists a
 * gym_workout (with the routine_id / gym_step_results / gym_adherence metadata
 * trio) and lands on /gym/[id] with the adherence review panel; discarding via
 * the ConfirmDialog leaves without saving anything.
 *
 * Each run seeds its own routine (unique title/exercise so rows never collide
 * in the shared seed DB) directly via the admin client and cleans up after.
 */

type SeededRoutine = {
	id: string;
	title: string;
	pressExercise: string;
	rowExercise: string;
	pressKey: string;
	rowKey: string;
};

async function seedRoutine(stamp: number): Promise<SeededRoutine> {
	const admin = getAdminClient();
	const title = `E2E Session ${stamp}`;
	const pressExercise = `E2E Press ${stamp}`;
	const rowExercise = `E2E Row ${stamp}`;
	const pressKey = pressExercise.trim().toLowerCase();
	const rowKey = rowExercise.trim().toLowerCase();

	const { data: routine, error: rErr } = await admin
		.from('gym_routines')
		.insert({ author_id: USER_A.id, title, exercise_count: 2 })
		.select('id')
		.single();
	if (rErr || !routine) throw rErr ?? new Error('seed routine failed');
	const routineId = routine.id as string;

	const { data: pressEx } = await admin
		.from('gym_routine_exercises')
		.insert({
			routine_id: routineId,
			exercise_name: pressExercise,
			exercise_key: pressKey,
			position: 0,
		})
		.select('id')
		.single();
	const { data: rowEx } = await admin
		.from('gym_routine_exercises')
		.insert({
			routine_id: routineId,
			exercise_name: rowExercise,
			exercise_key: rowKey,
			position: 1,
		})
		.select('id')
		.single();

	// Press has two planned sets with a 30 s rest between them (drives the
	// rest-timer path); Row has one. Three planned steps total.
	await admin.from('gym_routine_sets').insert([
		{
			routine_exercise_id: pressEx!.id,
			set_index: 0,
			target_reps_min: 5,
			target_weight_kg: 60,
			rest_s: 30,
		},
		{
			routine_exercise_id: pressEx!.id,
			set_index: 1,
			target_reps_min: 5,
			target_weight_kg: 60,
		},
		{
			routine_exercise_id: rowEx!.id,
			set_index: 0,
			target_reps_min: 8,
			target_weight_kg: 40,
		},
	]);

	return { id: routineId, title, pressExercise, rowExercise, pressKey, rowKey };
}

async function startSession(page: Page, routineId: string): Promise<void> {
	await page.goto(`/gym/session/${routineId}`);
	await expect(page.getByTestId('gym-session-runner')).toBeVisible({ timeout: 10_000 });
	await expect(page.getByTestId('gym-exec-band')).toBeVisible();
}

test.describe('/gym/session — guided runner', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('start renders the first step with the target prefilled', async ({ page }) => {
		const admin = getAdminClient();
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);

			const band = page.getByTestId('gym-exec-band');
			await expect(band).toContainText(r.pressExercise);
			await expect(band).toContainText('Set 1/3');

			// The first step prefills its target: 5 reps @ 60 kg.
			await expect(page.getByTestId('gym-set-reps')).toHaveValue('5');
			await expect(page.getByTestId('gym-set-weight')).toHaveValue('60');
		} finally {
			await admin.from('gym_routines').delete().eq('id', r.id);
		}
	});

	test('completing a set advances + increments the step counter', async ({ page }) => {
		const admin = getAdminClient();
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);

			const band = page.getByTestId('gym-exec-band');
			await expect(band).toContainText('Set 1/3');
			await expect(band).toContainText(r.pressExercise);

			await page.getByTestId('gym-step-complete').click();

			// rest_s > 0 on Press set 1 → the rest timer interposes before the
			// counter advances. Skip it, then we are on step 2.
			await expect(page.getByTestId('gym-rest-timer')).toBeVisible({ timeout: 10_000 });
			await page.getByTestId('rest-skip').click();

			await expect(page.getByTestId('gym-exec-band')).toContainText('Set 2/3');
			await expect(page.getByTestId('gym-exec-band')).toContainText(r.pressExercise);
		} finally {
			await admin.from('gym_routines').delete().eq('id', r.id);
		}
	});

	test('a rest timer appears between sets and Skip-rest advances', async ({ page }) => {
		const admin = getAdminClient();
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);

			await expect(page.getByTestId('gym-rest-timer')).toHaveCount(0);

			await page.getByTestId('gym-step-complete').click();

			const timer = page.getByTestId('gym-rest-timer');
			await expect(timer).toBeVisible({ timeout: 10_000 });
			await expect(timer).toContainText('Rest');
			await expect(page.getByTestId('gym-exec-band')).toHaveCount(0);

			await page.getByTestId('rest-skip').click();

			await expect(timer).toHaveCount(0);
			await expect(page.getByTestId('gym-exec-band')).toBeVisible();
			await expect(page.getByTestId('gym-exec-band')).toContainText('Set 2/3');
		} finally {
			await admin.from('gym_routines').delete().eq('id', r.id);
		}
	});

	test('skipping a set marks it missed and continues', async ({ page }) => {
		const admin = getAdminClient();
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);

			// Skip the very first set (no rest precedes it) → straight to set 2.
			await page.getByTestId('gym-step-skip').click();
			await expect(page.getByTestId('gym-exec-band')).toContainText('Set 2/3');

			// Complete set 2, skip past its rest, complete the final set, finish.
			await page.getByTestId('gym-step-complete').click();
			await page.getByTestId('gym-step-complete').click();
			await page.getByTestId('gym-session-finish-save').click();

			await page.waitForURL(/\/gym\/[0-9a-f-]+$/, { timeout: 15_000 });

			const { data: created } = await admin
				.from('gym_workouts')
				.select('id, metadata')
				.eq('user_id', USER_A.id)
				.eq('title', r.title);
			expect(created?.length).toBe(1);
			const workoutId = created![0].id as string;

			try {
				const metadata = created![0].metadata as {
					routine_id: string;
					gym_step_results: Array<{ exercise_key: string; set_index: number; status: string }>;
					gym_adherence: string;
				};
				expect(metadata.routine_id).toBe(r.id);
				// The first Press set was skipped → recorded as missed.
				const first = metadata.gym_step_results.find(
					(s) => s.exercise_key === r.pressKey && s.set_index === 0,
				);
				expect(first?.status).toBe('missed');
			} finally {
				await admin.from('gym_workouts').delete().eq('id', workoutId);
			}
		} finally {
			await admin.from('gym_routines').delete().eq('id', r.id);
		}
	});

	test('finishing saves a gym_workout and shows the adherence review', async ({ page }) => {
		const admin = getAdminClient();
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);

			// Complete set 1 (prefilled 5 @ 60) → rest → skip → set 2 → set 3.
			await page.getByTestId('gym-step-complete').click();
			await page.getByTestId('rest-skip').click();
			await page.getByTestId('gym-step-complete').click();
			await page.getByTestId('gym-step-complete').click();

			await expect(page.getByTestId('gym-session-finish')).toBeVisible({ timeout: 10_000 });
			await page.getByTestId('gym-session-finish-save').click();

			await page.waitForURL(/\/gym\/[0-9a-f-]+$/, { timeout: 15_000 });

			// The adherence review panel renders on the detail screen.
			await expect(page.getByTestId('gym-workout-review')).toBeVisible({ timeout: 10_000 });
			// All three planned sets were completed at or above target → completed.
			await expect(page.getByTestId('gym-review-verdict')).toHaveText('Completed');

			const { data: created } = await admin
				.from('gym_workouts')
				.select('id, metadata')
				.eq('user_id', USER_A.id)
				.eq('title', r.title);
			expect(created?.length).toBe(1);
			const workoutId = created![0].id as string;

			try {
				const { data: sets } = await admin
					.from('gym_sets')
					.select('exercise_name, reps, weight_kg')
					.eq('workout_id', workoutId);
				// Three sets logged; weight stored canonical kg (60), not lbs.
				expect(sets?.length).toBe(3);
				const press = sets!.filter((s) => s.exercise_name === r.pressExercise);
				expect(press.length).toBe(2);
				expect(Number(press[0].weight_kg)).toBe(60);

				const metadata = created![0].metadata as { gym_adherence: string };
				expect(metadata.gym_adherence).toBe('completed');
			} finally {
				await admin.from('gym_workouts').delete().eq('id', workoutId);
			}
		} finally {
			await admin.from('gym_routines').delete().eq('id', r.id);
		}
	});

	test('discard via the ConfirmDialog leaves without saving', async ({ page }) => {
		const admin = getAdminClient();
		const r = await seedRoutine(Date.now());
		try {
			await startSession(page, r.id);

			// Enter a set so there would be something to lose, then discard.
			await page.getByTestId('gym-set-reps').fill('5');
			await page.getByTestId('gym-session-discard').click();

			const dialog = page.getByTestId('gym-discard-dialog');
			await expect(dialog).toBeVisible({ timeout: 10_000 });
			await dialog.getByRole('button', { name: 'Discard', exact: true }).click();

			// Returns to the routine detail, no workout persisted.
			await page.waitForURL(new RegExp(`/gym/routines/${r.id}$`), { timeout: 10_000 });

			const { data: created } = await admin
				.from('gym_workouts')
				.select('id')
				.eq('user_id', USER_A.id)
				.eq('title', r.title);
			expect(created?.length ?? 0).toBe(0);
		} finally {
			await admin.from('gym_routines').delete().eq('id', r.id);
		}
	});
});
