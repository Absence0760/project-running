import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * The client (attendee / student) side of an instructor's class — the
 * north-star cross-modal payoff (instructor_business.md: "the class lands in
 * the student's Train history"). The existing seam + runner specs stop at the
 * DB write; nothing follows the workout through to the surfaces the STUDENT
 * actually looks at. These do:
 *
 * (a) A non-host attendee one-tap-logs a class via the seam, and the workout
 *     then appears in THEIR OWN /gym list and /history timeline.
 * (b) A participant who completes a follow-along session (the content an
 *     instructor attaches to a class) finds the logged session in their /gym +
 *     /history.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('class attendee — the class lands in the student history (seam)', () => {
	// USER_C_PRO is a non-host viewer (a student), not the Richmond organiser.
	test.use({ storageState: USER_C_PRO.storageStatePath });

	const createdEvents: string[] = [];
	const createdWorkouts: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of createdWorkouts.splice(0)) {
			try {
				await admin.from('gym_workouts').delete().eq('id', id);
			} catch (_) {
				/* best-effort */
			}
		}
		for (const id of createdEvents.splice(0)) {
			try {
				await deleteEvent(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('a student logs a class as a workout; it shows in their /gym + /history', async ({
		page
	}) => {
		// A class the instructor (USER_A) hosts, templated so the seam is offered.
		const discipline = `Vinyasa ${Date.now()}`;
		const eventId = await insertEvent({
			club_id: RICHMOND_CLUB_ID,
			author_id: USER_A.id,
			title: `e2e-attendee-class ${Date.now()}`,
			category: 'class',
			discipline,
			gym_template: { discipline, duration_min: 45 },
			starts_at: new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString()
		});
		createdEvents.push(eventId);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		const logBtn = page.getByTestId('log-as-workout');
		await expect(logBtn).toBeVisible({ timeout: 10_000 });
		await logBtn.click();

		const gymModal = page.locator('.modal', { hasText: 'Log this as a workout' });
		await expect(gymModal).toBeVisible({ timeout: 5_000 });
		// The composer pre-fills the title from the class discipline.
		await expect(gymModal.getByPlaceholder('e.g. Push day')).toHaveValue(discipline);
		await gymModal.getByPlaceholder('Exercise name').fill('Sun salutation');
		await gymModal.getByLabel('Reps', { exact: true }).first().fill('10');
		await gymModal.getByRole('button', { name: 'Save workout' }).click();
		await expect(gymModal).toHaveCount(0, { timeout: 10_000 });

		// Track the created workout for cleanup.
		const admin = getAdminClient();
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('gym_workouts')
						.select('id')
						.eq('user_id', USER_C_PRO.id)
						.eq('title', discipline);
					for (const w of data ?? []) createdWorkouts.push(w.id as string);
					return (data ?? []).length;
				},
				{ timeout: 10_000 }
			)
			.toBeGreaterThan(0);

		// The student's OWN gym surface now lists the class workout.
		await page.goto('/gym');
		await expect(page.locator('.workout-row', { hasText: discipline })).toBeVisible({
			timeout: 10_000
		});

		// And it shows on the unified history timeline under the Lifts chip.
		await page.goto('/history');
		await page.getByRole('button', { name: 'Lifts', exact: true }).click();
		await expect(page.locator('.timeline-row', { hasText: discipline })).toBeVisible({
			timeout: 10_000
		});
	});
});

test.describe('follow-along participant — the session lands in their history', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdPlanIds: string[] = [];
	const createdWorkoutIds: string[] = [];

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of createdWorkoutIds.splice(0)) {
			try {
				await admin.from('gym_workouts').delete().eq('id', id);
			} catch (_) {
				/* best-effort */
			}
		}
		for (const id of createdPlanIds.splice(0)) {
			try {
				await admin.from('session_plans').delete().eq('id', id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('completing a follow-along session surfaces it in /gym + /history', async ({ page }) => {
		const admin = getAdminClient();
		const discipline = `Reformer ${Date.now()}`;
		const { data: planRow } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title: `e2e-payoff ${Date.now()}`, discipline })
			.select('id, title')
			.single();
		const planId = planRow!.id as string;
		const title = planRow!.title as string;
		createdPlanIds.push(planId);
		await admin.from('session_plan_items').insert([
			{ plan_id: planId, position: 0, movement_name: 'Roll Down', kind: 'flow', duration_s: 2 },
			{ plan_id: planId, position: 1, movement_name: 'The Hundred', kind: 'reps', reps: 100 }
		]);

		// Run the follow-along to completion.
		await page.goto(`/sessions/${planId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		await page.getByTestId('session-start').click();
		const runner = page.getByTestId('session-runner');
		const band = runner.getByTestId('session-execution-band');
		// The 2s flow auto-advances to the reps step; Done on the last finishes.
		await expect(band.getByTestId('session-step-name')).toHaveText('The Hundred', {
			timeout: 10_000
		});
		await band.getByTestId('session-done').click();
		await expect(runner).toBeHidden({ timeout: 10_000 });
		await expect(page.getByText('Session saved.')).toBeVisible({ timeout: 10_000 });

		// The logged session (titled from the plan discipline) is in the gym log.
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('gym_workouts')
						.select('id, metadata')
						.eq('user_id', USER_A.id);
					const match = (data ?? []).find(
						(w) => (w.metadata as Record<string, unknown>)?.session_plan_id === planId
					);
					if (match) createdWorkoutIds.push(match.id as string);
					return !!match;
				},
				{ timeout: 10_000 }
			)
			.toBe(true);

		await page.goto('/gym');
		await expect(page.locator('.workout-row', { hasText: discipline })).toBeVisible({
			timeout: 10_000
		});

		await page.goto('/history');
		await page.getByRole('button', { name: 'Lifts', exact: true }).click();
		await expect(page.locator('.timeline-row', { hasText: discipline })).toBeVisible({
			timeout: 10_000
		});
	});
});
