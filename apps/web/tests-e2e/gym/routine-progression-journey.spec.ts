import { expect, test, type Page } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Gym routine + progression-signal journey — the progressive-overload story
 * walked across every gym surface that renders a "vs last time" / "since first
 * session" signal, on a CLEAN, fully-owned canvas (one ephemeral saga user with
 * zero gym history), so each delta the UI computes is unambiguous.
 *
 * The two existing long-form gym specs each own a different arc:
 *   - gym-lifecycle-journey.spec.ts: log → PR badge → records → save-as-routine →
 *     repeat-last → progression LIST (asserts the /gym/exercise page lists both
 *     sessions and both carry a PR badge — but never the per-exercise
 *     progression *delta* signals).
 *   - gym-routine-runner-journey.spec.ts: author a routine → guided runner →
 *     adherence → nextPrescription chip (the authoring-end + guided-runner arc).
 *
 * This journey owns the UNCOVERED slice: the progressive-overload CUES that the
 * all-time PR chips can't give —
 *   1. the /gym/[id] per-exercise "vs last time" hint (exercise_history.ts#
 *      previousExerciseSession → the .last-time row: prior session's top set +
 *      a signed delta on this session's heaviest set), which is ABSENT on the
 *      first-ever session and APPEARS (with a + up-delta) on the second, and
 *   2. the /gym/exercise headline est.-1RM delta ("up {delta} since first
 *      session" → .delta.delta-up), which only exists once ≥2 sessions carry an
 *      e1RM (exercise_history.ts#exerciseProgress.est1RmDeltaKg).
 *
 * The thread, all from the /gym create + repeat-last UI (canonical kg entry):
 *   1. Log session 1 of a brand-new exercise (5 @ 100 kg). On /gym it's a PR
 *      (first-ever lift). On /gym/[id] there is NO "vs last time" row yet.
 *   2. Save it as a reusable routine (routineFromWorkout → RoutineEditor),
 *      cross-checked in gym_routines.
 *   3. Repeat-last → a fresh log prefilled from session 1, bumped to 110 kg.
 *      On session 2's /gym/[id] the "vs last time" row now renders: it cites
 *      session 1's "100 kg × 5" and shows a +10 kg up-delta.
 *   4. /gym/records: the exercise's current-best card flips to 110 kg × 5.
 *   5. /gym/exercise: TWO sessions, both PR badges, and the headline shows an
 *      "up … since first session" est.-1RM delta in the up direction.
 *   6. A THIRD heavier session (120 kg) via repeat-last, so the progression
 *      delta climbs again — the "are you getting stronger" signal is monotone,
 *      not a one-off. /gym/[id] cites session 2's 110 with a +10 up-delta;
 *      /gym/exercise now lists three sessions, three PR badges, headline still up.
 *   7. Tear everything down (both helper drops the saga user + cascades, but we
 *      also wipe the routine + workouts explicitly in case the saga delete races).
 *
 * A unique stamped exercise name keeps every record / progression assertion
 * unambiguous and pins cleanup. Weight is entered in the editor's display unit;
 * the saga user defaults to km/kg (createSagaUsers upserts preferred_unit 'km',
 * weight_unit unset → kg), so '100' in the field stores 100 kg canonical and the
 * UI renders '100 kg'. Gym workout creation is not rate-limited, so no reset.
 */
test.describe('gym routine + progression-signal journey — log → save-as-routine → repeat heavier → vs-last-time + since-first deltas', () => {
	test('progressive overload threads the vs-last-time hint and the since-first est.-1RM delta across the gym surfaces', async ({
		browser,
	}) => {
		const admin = getAdminClient();
		const stamp = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const exercise = `e2e-prog-ex-${stamp}`;
		const s1Title = `${exercise} session 1`;
		const s2Title = `${exercise} session 2`;
		const s3Title = `${exercise} session 3`;
		const routineTitle = `${exercise} routine`;

		let users: SagaUser[] = [];
		const workoutIds: string[] = [];
		let routineId: string | null = null;

		// Fill one weighted exercise (single set) into an open GymEditor and save.
		// The editor opens with one exercise + one set; we fill the title, the
		// exercise name, then the set's reps + weight inputs by index. Weight is a
		// type=number input → stored canonical kg.
		async function logViaEditor(page: Page, title: string, reps: string, weightKg: string) {
			await page.getByPlaceholder('e.g. Push day').fill(title);
			await page.getByPlaceholder('Exercise name').first().fill(exercise);
			const setRow = page.locator('.set-row').first();
			await setRow.locator('input[type="number"]').nth(0).fill(reps); // reps
			await setRow.locator('input[type="number"]').nth(1).fill(weightKg); // weight kg
			await page.getByRole('button', { name: 'Save workout' }).click();
		}

		async function captureWorkoutId(userId: string, title: string): Promise<string> {
			const { data } = await admin
				.from('gym_workouts')
				.select('id')
				.eq('user_id', userId)
				.eq('title', title);
			expect(data?.length).toBe(1);
			return data![0].id as string;
		}

		try {
			users = await createSagaUsers(1, { displayNames: ['Progression Saga'] });
			const user = users[0];
			const ctx = await browser.newContext({ storageState: user.storageStatePath });
			const page = await ctx.newPage();

			try {
				// ── 1. Log session 1 of a brand-new exercise (5 @ 100 kg) ────────
				await test.step('log session 1 (5 @ 100 kg) — a first-ever-lift PR, no "vs last time" yet', async () => {
					await page.goto('/gym');
					await page.getByTestId('gym-log').click();
					await logViaEditor(page, s1Title, '5', '100');

					const row = page.locator('.workout-row', { hasText: s1Title });
					await expect(row).toBeVisible({ timeout: 10_000 });
					// First-ever lift of this exercise is always a PR.
					await expect(row.locator('.pr-badge')).toBeVisible();

					const id = await captureWorkoutId(user.id, s1Title);
					workoutIds.push(id);

					// On session 1's detail the exercise block renders with NO
					// "vs last time" row — there is no earlier session to compare to.
					await page.goto(`/gym/${id}`);
					const block = page.locator('.exercise-block', { hasText: exercise });
					await expect(block).toBeVisible({ timeout: 10_000 });
					await expect(block.locator('.last-time')).toHaveCount(0);
					await expect(block.locator('.sets li:not(.sets-head)').first()).toContainText('100');
				});

				// ── 2. Save session 1 as a reusable routine ──────────────────────
				await test.step('save session 1 as a routine (routineFromWorkout → RoutineEditor)', async () => {
					await page.goto(`/gym/${workoutIds[0]}`);
					await page.getByTestId('gym-save-as-routine').click();
					// The RoutineEditor opens prefilled from the workout.
					await expect(page.getByTestId('routine-title')).toHaveValue(s1Title, {
						timeout: 10_000,
					});
					await expect(page.getByTestId('routine-exercise-name').first()).toHaveValue(exercise);
					// Rename so the routine title can't collide with the workout title
					// in the backend lookup.
					await page.getByTestId('routine-title').fill(routineTitle);
					await page.getByTestId('routine-save').click();
					await expect(page.locator('.toast', { hasText: 'Routine saved' })).toBeVisible({
						timeout: 10_000,
					});

					const { data: routines } = await admin
						.from('gym_routines')
						.select('id, exercise_count')
						.eq('author_id', user.id)
						.eq('title', routineTitle);
					expect(routines?.length).toBe(1);
					expect(routines![0].exercise_count).toBe(1);
					routineId = routines![0].id as string;
				});

				// ── 3. Repeat-last heavier → session 2's "vs last time" hint ─────
				await test.step('repeat-last heavier (110 kg) → session 2 cites session 1 + a +10 up-delta', async () => {
					await page.goto(`/gym/${workoutIds[0]}`);
					await page.getByTestId('gym-repeat-last').click();
					// GymEditor opens prefilled with session 1's exercise.
					await expect(page.getByPlaceholder('Exercise name').first()).toHaveValue(exercise, {
						timeout: 10_000,
					});
					// New title + heavier top set.
					await page.getByPlaceholder('e.g. Push day').fill(s2Title);
					const setRow = page.locator('.set-row').first();
					await setRow.locator('input[type="number"]').nth(0).fill('5'); // reps
					await setRow.locator('input[type="number"]').nth(1).fill('110'); // weight kg
					await page.getByRole('button', { name: 'Save workout' }).click();
					await expect(page).toHaveURL(/\/gym$/, { timeout: 10_000 });

					const id = await captureWorkoutId(user.id, s2Title);
					workoutIds.push(id);

					// Session 2's detail: the "vs last time" row NOW renders against
					// session 1.
					await page.goto(`/gym/${id}`);
					const block = page.locator('.exercise-block', { hasText: exercise });
					await expect(block).toBeVisible({ timeout: 10_000 });
					const lastTime = block.locator('.last-time');
					await expect(lastTime).toBeVisible();
					// It cites session 1's top set (100 kg × 5).
					await expect(lastTime.locator('.lt-text')).toContainText('100 kg × 5');
					// And the heaviest set climbed +10 kg → an UP delta (.lt-up).
					const delta = lastTime.locator('.lt-delta.lt-up');
					await expect(delta).toBeVisible();
					await expect(delta).toContainText('+');
					await expect(delta).toContainText('10');
					// The hint links to this exercise's progression page.
					await expect(lastTime).toHaveAttribute('href', /\/gym\/exercise\?name=/);
				});

				// ── 4. Records page: current best flips to 110 kg × 5 ────────────
				await test.step('/gym/records shows the exercise current best (110 kg × 5)', async () => {
					await page.goto('/gym');
					const recordsLink = page.getByTestId('gym-records-link');
					await expect(recordsLink).toBeVisible({ timeout: 10_000 });
					await recordsLink.click();
					await expect(page).toHaveURL(/\/gym\/records$/);

					const card = page.locator('.record-card', { hasText: exercise });
					await expect(card).toBeVisible({ timeout: 10_000 });
					// Heaviest line = 110 kg × 5; "2 sessions" so far.
					await expect(card).toContainText('110 kg × 5');
					await expect(card).toContainText('2 sessions');
				});

				// ── 5. /gym/exercise: two sessions + the "since first" up-delta ──
				await test.step('/gym/exercise lists both sessions, both PR, headline shows "up … since first session"', async () => {
					await page.goto('/gym/records');
					const card = page.locator('.record-card', { hasText: exercise });
					await expect(card).toBeVisible({ timeout: 10_000 });
					await card.click();
					await expect(page).toHaveURL(/\/gym\/exercise\?name=/);

					const rows = page.locator('.session-row');
					await expect(rows).toHaveCount(2);
					// The heavier (latest) session's top-set line.
					await expect(
						page.locator('.session-row', { hasText: '110 kg × 5' }),
					).toBeVisible();
					// Both sessions raised the heaviest weight (100 then 110) AND the est.
					// 1RM, so each carries a Heaviest + a Best-est.-1RM PR badge → four total.
					await expect(page.locator('.session-row .pr-badge')).toHaveCount(4);
					await expect(
						page.locator('.session-row .pr-badge', { hasText: 'Heaviest' }),
					).toHaveCount(2);
					await expect(
						page.locator('.session-row .pr-badge', { hasText: 'Best est. 1RM' }),
					).toHaveCount(2);
					// The headline est.-1RM delta is in the UP direction (latest e1RM
					// from 110 > first from 100), rendered via gym.exercise.sinceFirstUp.
					const delta = page.locator('.head .delta.delta-up');
					await expect(delta).toBeVisible();
					await expect(delta).toContainText('since first session');
				});

				// ── 6. A third heavier session keeps the progression climbing ────
				await test.step('repeat-last again (120 kg) → session 3 cites session 2 (+10) and the progression climbs', async () => {
					await page.goto(`/gym/${workoutIds[1]}`);
					await page.getByTestId('gym-repeat-last').click();
					await expect(page.getByPlaceholder('Exercise name').first()).toHaveValue(exercise, {
						timeout: 10_000,
					});
					await page.getByPlaceholder('e.g. Push day').fill(s3Title);
					const setRow = page.locator('.set-row').first();
					await setRow.locator('input[type="number"]').nth(0).fill('5'); // reps
					await setRow.locator('input[type="number"]').nth(1).fill('120'); // weight kg
					await page.getByRole('button', { name: 'Save workout' }).click();
					await expect(page).toHaveURL(/\/gym$/, { timeout: 10_000 });

					const id = await captureWorkoutId(user.id, s3Title);
					workoutIds.push(id);

					// Session 3's "vs last time" cites session 2's 110 kg × 5 with a
					// fresh +10 up-delta — the cue is per-session, not one-off.
					await page.goto(`/gym/${id}`);
					const block = page.locator('.exercise-block', { hasText: exercise });
					await expect(block).toBeVisible({ timeout: 10_000 });
					const lastTime = block.locator('.last-time');
					await expect(lastTime.locator('.lt-text')).toContainText('110 kg × 5');
					await expect(lastTime.locator('.lt-delta.lt-up')).toContainText('10');

					// The progression page now lists three sessions; each raised both the
					// heaviest weight and the est. 1RM → a Heaviest + a Best-est.-1RM badge
					// per session, six total. Headline still up.
					await page.goto(`/gym/exercise?name=${encodeURIComponent(exercise)}`);
					await expect(page.locator('.session-row')).toHaveCount(3);
					await expect(page.locator('.session-row .pr-badge')).toHaveCount(6);
					await expect(
						page.locator('.session-row .pr-badge', { hasText: 'Heaviest' }),
					).toHaveCount(3);
					await expect(
						page.locator('.session-row .pr-badge', { hasText: 'Best est. 1RM' }),
					).toHaveCount(3);
					await expect(
						page.locator('.session-row', { hasText: '120 kg × 5' }),
					).toBeVisible();
					await expect(page.locator('.head .delta.delta-up')).toContainText(
						'since first session',
					);

					// Backend cross-check: three weighted workouts for this exercise,
					// one routine, all owned by the saga user.
					const { data: sets } = await admin
						.from('gym_sets')
						.select('weight_kg, reps')
						.in('workout_id', workoutIds)
						.eq('exercise_name', exercise)
						.order('weight_kg', { ascending: true });
					expect(sets?.length).toBe(3);
					expect(sets!.map((s) => Number(s.weight_kg))).toEqual([100, 110, 120]);
				});
			} finally {
				await ctx.close();
			}
		} finally {
			// Explicit gym teardown first (the saga user delete cascades these too,
			// but an explicit wipe makes cleanup robust to a saga-delete race and
			// leaves the shared seed DB clean even if deleteSagaUsers logs a warning).
			if (routineId) await admin.from('gym_routines').delete().eq('id', routineId);
			for (const id of workoutIds) await admin.from('gym_workouts').delete().eq('id', id);
			if (users.length > 0) await deleteSagaUsers(users);
		}
	});
});
