import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Gym / strength-class instructor depth — the two journeys the existing
 * class specs don't combine (persona-gym-class-instructor #3 + #4):
 *
 * (a) One UI create that carries ALL THREE instructor-critical columns at
 *     once — discipline + capacity + weekly recurrence. event-category-typed
 *     covers discipline, event-recurring covers recurrence; nothing proved
 *     they survive the same round-trip together.
 * (b) A class with an ATTACHED SESSION PLAN prefills "Log as workout" with
 *     the session's movements (workoutDraftFromSession), not just the flat
 *     gym_template title — the attendee logs the class content.
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('gym class instructor — recurring capacity class + session-prefilled log', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const createdEventIds: string[] = [];
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
		for (const id of createdEventIds.splice(0)) {
			try {
				await deleteEvent(id);
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

	test('weekly Strength class with capacity 8 round-trips discipline + capacity + recurrence', async ({
		page
	}) => {
		const title = `e2e-class-weekly ${Date.now()}`;
		const discipline = 'Strength';
		const startDate = new Date(Date.now() + 7 * 24 * 3600 * 1000);
		const startIso = startDate.toISOString().slice(0, 10);
		const untilIso = new Date(Date.now() + 28 * 24 * 3600 * 1000)
			.toISOString()
			.slice(0, 10);

		await page.goto('/clubs/richmond-run-club/events/new');
		await expect(page.getByRole('heading', { level: 1, name: 'New event' })).toBeVisible({
			timeout: 10_000
		});

		await page.getByRole('radio', { name: 'Class', exact: true }).click();
		await page.getByPlaceholder('Sunday long run').fill(title);
		await page.getByPlaceholder(/Vinyasa yoga/).fill(discipline);
		await page.locator('input[type="date"]').first().fill(startIso);
		await page.locator('input[type="time"]').first().fill('18:00');
		await page.locator('input[type="number"][min="1"]').first().fill('8');

		await page.getByRole('radio', { name: 'Weekly' }).check();
		await page.locator('fieldset input[type="date"]').fill(untilIso);

		await page.getByRole('button', { name: /Create event/ }).click();
		await page.waitForURL(/\/clubs\/richmond-run-club\/events\/[0-9a-f-]+$/, {
			timeout: 10_000
		});
		const id = page.url().match(/\/events\/([0-9a-f-]+)$/)![1];
		createdEventIds.push(id);

		// All four instructor-critical columns survive the one round-trip.
		const { data: row } = await getAdminClient()
			.from('events')
			.select('category, discipline, capacity, recurrence_freq')
			.eq('id', id)
			.single();
		expect(row?.category).toBe('class');
		expect(row?.discipline).toBe(discipline);
		expect(row?.capacity).toBe(8);
		expect(row?.recurrence_freq).toBe('weekly');

		// Detail: discipline label + recurring instance chips render; the
		// athletic affordances stay hidden for a class.
		await expect(page.getByRole('heading', { name: title })).toBeVisible({
			timeout: 10_000
		});
		await expect(page.getByText(discipline).first()).toBeVisible();
		expect(await page.locator('.instance-chip').count()).toBeGreaterThan(1);
		await expect(page.getByText('Submit my time')).toHaveCount(0);
		await expect(page.getByText('Target pace')).toHaveCount(0);
		// Capacity renders as "going / capacity" once the attendee count shows.
		await expect(page.getByText('/ 8').first()).toBeVisible();
	});

	test('log-as-workout on a class with an attached session plan prefills the movements', async ({
		page
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const discipline = `Mat Pilates ${stamp}`;

		const { data: planRow, error: planErr } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title: `e2e-prefill-plan ${stamp}`, discipline })
			.select('id')
			.single();
		expect(planErr).toBeNull();
		const planId = planRow!.id as string;
		createdPlanIds.push(planId);
		await admin.from('session_plan_items').insert([
			{ plan_id: planId, position: 0, movement_name: 'Cat Cow', kind: 'flow', duration_s: 30 },
			{ plan_id: planId, position: 1, movement_name: 'Child Pose', kind: 'reps', reps: 5 }
		]);

		const title = `e2e-class-session ${stamp}`;
		const { data: eventRow, error: eventErr } = await admin
			.from('events')
			.insert({
				club_id: RICHMOND_CLUB_ID,
				author_id: USER_A.id,
				title,
				category: 'class',
				discipline,
				starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString(),
				duration_min: 45,
				gym_template: { discipline, duration_min: 45 },
				session_plan_id: planId
			})
			.select('id')
			.single();
		expect(eventErr).toBeNull();
		const eventId = eventRow!.id as string;
		createdEventIds.push(eventId);

		await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

		await page.getByTestId('log-as-workout').click();
		const modal = page.locator('.modal', { hasText: 'Log this as a workout' });
		await expect(modal).toBeVisible({ timeout: 5_000 });

		// The composer is seeded from workoutDraftFromSession: title from the
		// class discipline, one exercise block per session movement — not just
		// the flat template title over an empty block.
		await expect(modal.getByPlaceholder('e.g. Push day')).toHaveValue(discipline);
		const names = modal.locator('input.exercise-name');
		await expect(names.nth(0)).toHaveValue('Cat Cow');
		await expect(names.nth(1)).toHaveValue('Child Pose');

		await modal.getByRole('button', { name: 'Save workout' }).click();
		await expect(modal).toHaveCount(0, { timeout: 10_000 });

		// The saved workout carries the session-derived title + both movements.
		await expect
			.poll(
				async () => {
					const { data } = await admin
						.from('gym_workouts')
						.select('id, title')
						.eq('user_id', USER_A.id)
						.eq('title', discipline);
					const match = (data ?? [])[0];
					if (match) createdWorkoutIds.push(match.id as string);
					return match?.id ?? null;
				},
				{ timeout: 10_000 }
			)
			.not.toBeNull();
		const workoutId = createdWorkoutIds[0];
		const { data: sets } = await admin
			.from('gym_sets')
			.select('exercise_name')
			.eq('workout_id', workoutId)
			.order('set_index');
		expect((sets ?? []).map((s) => s.exercise_name)).toEqual(['Cat Cow', 'Child Pose']);
	});
});
