import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Gym routine → guided runner → progression journey — the gym-programming
 * P1→P4 stack walked end to end as ONE thread, the long-form companion to the
 * focused per-surface specs.
 *
 * Unlike gym-lifecycle-journey.spec.ts (ad-hoc workout create → PR badges →
 * records → save-as-routine → repeat → progression, all from a LOGGED workout)
 * this journey starts at the *authoring* end of the programming engine and runs
 * the routine THROUGH the guided session runner, which the lifecycle journey
 * never touches:
 *
 *   1. Author a reusable routine in the builder (/gym/routines/new): a main lift
 *      (linear progression) supersetted with an accessory, each with two/one
 *      working sets — exercising RoutineEditor's superset toggle + the advanced
 *      progression select. Backend cross-check the three-table plan.
 *   2. It lists in the routine library and its detail renders the planned
 *      targets (the routineFromWorkout-independent author path).
 *   3. Start the guided runner at /gym/session/[routineId]: expandRoutineSteps
 *      interleaves the superset round-robin (A1, B1, A2, C1…), each step
 *      prefilled from the plan (prefillFromRoutine). Log every set at/above
 *      target to completion.
 *   4. Finishing persists ONE gym_workout linked to the routine (metadata
 *      .routine_id + the gym_step_results / gym_adherence trio) and lands on
 *      /gym/[id], where GymWorkoutReview shows the computeRoutineAdherence
 *      planned-vs-actual table with a Completed verdict.
 *   5. The next-session progression chip (nextPrescription) renders: the main
 *      lift hit its rep target at the planned load, so linear progression
 *      suggests "Add load next time" with a +load delta — the accessory carries
 *      no scheme, so it gets no chip.
 *   6. Backend cross-check the gym_routines plan + the logged gym_workouts /
 *      gym_sets, then tear the routine + workout down so the shared seed DB is
 *      left clean.
 *
 * Unique stamped titles/exercises keep every adherence / progression assertion
 * unambiguous against the seed data and pin cleanup so rows can't collide with
 * another run. Rests are left at 0 so the runner advances directly step-to-step
 * (the rest-timer interpose is already covered by gym_session.spec.ts).
 */
