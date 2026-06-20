import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { setUserSetting } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /gym — the Phase 4 multi-modal gym module (decisions §63,
 * docs/features/multi_modal.md § Gym).
 *
 * Covers the lightweight-tier loop end to end: log a free-form workout
 * (title + exercise + sets), see it on the list with a PR badge (first
 * time an exercise is logged is always a PR — gym_prs.ts), open the
 * detail screen and confirm the per-exercise PR chip + set rows, then
 * delete it. The /gym route is always reachable (the Gym sidebar item is
 * always present now — decisions §63 amendment ungated it), and the test
 * drives it directly.
 *
 * Each run uses a unique exercise + title so the assertions and cleanup
 * never collide with a previous run's rows in the shared seed DB.
 */
test.describe('/gym — log, PR badge, detail, delete', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('log a workout → PR badge → detail chips → delete', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Push day ${stamp}`;
		const exercise = `E2E Bench ${stamp}`;

		await page.goto('/gym');

		// Open the composer.
		await page.getByTestId('gym-log').click();

		// Fill the title + first exercise + its set (8 reps @ 60 kg).
		await page.getByPlaceholder('e.g. Push day').fill(title);
		await page.getByPlaceholder('Exercise name').first().fill(exercise);
		const setRow = page.locator('.set-row').first();
		await setRow.locator('input[type="number"]').nth(0).fill('8'); // reps
		await setRow.locator('input[type="number"]').nth(1).fill('60'); // weight kg

		await page.getByRole('button', { name: 'Save workout' }).click();

		// The new workout shows on the list with a PR badge (first-ever lift).
		const row = page.locator('.workout-row', { hasText: title });
		await expect(row).toBeVisible({ timeout: 10_000 });
		await expect(row.locator('.pr-badge')).toBeVisible();

		// Backend row exists, owned by USER_A.
		const { data: created } = await admin
			.from('gym_workouts')
			.select('id, title')
			.eq('user_id', USER_A.id)
			.eq('title', title);
		expect(created?.length).toBe(1);
		const workoutId = created![0].id as string;

		// Detail screen: the exercise block, its PR chip, and the set value.
		await row.click();
		await expect(page).toHaveURL(new RegExp(`/gym/${workoutId}`));
		const block = page.locator('.exercise-block', { hasText: exercise });
		await expect(block).toBeVisible({ timeout: 10_000 });
		await expect(block.locator('.pr-chip').first()).toBeVisible();
		await expect(block.locator('.sets li:not(.sets-head)').first()).toContainText('60');

		// ICU plural runtime: this workout has exactly one exercise, so the
		// dashboard recent-lifts row renders the singular "1 exercise", not
		// "1 exercises" (gym.exercisesShort → Intl.PluralRules `one` branch).
		await page.goto('/dashboard');
		const liftRow = page.locator('.run-row', { hasText: title });
		await expect(liftRow).toBeVisible({ timeout: 10_000 });
		await expect(liftRow.locator('.run-pace')).toHaveText('1 exercise');
		await page.goto(`/gym/${workoutId}`);

		// Delete it via the confirm dialog → back to the list, row gone.
		await page.getByRole('button', { name: 'Delete', exact: true }).click();
		await page
			.getByRole('button', { name: 'Delete', exact: true })
			.last()
			.click();
		await expect(page).toHaveURL(/\/gym$/, { timeout: 10_000 });
		await expect(page.locator('.workout-row', { hasText: title })).toHaveCount(0);

		// Backend row is gone (sets cascade with it).
		const { data: afterDelete } = await admin
			.from('gym_workouts')
			.select('id')
			.eq('id', workoutId);
		expect(afterDelete?.length ?? 0).toBe(0);
	});

	test('Gym → Sessions link surfaces when the user has a session plan', async ({ page }) => {
		// Session plans are otherwise undiscoverable from the main nav — the Gym
		// header surfaces a Sessions link, self-hiding on session-plan presence
		// (independent of gym-workout count). Seed one plan, assert the link
		// appears and lands on /sessions.
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E session ${stamp}`;
		const { data } = await admin
			.from('session_plans')
			.insert({ author_id: USER_A.id, title })
			.select('id')
			.single();
		const planId = (data as { id: string }).id;

		try {
			await page.goto('/gym');
			const link = page.getByTestId('gym-sessions-link');
			await expect(link).toBeVisible({ timeout: 10_000 });
			await link.click();
			await expect(page).toHaveURL(/\/sessions$/, { timeout: 10_000 });
			await expect(page.locator('.plan-row', { hasText: title })).toBeVisible({ timeout: 10_000 });
		} finally {
			await admin.from('session_plans').delete().eq('id', planId);
		}
	});

	test('timed set: duration_s round-trips (plank hold)', async ({ page }) => {
		// A timed hold (plank) carries duration_s with no weight (instructor M2).
		// Log a 90 s plank, assert the stored row carries duration_s = 90, and
		// the detail screen surfaces the hold time.
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Core day ${stamp}`;
		const exercise = `E2E Plank ${stamp}`;

		await page.goto('/gym');
		await page.getByTestId('gym-log').click();

		await page.getByPlaceholder('e.g. Push day').fill(title);
		await page.getByPlaceholder('Exercise name').first().fill(exercise);
		const setRow = page.locator('.set-row').first();
		// Columns are reps / weight / rpe / duration — fill only the duration.
		await setRow.locator('input[type="number"]').nth(3).fill('90');

		await page.getByRole('button', { name: 'Save workout' }).click();

		const row = page.locator('.workout-row', { hasText: title });
		await expect(row).toBeVisible({ timeout: 10_000 });

		const { data: created } = await admin
			.from('gym_workouts')
			.select('id')
			.eq('user_id', USER_A.id)
			.eq('title', title);
		expect(created?.length).toBe(1);
		const workoutId = created![0].id as string;

		try {
			const { data: sets } = await admin
				.from('gym_sets')
				.select('duration_s, reps, weight_kg')
				.eq('workout_id', workoutId);
			expect(sets?.length).toBe(1);
			expect(sets![0].duration_s).toBe(90);
			expect(sets![0].reps).toBeNull();
			expect(sets![0].weight_kg).toBeNull();

			// Detail screen surfaces the hold time.
			await row.click();
			await expect(page).toHaveURL(new RegExp(`/gym/${workoutId}`));
			const block = page.locator('.exercise-block', { hasText: exercise });
			await expect(block).toBeVisible({ timeout: 10_000 });
			await expect(block.locator('.sets li:not(.sets-head)').first()).toContainText('90s');
		} finally {
			await admin.from('gym_workouts').delete().eq('id', workoutId);
		}
	});

	test('catalogue: picking a seeded exercise binds gym_sets.exercise_id (migration 20270222_001)', async ({
		page,
	}) => {
		// The exercise catalogue is ADDITIVE: typing a name that matches a seeded
		// global by normalised key binds that exercise_id onto the logged sets,
		// while free text still logs with exercise_id null. Log a set under the
		// seeded "Bench Press" and assert the stored set carries the catalogue id.
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Catalogue day ${stamp}`;

		// Resolve the seeded global "Bench Press" id (author_id null).
		const { data: cat } = await admin
			.from('exercises')
			.select('id')
			.is('author_id', null)
			.eq('name_key', 'bench press')
			.single();
		const benchId = (cat as { id: string }).id;
		expect(benchId).toBeTruthy();

		await page.goto('/gym');
		await page.getByTestId('gym-log').click();

		await page.getByPlaceholder('e.g. Push day').fill(title);
		// Type the catalogue name verbatim (the datalist offers it; a free-text
		// match by normalised key is what binds the id at save time).
		await page.getByPlaceholder('Exercise name').first().fill('Bench Press');
		const setRow = page.locator('.set-row').first();
		await setRow.locator('input[type="number"]').nth(0).fill('5');
		await setRow.locator('input[type="number"]').nth(1).fill('80');

		await page.getByRole('button', { name: 'Save workout' }).click();

		const row = page.locator('.workout-row', { hasText: title });
		await expect(row).toBeVisible({ timeout: 10_000 });

		const { data: created } = await admin
			.from('gym_workouts')
			.select('id')
			.eq('user_id', USER_A.id)
			.eq('title', title);
		expect(created?.length).toBe(1);
		const workoutId = created![0].id as string;

		try {
			const { data: sets } = await admin
				.from('gym_sets')
				.select('exercise_name, exercise_id')
				.eq('workout_id', workoutId);
			expect(sets?.length).toBe(1);
			expect(sets![0].exercise_name).toBe('Bench Press');
			// The catalogue link was bound from the typed name.
			expect(sets![0].exercise_id).toBe(benchId);
		} finally {
			await admin.from('gym_workouts').delete().eq('id', workoutId);
		}
	});

	test('weight_unit=lbs: entry parses to canonical kg + display renders lbs (F19)', async ({
		page,
	}) => {
		// The weight_unit pref is display + entry only — gym_sets.weight_kg
		// stays canonical kilograms. Flip the universal pref to lbs, type a
		// pound value, and assert (a) the stored weight is the kg equivalent,
		// (b) the detail screen renders it back in lbs.
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E lbs day ${stamp}`;
		const exercise = `E2E Squat ${stamp}`;

		await setUserSetting(USER_A.id, 'weight_unit', 'lbs');
		try {
			await page.goto('/gym');
			// The set label reflects the active unit.
			await page.getByTestId('gym-log').click();
			await expect(page.locator('.set-cap', { hasText: 'Weight (lbs)' }).first()).toBeVisible();

			await page.getByPlaceholder('e.g. Push day').fill(title);
			await page.getByPlaceholder('Exercise name').first().fill(exercise);
			const setRow = page.locator('.set-row').first();
			await setRow.locator('input[type="number"]').nth(0).fill('5'); // reps
			await setRow.locator('input[type="number"]').nth(1).fill('135'); // 135 lbs

			await page.getByRole('button', { name: 'Save workout' }).click();

			const row = page.locator('.workout-row', { hasText: title });
			await expect(row).toBeVisible({ timeout: 10_000 });

			const { data: created } = await admin
				.from('gym_workouts')
				.select('id')
				.eq('user_id', USER_A.id)
				.eq('title', title);
			expect(created?.length).toBe(1);
			const workoutId = created![0].id as string;

			try {
				// 135 lbs -> ~61.23 kg stored (canonical), not 135.
				const { data: sets } = await admin
					.from('gym_sets')
					.select('weight_kg')
					.eq('workout_id', workoutId);
				expect(sets?.length).toBe(1);
				expect(sets![0].weight_kg).toBeGreaterThan(61);
				expect(sets![0].weight_kg).toBeLessThan(61.5);

				// Detail renders the canonical kg back in the user's lbs unit.
				await row.click();
				await expect(page).toHaveURL(new RegExp(`/gym/${workoutId}`));
				const block = page.locator('.exercise-block', { hasText: exercise });
				await expect(block).toBeVisible({ timeout: 10_000 });
				await expect(block.locator('.sets li:not(.sets-head)').first()).toContainText('135');
				await expect(block.locator('.sets li:not(.sets-head)').first()).toContainText('lbs');
			} finally {
				await admin.from('gym_workouts').delete().eq('id', workoutId);
			}
		} finally {
			await setUserSetting(USER_A.id, 'weight_unit', 'kg');
		}
	});
});
