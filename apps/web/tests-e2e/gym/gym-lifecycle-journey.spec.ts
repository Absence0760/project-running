import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Gym lifecycle journey — the full life of a weighted gym workout walked
 * through every surface it touches, plus the routine-reuse loop.
 *
 * This is the long-form companion to the focused single-surface gym specs
 * (gym.spec.ts, records.spec.ts, routines.spec.ts, exercise_history.spec.ts):
 * one user, one unique exercise, carried end to end so each step builds on
 * the state the previous one left behind.
 *
 *   1. Log a brand-new weighted workout via the /gym create modal (GymEditor):
 *      title + one weighted exercise (5 reps @ 100 kg).
 *   2. It lands on the /gym list with a PR badge (first-ever lift of this
 *      exercise is always a PR — gym_prs.ts).
 *   3. Open /gym/[id] detail: the exercise block + its per-exercise PR chip +
 *      the set value render.
 *   4. /gym/records: the per-exercise current-best card shows the heaviest set.
 *   5. Save that workout as a reusable routine (gym-save-as-routine → the
 *      RoutineEditor prefilled from gym/gym_routine.ts#routineFromWorkout).
 *   6. Repeat-last: start a fresh log prefilled from the first session
 *      (gym-repeat-last → GymEditor prefilled), bumping to 110 kg, and save —
 *      a second, distinct workout.
 *   7. /gym/exercise?name=<name>: the progression page now lists TWO sessions,
 *      the heavier one carrying an est.-1RM PR.
 *   8. Tear everything down — both workouts and the routine — so the shared
 *      seed DB is left clean.
 *
 * A unique exercise name (never used by the seed data) keeps every
 * PR / records / progression assertion unambiguous, and pins cleanup so it
 * can't collide with another run's rows. Gym workout creation is NOT
 * rate-limited (no rate_limits bucket for it — unlike clubs/routes), so no
 * resetRateLimit is needed here.
 */
test.describe('gym lifecycle journey — log → PR → records → save-as-routine → repeat → progression', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a workout lives its full life across the gym surfaces, then reuses as a routine', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const exercise = `e2e-gym-journey-ex-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const firstTitle = `${exercise} session 1`;
		const secondTitle = `${exercise} session 2`;
		const routineTitle = `${exercise} routine`;

		// Track everything we create so the finally{} below can wipe it even if
		// an assertion fails mid-journey.
		const workoutIds: string[] = [];
		let routineId: string | null = null;

		try {
			// ── 1. Log a new weighted workout via the /gym create modal ──────
			await test.step('log a new weighted workout (5 @ 100 kg)', async () => {
				await page.goto('/gym');
				await page.getByTestId('gym-log').click();
				await page.getByPlaceholder('e.g. Push day').fill(firstTitle);
				await page.getByPlaceholder('Exercise name').first().fill(exercise);
				const setRow = page.locator('.set-row').first();
				await setRow.locator('input[type="number"]').nth(0).fill('5'); // reps
				await setRow.locator('input[type="number"]').nth(1).fill('100'); // weight kg
				await page.getByRole('button', { name: 'Save workout' }).click();
			});

			// ── 2. It appears on the /gym list with a PR badge ───────────────
			await test.step('the workout appears on /gym with a PR badge', async () => {
				const row = page.locator('.workout-row', { hasText: firstTitle });
				await expect(row).toBeVisible({ timeout: 10_000 });
				// First-ever lift of this exercise is always a PR.
				await expect(row.locator('.pr-badge')).toBeVisible();

				const { data: created } = await admin
					.from('gym_workouts')
					.select('id')
					.eq('user_id', USER_A.id)
					.eq('title', firstTitle);
				expect(created?.length).toBe(1);
				workoutIds.push(created![0].id as string);
			});

			// ── 3. Detail screen: exercise block + per-exercise PR chip ──────
			await test.step('the /gym/[id] detail renders the exercise + PR chip + set value', async () => {
				const firstWorkoutId = workoutIds[0];
				await page.goto(`/gym/${firstWorkoutId}`);
				const block = page.locator('.exercise-block', { hasText: exercise });
				await expect(block).toBeVisible({ timeout: 10_000 });
				await expect(block.locator('.pr-chip').first()).toBeVisible();
				await expect(block.locator('.sets li:not(.sets-head)').first()).toContainText('100');
			});

			// ── 4. Records page: this exercise's current best ────────────────
			await test.step('/gym/records shows the exercise current best (100 kg × 5)', async () => {
				await page.goto('/gym');
				const recordsLink = page.getByTestId('gym-records-link');
				await expect(recordsLink).toBeVisible({ timeout: 10_000 });
				await recordsLink.click();
				await expect(page).toHaveURL(/\/gym\/records$/);

				const card = page.locator('.record-card', { hasText: exercise });
				await expect(card).toBeVisible({ timeout: 10_000 });
				// "× 5" is the heaviest-set rep suffix — unambiguous against the
				// digits in the Date.now()-stamped exercise name.
				await expect(card).toContainText('100 kg × 5');
			});

			// ── 5. Save the workout as a reusable routine ────────────────────
			await test.step('save the workout as a routine via gym-save-as-routine', async () => {
				const firstWorkoutId = workoutIds[0];
				await page.goto(`/gym/${firstWorkoutId}`);
				await page.getByTestId('gym-save-as-routine').click();
				// The RoutineEditor opens prefilled with the workout title + exercise.
				await expect(page.getByTestId('routine-title')).toHaveValue(firstTitle, {
					timeout: 10_000,
				});
				await expect(page.getByTestId('routine-exercise-name').first()).toHaveValue(exercise);
				// Rename the routine so its title is distinct from the workout's,
				// keeping the backend lookup below unambiguous.
				await page.getByTestId('routine-title').fill(routineTitle);
				await page.getByTestId('routine-save').click();
				await expect(page.locator('.toast', { hasText: 'Routine saved' })).toBeVisible({
					timeout: 10_000,
				});

				const { data: routines } = await admin
					.from('gym_routines')
					.select('id, exercise_count')
					.eq('author_id', USER_A.id)
					.eq('title', routineTitle);
				expect(routines?.length).toBe(1);
				expect(routines![0].exercise_count).toBe(1);
				routineId = routines![0].id as string;
			});

			// ── 6. Repeat-last: a fresh log prefilled from the first session ──
			await test.step('repeat-last starts a prefilled new log (110 kg) and saves', async () => {
				const firstWorkoutId = workoutIds[0];
				await page.goto(`/gym/${firstWorkoutId}`);
				await page.getByTestId('gym-repeat-last').click();
				// GymEditor opens prefilled with the prior exercise.
				await expect(page.getByPlaceholder('Exercise name').first()).toHaveValue(exercise, {
					timeout: 10_000,
				});
				// Give the new session its own title + a heavier top set so it
				// sets a fresh est.-1RM PR.
				await page.getByPlaceholder('e.g. Push day').fill(secondTitle);
				const setRow = page.locator('.set-row').first();
				await setRow.locator('input[type="number"]').nth(0).fill('5'); // reps
				await setRow.locator('input[type="number"]').nth(1).fill('110'); // weight kg
				await page.getByRole('button', { name: 'Save workout' }).click();
				await expect(page).toHaveURL(/\/gym$/, { timeout: 10_000 });

				const row = page.locator('.workout-row', { hasText: secondTitle });
				await expect(row).toBeVisible({ timeout: 10_000 });

				const { data: created } = await admin
					.from('gym_workouts')
					.select('id')
					.eq('user_id', USER_A.id)
					.eq('title', secondTitle);
				expect(created?.length).toBe(1);
				workoutIds.push(created![0].id as string);
			});

			// ── 7. Progression page lists both sessions, PR on the heavier ───
			await test.step('/gym/exercise lists both sessions with a PR on the heavier one', async () => {
				await page.goto('/gym/records');
				const card = page.locator('.record-card', { hasText: exercise });
				await expect(card).toBeVisible({ timeout: 10_000 });
				await card.click();
				await expect(page).toHaveURL(/\/gym\/exercise\?name=/);

				const rows = page.locator('.session-row');
				await expect(rows).toHaveCount(2);
				// The heavier session's top-set line.
				await expect(page.locator('.session-row', { hasText: '110 kg × 5' })).toBeVisible();
				// Both sessions beat the running best at their time, so both carry
				// an est.-1RM PR badge (first-ever 100, then the new-best 110).
				await expect(page.locator('.session-row .pr-badge')).toHaveCount(2);
			});
		} finally {
			// ── 8. Tear down everything we created ───────────────────────────
			if (routineId) await admin.from('gym_routines').delete().eq('id', routineId);
			for (const id of workoutIds) await admin.from('gym_workouts').delete().eq('id', id);
		}
	});
});