test.describe('gym routine runner journey — author → guided run → adherence → progression', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a routine is authored, run through the guided session, and suggests a progression', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const routineTitle = `E2E Routine Journey ${stamp}`;
		// Main lift carries linear progression; the accessory is supersetted with
		// it but carries no scheme (so only the main lift gets a next-target chip).
		const mainLift = `E2E Squat ${stamp}`;
		const accessory = `E2E Lunge ${stamp}`;
		const mainKey = mainLift.trim().toLowerCase();
		const accessoryKey = accessory.trim().toLowerCase();

		let routineId: string | null = null;
		const workoutIds: string[] = [];

		try {
			// ── 1. Author a reusable routine in the builder ──────────────────
			await test.step('author a superset routine with linear progression on the main lift', async () => {
				await page.goto('/gym/routines/new');
				await page.getByTestId('routine-title').fill(routineTitle);

				// Main lift: two working sets @ 100 kg × 5, no rest, linear
				// progression. (Rest 0 keeps the runner stepping directly.) The
				// editor opens an exercise with ONE set; the second comes from the
				// "Add set" button. Scope both set inputs to the main block so the
				// later accessory's set can't shift the index out from under us.
				const mainBlock = page.locator('.exercise-block').nth(0);
				await page.getByTestId('routine-exercise-name').nth(0).fill(mainLift);
				await mainBlock.getByTestId('routine-set-reps').nth(0).fill('5');
				await mainBlock.getByTestId('routine-set-weight').nth(0).fill('100');
				// Append a second working set, then fill it (5 × 100 kg too).
				await mainBlock.getByRole('button', { name: 'Add set' }).click();
				await expect(mainBlock.getByTestId('routine-set-reps')).toHaveCount(2);
				await mainBlock.getByTestId('routine-set-reps').nth(1).fill('5');
				await mainBlock.getByTestId('routine-set-weight').nth(1).fill('100');
				// Progression lives in the per-exercise collapsed <details class="advanced">.
				await mainBlock.getByText('Advanced').click();
				await mainBlock.getByTestId('routine-progression').selectOption('linear');

				// Accessory: one working set @ 40 kg × 8, no scheme. Scope its set
				// inputs to the accessory block — the main lift now owns TWO global
				// set inputs, so a bare .nth(1) would land on the main lift's second
				// set, not the accessory's only set.
				await page.getByTestId('routine-add-exercise').click();
				const accessoryBlock = page.locator('.exercise-block').nth(1);
				await page.getByTestId('routine-exercise-name').nth(1).fill(accessory);
				await accessoryBlock.getByTestId('routine-set-reps').nth(0).fill('8');
				await accessoryBlock.getByTestId('routine-set-weight').nth(0).fill('40');

				// Link the main lift into a superset with the accessory — the toggle
				// is only enabled once a following exercise exists.
				await page.getByTestId('routine-superset-toggle').nth(0).check();

				await page.getByTestId('routine-save').click();
				// Lands on the detail screen.
				await expect(page.getByTestId('routine-exercises')).toBeVisible({ timeout: 10_000 });

				const { data: routines } = await admin
					.from('gym_routines')
					.select('id, exercise_count')
					.eq('author_id', USER_A.id)
					.eq('title', routineTitle);
				expect(routines?.length).toBe(1);
				expect(routines![0].exercise_count).toBe(2);
				routineId = routines![0].id as string;

				// The plan persisted: a shared superset group, ordered, with the
				// main lift carrying the linear scheme.
				const { data: exRows } = await admin
					.from('gym_routine_exercises')
					.select('id, exercise_name, position, superset_group, superset_order, progression')
					.eq('routine_id', routineId)
					.order('position', { ascending: true });
				expect(exRows?.length).toBe(2);
				expect(exRows![0].superset_group).not.toBeNull();
				expect(exRows![0].superset_group).toBe(exRows![1].superset_group);
				expect(exRows![0].superset_order).toBe(0);
				expect(exRows![1].superset_order).toBe(1);
				expect(exRows![0].progression).toBe('linear');

				const { data: mainSets } = await admin
					.from('gym_routine_sets')
					.select('target_reps_min, target_weight_kg')
					.eq('routine_exercise_id', exRows![0].id);
				expect(mainSets?.length).toBe(2);
				expect(Number(mainSets![0].target_weight_kg)).toBe(100);
			});

			// ── 2. The routine lists + its detail renders the planned targets ─
			await test.step('the routine lists in the library and its detail shows the plan', async () => {
				await page.goto('/gym/routines');
				await expect(page.getByTestId('routine-list')).toBeVisible({ timeout: 10_000 });
				await expect(page.locator('.routine-row', { hasText: routineTitle })).toBeVisible();

				await page.goto(`/gym/routines/${routineId}`);
				const exercises = page.getByTestId('routine-exercises');
				await expect(exercises).toContainText(mainLift, { timeout: 10_000 });
				await expect(exercises).toContainText(accessory);
			});

			// ── 3. Run the guided session, logging the superset round-robin ──
			await test.step('the guided runner interleaves the superset and logs every set', async () => {
				await page.goto(`/gym/session/${routineId}`);
				await expect(page.getByTestId('gym-session-runner')).toBeVisible({ timeout: 10_000 });
				const band = page.getByTestId('gym-exec-band');
				await expect(band).toBeVisible();

				// expandRoutineSteps emits A1, B1, A2 for the superset (main has two
				// sets, accessory one) — three steps total, interleaved.
				// Step 1 — main lift, set 1 of the round-robin, prefilled from plan.
				await expect(band).toContainText(mainLift);
				await expect(band).toContainText('Set 1/3');
				await expect(page.getByTestId('gym-set-reps')).toHaveValue('5');
				await expect(page.getByTestId('gym-set-weight')).toHaveValue('100');
				await page.getByTestId('gym-step-complete').click();

				// Step 2 — the superset partner (accessory), not the main lift's
				// second set.
				await expect(band).toContainText(accessory);
				await expect(band).toContainText('Set 2/3');
				await expect(page.getByTestId('gym-set-reps')).toHaveValue('8');
				await expect(page.getByTestId('gym-set-weight')).toHaveValue('40');
				await page.getByTestId('gym-step-complete').click();

				// Step 3 — back to the main lift for round two of the superset.
				await expect(band).toContainText(mainLift);
				await expect(band).toContainText('Set 3/3');
				await page.getByTestId('gym-step-complete').click();

				// All steps drained → the finish panel; save the session. The runner
				// persists one gym_workout linked to the routine, then client-side
				// goto()s to /gym/[id].
				await expect(page.getByTestId('gym-session-finish')).toBeVisible({ timeout: 10_000 });
				await page.getByTestId('gym-session-finish-save').click();
				await page.waitForURL(/\/gym\/[0-9a-f-]+$/, { timeout: 15_000 });
			});

			// ── 4. The adherence review on /gym/[id] (computeRoutineAdherence) ─
			await test.step('the detail screen shows a Completed adherence review', async () => {
				// Pin the workout id from the redirect URL. Do NOT hard-navigate
				// here: the runner reaches /gym/[id] via a client-side goto() with
				// the auth session already live, so the detail page's onMount fetch
				// is authenticated and the review renders. A full page.goto() reload
				// would re-fire that fetch before the Supabase session rehydrates
				// from storage, RLS would return no row, and the page would render
				// blank — so we assert on the SPA location the runner already landed.
				const landedUrl = new URL(page.url());
				const workoutId = landedUrl.pathname.split('/').pop() as string;
				expect(workoutId).toMatch(/^[0-9a-f-]+$/);
				workoutIds.push(workoutId);

				const review = page.getByTestId('gym-workout-review');
				await expect(review).toBeVisible({ timeout: 10_000 });
				// Every planned set logged at/above target → Completed.
				await expect(page.getByTestId('gym-review-verdict')).toHaveText('Completed');
				// The planned-vs-actual table reflects all three sets as hit (none
				// missed/partial). The status pill text 'Hit' appears per logged set.
				await expect(review.locator('.status-hit')).toHaveCount(3);

				// Cross-check the logged workout + sets, linked to the routine — by
				// the id we navigated to, so the backend row and the rendered review
				// are provably the same workout.
				const { data: created } = await admin
					.from('gym_workouts')
					.select('id, metadata')
					.eq('id', workoutId);
				expect(created?.length).toBe(1);
				expect(created![0].id).toBe(workoutId);

				const metadata = created![0].metadata as {
					routine_id: string;
					gym_adherence: string;
					gym_step_results: Array<{ exercise_key: string; set_index: number; status: string }>;
				};
				expect(metadata.routine_id).toBe(routineId);
				expect(metadata.gym_adherence).toBe('completed');
				// All three step results recorded as hit.
				expect(metadata.gym_step_results.every((s) => s.status === 'hit')).toBe(true);

				const { data: sets } = await admin
					.from('gym_sets')
					.select('exercise_name, reps, weight_kg')
					.eq('workout_id', workoutId);
				expect(sets?.length).toBe(3);
				const mainSets = sets!.filter((s) => s.exercise_name === mainLift);
				expect(mainSets.length).toBe(2);
				// Weight stored canonical kg (100), not lbs.
				expect(Number(mainSets[0].weight_kg)).toBe(100);
				expect(sets!.filter((s) => s.exercise_name === accessory).length).toBe(1);
			});

			// ── 5. The next-session progression suggestion (nextPrescription) ─
			await test.step('a next-session progression suggestion appears for the main lift', async () => {
				const targets = page.getByTestId('gym-next-targets');
				await expect(targets).toBeVisible();

				// The main lift hit its 5-rep target at the planned 100 kg under a
				// linear scheme → nextPrescription suggests adding load.
				const mainChip = page.getByTestId('gym-next-target').filter({ hasText: mainLift });
				await expect(mainChip).toBeVisible();
				await expect(mainChip).toContainText('Add load next time');
				// And a positive load delta (e.g. +2.5 kg) — never a decrease after
				// a clean target hit.
				await expect(mainChip).toContainText('+');

				// The accessory carries no scheme → no chip for it.
				await expect(
					page.getByTestId('gym-next-target').filter({ hasText: accessory }),
				).toHaveCount(0);
			});
		} finally {
			// ── 6. Tear down everything we created ───────────────────────────
			for (const id of workoutIds) await admin.from('gym_workouts').delete().eq('id', id);
			if (routineId) await admin.from('gym_routines').delete().eq('id', routineId);
		}
	});
});
