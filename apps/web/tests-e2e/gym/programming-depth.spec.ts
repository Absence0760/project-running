import { expect, test, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym programming engine — DEPTH coverage of the routines → supersets →
 * guided runner → progression stack (docs/features/gym_programming.md, P1-P4).
 *
 * This spec deliberately covers the genuinely-uncovered seams that the existing
 * gym specs do NOT:
 *   - routines.spec.ts covers the builder, library self-hide, save-as-routine,
 *     repeat-last, and superset *persistence* (the relational columns land);
 *   - gym_session.spec.ts covers the runner's completed / missed / discard
 *     happy paths and rest-timer interpose.
 *
 * What's left, and what this file pins:
 *   1. save-as-routine ROUND-TRIPS — the promoted routine appears in
 *      /gym/routines and prefills the runner with the same exercises/targets
 *      (routineFromWorkout → prefillFromRoutine path end to end, not just the
 *      DB rows).
 *   2. REPEAT-LAST prefill — starting a saved routine prefills the first step's
 *      targets in the execution band (prefillFromRoutine / step seeding).
 *   3. SUPERSET RUNNER ORDER — a routine authored with a superset interleaves
 *      its members round-robin in the runner (expandRoutineSteps: A1,B1,A2,…),
 *      observable as the band's exercise + set-counter sequence.
 *   4. PROGRESSION chip — a routine carrying progression='linear' + a from-
 *      routine session that hits its targets renders the gym-next-target
 *      prescription chip with the +load delta; a session that falls short
 *      renders the hold hint instead (nextPrescription wired through the
 *      review panel).
 *   5. ADHERENCE 'partial' verdict — skipping one of several working sets
 *      yields a 'partial' (not 'Completed') verdict on the review panel, and
 *      metadata.gym_adherence persists 'partial'.
 *
 * Each test seeds its own routine/workout with a unique stamped title/exercise
 * so rows never collide in the shared seed DB, and tears its rows down in
 * afterEach via the admin (service-role) client.
 */

// IDs the active test seeded — torn down in afterEach regardless of outcome.
let seededRoutineIds: string[] = [];
let seededWorkoutTitles: string[] = [];

test.afterEach(async () => {
	const admin = getAdminClient();
	for (const id of seededRoutineIds) {
		await admin.from('gym_routines').delete().eq('id', id);
	}
	for (const title of seededWorkoutTitles) {
		await admin.from('gym_workouts').delete().eq('user_id', USER_A.id).eq('title', title);
	}
	seededRoutineIds = [];
	seededWorkoutTitles = [];
});

type ExerciseSeed = {
	name: string;
	position: number;
	supersetGroup?: number | null;
	supersetOrder?: number | null;
	progression?: string;
	progressionParams?: Record<string, unknown>;
	sets: Array<{
		setIndex: number;
		setType?: string;
		repsMin?: number | null;
		weightKg?: number | null;
		restS?: number | null;
	}>;
};

async function seedRoutine(title: string, exercises: ExerciseSeed[]): Promise<string> {
	const admin = getAdminClient();
	const { data: routine, error: rErr } = await admin
		.from('gym_routines')
		.insert({ author_id: USER_A.id, title, exercise_count: exercises.length })
		.select('id')
		.single();
	if (rErr || !routine) throw rErr ?? new Error('seed routine failed');
	const routineId = routine.id as string;
	seededRoutineIds.push(routineId);

	for (const ex of exercises) {
		const { data: exRow, error: eErr } = await admin
			.from('gym_routine_exercises')
			.insert({
				routine_id: routineId,
				exercise_name: ex.name,
				exercise_key: ex.name.trim().toLowerCase(),
				position: ex.position,
				superset_group: ex.supersetGroup ?? null,
				superset_order: ex.supersetGroup == null ? null : (ex.supersetOrder ?? 0),
				progression: ex.progression ?? 'none',
				progression_params: ex.progressionParams ?? {},
			})
			.select('id')
			.single();
		if (eErr || !exRow) throw eErr ?? new Error('seed exercise failed');
		await admin.from('gym_routine_sets').insert(
			ex.sets.map((s) => ({
				routine_exercise_id: exRow.id,
				set_index: s.setIndex,
				set_type: s.setType ?? 'working',
				target_reps_min: s.repsMin ?? null,
				target_weight_kg: s.weightKg ?? null,
				rest_s: s.restS ?? null,
			})),
		);
	}
	return routineId;
}

async function startSession(page: Page, routineId: string): Promise<void> {
	await page.goto(`/gym/session/${routineId}`);
	await expect(page.getByTestId('gym-session-runner')).toBeVisible({ timeout: 10_000 });
	await expect(page.getByTestId('gym-exec-band')).toBeVisible();
}

test.describe('/gym programming — routines → supersets → runner → progression', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('save-as-routine round-trips into the library and the runner prefill', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Promote ${stamp}`;
		const exercise = `E2E Squat ${stamp}`;
		seededWorkoutTitles.push(title);

		// Seed a logged workout: two sets of one exercise at 100 kg × 5.
		const { data: w } = await admin
			.from('gym_workouts')
			.insert({ user_id: USER_A.id, title })
			.select('id')
			.single();
		const workoutId = w!.id as string;
		await admin.from('gym_sets').insert([
			{ workout_id: workoutId, set_index: 0, exercise_name: exercise, reps: 5, weight_kg: 100 },
			{ workout_id: workoutId, set_index: 1, exercise_name: exercise, reps: 5, weight_kg: 100 },
		]);

		// Promote it to a routine through the UI.
		await page.goto(`/gym/${workoutId}`);
		await page.getByTestId('gym-save-as-routine').click();
		await expect(page.getByTestId('routine-title')).toHaveValue(title, { timeout: 10_000 });
		await page.getByTestId('routine-save').click();
		await expect(page.locator('.toast', { hasText: 'Routine saved' })).toBeVisible({
			timeout: 10_000,
		});

		const { data: routines } = await admin
			.from('gym_routines')
			.select('id')
			.eq('author_id', USER_A.id)
			.eq('title', title);
		expect(routines?.length).toBe(1);
		const routineId = routines![0].id as string;
		seededRoutineIds.push(routineId);

		// 1) It appears in the routine library, reusing the same title.
		await page.goto('/gym/routines');
		await expect(page.getByTestId('routine-list')).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.routine-row', { hasText: title })).toBeVisible();

		// 2) Its detail reuses the promoted exercise + two planned sets.
		await page.goto(`/gym/routines/${routineId}`);
		await expect(page.getByTestId('routine-exercises')).toContainText(exercise, { timeout: 10_000 });
		const { data: planSets } = await admin
			.from('gym_routine_sets')
			.select('target_reps_min, target_weight_kg')
			.eq(
				'routine_exercise_id',
				(
					await admin
						.from('gym_routine_exercises')
						.select('id')
						.eq('routine_id', routineId)
						.single()
				).data!.id,
			);
		expect(planSets?.length).toBe(2);
		expect(Number(planSets![0].target_weight_kg)).toBe(100);

		// 3) Starting the promoted routine prefills the runner from those targets
		//    — the round-trip the DB-row assertions alone don't prove.
		await startSession(page, routineId);
		const band = page.getByTestId('gym-exec-band');
		await expect(band).toContainText(exercise);
		await expect(band).toContainText('Set 1/2');
		await expect(page.getByTestId('gym-set-reps')).toHaveValue('5');
		await expect(page.getByTestId('gym-set-weight')).toHaveValue('100');
	});

	test('starting a routine prefills the first step targets from the plan', async ({ page }) => {
		const stamp = Date.now();
		const routineId = await seedRoutine(`E2E Prefill ${stamp}`, [
			{
				name: `E2E Bench ${stamp}`,
				position: 0,
				sets: [
					{ setIndex: 0, repsMin: 8, weightKg: 70 },
					{ setIndex: 1, repsMin: 8, weightKg: 70 },
				],
			},
		]);

		await startSession(page, routineId);

		const band = page.getByTestId('gym-exec-band');
		await expect(band).toContainText('Set 1/2');
		// The plan's first set (8 reps @ 70 kg) prefills the editable band.
		await expect(page.getByTestId('gym-set-reps')).toHaveValue('8');
		await expect(page.getByTestId('gym-set-weight')).toHaveValue('70');
		// The target read-out echoes the plan, too.
		await expect(band).toContainText('70');
	});

	test('superset members interleave round-robin in the runner order', async ({ page }) => {
		const stamp = Date.now();
		const exA = `E2E SupA ${stamp}`;
		const exB = `E2E SupB ${stamp}`;
		const exC = `E2E SoloC ${stamp}`;

		// A (2 sets) + B (1 set) share superset group 1; C is standalone.
		// expandRoutineSteps must emit A1, B1, A2, then C1 — never A1, A2, B1.
		const routineId = await seedRoutine(`E2E SupersetOrder ${stamp}`, [
			{
				name: exA,
				position: 0,
				supersetGroup: 1,
				supersetOrder: 0,
				sets: [
					{ setIndex: 0, repsMin: 5, weightKg: 50 },
					{ setIndex: 1, repsMin: 5, weightKg: 50 },
				],
			},
			{
				name: exB,
				position: 1,
				supersetGroup: 1,
				supersetOrder: 1,
				sets: [{ setIndex: 0, repsMin: 10, weightKg: 20 }],
			},
			{
				name: exC,
				position: 2,
				sets: [{ setIndex: 0, repsMin: 8, weightKg: 30 }],
			},
		]);

		await startSession(page, routineId);
		const band = page.getByTestId('gym-exec-band');

		// Step 1 — A1 (4 steps total: A1, B1, A2, C1).
		await expect(band).toContainText(exA);
		await expect(band).toContainText('Set 1/4');

		// Step 2 — B1 (the superset partner, not A's second set).
		await page.getByTestId('gym-step-complete').click();
		await expect(band).toContainText(exB);
		await expect(band).toContainText('Set 2/4');

		// Step 3 — back to A for its second set (round 2 of the superset).
		await page.getByTestId('gym-step-complete').click();
		await expect(band).toContainText(exA);
		await expect(band).toContainText('Set 3/4');

		// Step 4 — the standalone C, after the whole superset group drains.
		await page.getByTestId('gym-step-complete').click();
		await expect(band).toContainText(exC);
		await expect(band).toContainText('Set 4/4');
	});

	test('linear progression: a hit session renders an add-load next-target chip', async ({
		page,
	}) => {
		const stamp = Date.now();
		const exercise = `E2E Deadlift ${stamp}`;
		const title = `E2E LinearHit ${stamp}`;
		seededWorkoutTitles.push(title);

		// Routine with linear progression, +2.5 kg increment, single 5-rep target.
		const routineId = await seedRoutine(title, [
			{
				name: exercise,
				position: 0,
				progression: 'linear',
				progressionParams: { incrementKg: 2.5 },
				sets: [
					{ setIndex: 0, repsMin: 5, weightKg: 100 },
					{ setIndex: 1, repsMin: 5, weightKg: 100 },
				],
			},
		]);

		await startSession(page, routineId);
		// Complete both sets at the prefilled target (5 @ 100, both hit).
		await page.getByTestId('gym-step-complete').click();
		await page.getByTestId('gym-step-complete').click();
		await expect(page.getByTestId('gym-session-finish')).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('gym-session-finish-save').click();
		await page.waitForURL(/\/gym\/[0-9a-f-]+$/, { timeout: 15_000 });

		// All targets hit → the review verdict is Completed.
		await expect(page.getByTestId('gym-workout-review')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('gym-review-verdict')).toHaveText('Completed');

		// nextPrescription suggests +load: the chip renders an increase hint with
		// the +2.5 kg delta. (100 → 102.5; reps were all at/over target.)
		const targets = page.getByTestId('gym-next-targets');
		await expect(targets).toBeVisible();
		const chip = page.getByTestId('gym-next-target').filter({ hasText: exercise });
		await expect(chip).toContainText('Add load next time');
		await expect(chip).toContainText('2.5');
	});

	test('linear progression: a short session renders the hold hint, not add-load', async ({
		page,
	}) => {
		const stamp = Date.now();
		const exercise = `E2E OHP ${stamp}`;
		const title = `E2E LinearHold ${stamp}`;
		seededWorkoutTitles.push(title);

		const routineId = await seedRoutine(title, [
			{
				name: exercise,
				position: 0,
				progression: 'linear',
				progressionParams: { incrementKg: 2.5 },
				sets: [{ setIndex: 0, repsMin: 5, weightKg: 40 }],
			},
		]);

		await startSession(page, routineId);
		// Log the set UNDER the rep target (4 reps vs a 5-rep target) at the
		// planned weight. 4 >= 80% of 5 (=4.0), so adherence still counts the set
		// as hit (session Completed), but linear progression requires hitting the
		// FULL rep target to add load — 4 < 5 → it holds.
		await page.getByTestId('gym-set-reps').fill('4');
		await page.getByTestId('gym-step-complete').click();
		await expect(page.getByTestId('gym-session-finish')).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('gym-session-finish-save').click();
		await page.waitForURL(/\/gym\/[0-9a-f-]+$/, { timeout: 15_000 });

		await expect(page.getByTestId('gym-workout-review')).toBeVisible({ timeout: 10_000 });
		const chip = page.getByTestId('gym-next-target').filter({ hasText: exercise });
		await expect(chip).toBeVisible();
		await expect(chip).toContainText('Hold — repeat this target');
		await expect(chip).not.toContainText('Add load next time');
	});

	test("skipping one of three working sets yields a 'partial' verdict", async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const exercise = `E2E Press ${stamp}`;
		const title = `E2E Partial ${stamp}`;
		seededWorkoutTitles.push(title);

		// Three plain working sets, one exercise — no warmups (warmups are
		// excluded from the denominator and would skew the fraction).
		const routineId = await seedRoutine(title, [
			{
				name: exercise,
				position: 0,
				sets: [
					{ setIndex: 0, repsMin: 5, weightKg: 60 },
					{ setIndex: 1, repsMin: 5, weightKg: 60 },
					{ setIndex: 2, repsMin: 5, weightKg: 60 },
				],
			},
		]);

		await startSession(page, routineId);
		// Complete set 1 + set 2 at target, SKIP set 3 → 2/3 hit = 0.667 < 0.8.
		await page.getByTestId('gym-step-complete').click();
		await page.getByTestId('gym-step-complete').click();
		await page.getByTestId('gym-step-skip').click();
		await expect(page.getByTestId('gym-session-finish')).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('gym-session-finish-save').click();
		await page.waitForURL(/\/gym\/[0-9a-f-]+$/, { timeout: 15_000 });

		// The review verdict must read Partial, not Completed.
		await expect(page.getByTestId('gym-workout-review')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('gym-review-verdict')).toHaveText('Partial');

		// And metadata.gym_adherence persists 'partial' on the workout row.
		const { data: created } = await admin
			.from('gym_workouts')
			.select('metadata')
			.eq('user_id', USER_A.id)
			.eq('title', title);
		expect(created?.length).toBe(1);
		const metadata = created![0].metadata as {
			gym_adherence: string;
			gym_step_results: Array<{ set_index: number; status: string }>;
		};
		expect(metadata.gym_adherence).toBe('partial');
		// The skipped third set is recorded as missed; the first two as hit.
		const missed = metadata.gym_step_results.filter((s) => s.status === 'missed');
		expect(missed.length).toBe(1);
		expect(missed[0].set_index).toBe(2);
	});
});
