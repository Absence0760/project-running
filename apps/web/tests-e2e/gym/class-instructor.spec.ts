import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Two gym / strength-class instructor paths the existing specs miss:
 *
 * (a) A `class` event with NO gym_template (the instructor left the discipline
 *     blank) must NOT offer "Log this as a workout". event_class_gym_seam.spec
 *     covers the run + social negatives and the class-WITH-template positive,
 *     but the most common real miss — a class whose template is null — is
 *     untested, and it's the exact two-sided gate the seam doc calls out.
 * (b) The authored routine's Start button launches the guided runner.
 *     gym_session.spec drives /gym/session/[id] by URL; nobody enters via the
 *     routine-detail Start button, so a regression that reinstated the old
 *     prefill modal would pass unnoticed.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('gym class instructor — seam gate + routine start', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdEventIds: string[] = [];
	const createdRoutineIds: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of createdEventIds.splice(0)) {
			try {
				await deleteEvent(id);
			} catch (_) {
				/* best-effort */
			}
		}
		for (const id of createdRoutineIds.splice(0)) {
			try {
				await admin.from('gym_routines').delete().eq('id', id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('a class with no gym_template offers NO log-as-workout button', async ({ page }) => {
		const title = `e2e-class-notemplate ${Date.now()}`;
		// category 'class' but no discipline / gym_template — the column stays
		// null, so the inform-tier log affordance must self-hide.
		const id = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title,
			category: 'class',
			starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
		});
		createdEventIds.push(id);

		// Guard the precondition: the seed really produced a null template.
		const { data: row } = await getAdminClient()
			.from('events')
			.select('category, gym_template')
			.eq('id', id)
			.single();
		expect(row?.category).toBe('class');
		expect(row?.gym_template).toBeNull();

		await page.goto(`/clubs/richmond-run-club/events/${id}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('log-as-workout')).toHaveCount(0);
	});

	test('the routine-detail Start button launches the guided runner', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const exercise = `E2E Squat ${stamp}`;

		const { data: routine, error } = await admin
			.from('gym_routines')
			.insert({ author_id: USER_A.id, title: `E2E Class Routine ${stamp}`, exercise_count: 1 })
			.select('id')
			.single();
		if (error || !routine) throw error ?? new Error('seed routine failed');
		const routineId = routine.id as string;
		createdRoutineIds.push(routineId);

		const { data: ex } = await admin
			.from('gym_routine_exercises')
			.insert({
				routine_id: routineId,
				exercise_name: exercise,
				exercise_key: exercise.trim().toLowerCase(),
				position: 0
			})
			.select('id')
			.single();
		await admin.from('gym_routine_sets').insert({
			routine_exercise_id: ex!.id,
			set_index: 0,
			target_reps_min: 5,
			target_weight_kg: 80
		});

		await page.goto(`/gym/routines/${routineId}`);
		await page.getByTestId('routine-start').click();

		await page.waitForURL(new RegExp(`/gym/session/${routineId}$`), { timeout: 10_000 });
		await expect(page.getByTestId('gym-session-runner')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('gym-exec-band')).toContainText(exercise);
	});
});
