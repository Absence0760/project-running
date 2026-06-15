import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Gym programming — club-published gym-routine templates (migration
 * 20270109_001, gym_programming.md).
 *
 * USER_A owns Richmond Run Club (admin), so they can publish a personal gym
 * routine to it (publish_gym_routine_as_template) and the club's Templates tab
 * surfaces it with an Adopt action that clones it back into a fresh personal
 * routine (clone_gym_routine_template).
 */

const RICHMOND_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/gym/routines — club gym-routine templates', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let sourceRoutineId: string | null = null;
	const title = `e2e-routine-template ${Date.now()}`;

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data: routine } = await admin
			.from('gym_routines')
			.insert({ author_id: USER_A.id, title, exercise_count: 1 })
			.select('id')
			.single();
		sourceRoutineId = (routine as { id: string }).id;
		const { data: ex } = await admin
			.from('gym_routine_exercises')
			.insert({
				routine_id: sourceRoutineId,
				exercise_name: 'Back Squat',
				exercise_key: 'back squat',
				position: 0
			})
			.select('id')
			.single();
		await admin.from('gym_routine_sets').insert({
			routine_exercise_id: (ex as { id: string }).id,
			set_index: 0,
			target_reps_min: 5,
			target_weight_kg: 60
		});
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		// The source routine, the published club copy, and any adopted clone all
		// share the title — sweep them all (exercises + sets cascade).
		await admin.from('gym_routines').delete().eq('title', title);
	});

	test('publish a routine to a club, then adopt it from the club Templates tab', async ({
		page
	}) => {
		const admin = getAdminClient();

		// Publish from the routine detail page.
		await page.goto(`/gym/routines/${sourceRoutineId}`);
		const publishRow = page.locator('.publish-row');
		await expect(publishRow).toBeVisible({ timeout: 10_000 });
		await publishRow.locator('select').selectOption(RICHMOND_CLUB_ID);
		await page.getByTestId('routine-publish').click();
		await expect(publishRow.locator('select')).toHaveValue('', { timeout: 10_000 });

		// A club-owned copy now exists, with the set copied across.
		const { data: clubCopies } = await admin
			.from('gym_routines')
			.select('id')
			.eq('club_id', RICHMOND_CLUB_ID)
			.eq('title', title);
		expect(clubCopies?.length).toBe(1);

		// It surfaces on the club's Templates tab, and Adopt clones it.
		await page.goto('/clubs/richmond-run-club?tab=templates');
		const adoptBtn = page.getByTestId('gym-routine-template-adopt').first();
		await expect(adoptBtn).toBeVisible({ timeout: 10_000 });
		await adoptBtn.click();

		// Adopt navigates to the new personal clone's detail page.
		await page.waitForURL(/\/gym\/routines\/[0-9a-f-]+$/, { timeout: 10_000 });
		const { data: personalClones } = await admin
			.from('gym_routines')
			.select('id')
			.eq('author_id', USER_A.id)
			.is('club_id', null)
			.eq('title', title);
		// The original source + the adopted clone are both personal + club-less.
		expect(personalClones?.length ?? 0).toBeGreaterThanOrEqual(2);

		// Regression: the back control on the adopted clone must return to the
		// CLUB it was adopted from (the page we soft-navigated from), not the
		// generic /gym/routines list. smartBack pops the history entry the
		// adopt goto pushed.
		await page.getByRole('link', { name: 'Back to routines' }).click();
		await expect(page).toHaveURL(/\/clubs\/richmond-run-club/, { timeout: 10_000 });
	});

	test('arriving at a routine directly (deep link) backs to the gym routines list', async ({
		page
	}) => {
		// The other half of the smartBack contract: with no in-app referrer to
		// pop, the back link falls through to its static /gym/routines parent.
		await page.goto(`/gym/routines/${sourceRoutineId}`);
		await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });
		await page.getByRole('link', { name: 'Back to routines' }).click();
		await expect(page).toHaveURL(/\/gym\/routines$/, { timeout: 10_000 });
	});
});
