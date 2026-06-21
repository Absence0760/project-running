import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * gym_sets.set_type — the per-LOGGED-set role (warmup / working / dropset /
 * amrap / failure / backoff), migration 20270228_001. Reuses the routine
 * vocabulary + its i18n labels.
 *
 * Drives the composer: a warmup set + a working set, save, and assert (a) the
 * persisted gym_sets rows carry the chosen set_type, and (b) the detail screen
 * surfaces a chip for the non-working set while the working set shows none.
 */
test.describe('/gym — logged set_type', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('compose with set types → persists → detail chip', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E SetType ${stamp}`;
		const exercise = `E2E Squat ${stamp}`;

		await page.goto('/gym');
		await page.getByTestId('gym-log').click();

		await page.getByPlaceholder('e.g. Push day').fill(title);
		await page.getByPlaceholder('Exercise name').first().fill(exercise);

		// Set 1: warmup, 5 reps @ 40 kg.
		const set1 = page.locator('.set-row').nth(0);
		await set1.getByTestId('gym-set-type').selectOption('warmup');
		await set1.locator('input[type="number"]').nth(0).fill('5');
		await set1.locator('input[type="number"]').nth(1).fill('40');

		// Add a second set, leave it at the working default, 5 reps @ 80 kg.
		await page.getByRole('button', { name: 'Add set' }).click();
		const set2 = page.locator('.set-row').nth(1);
		await set2.locator('input[type="number"]').nth(0).fill('5');
		await set2.locator('input[type="number"]').nth(1).fill('80');

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
			// Persisted set_type values, in set_index order.
			const { data: sets } = await admin
				.from('gym_sets')
				.select('set_index, set_type')
				.eq('workout_id', workoutId)
				.order('set_index', { ascending: true });
			expect(sets?.map((s) => s.set_type)).toEqual(['warmup', 'working']);

			// Detail: the warmup set shows a chip; the working set shows none.
			await page.goto(`/gym/${workoutId}`);
			const block = page.locator('.exercise-block', { hasText: exercise });
			await expect(block).toBeVisible({ timeout: 10_000 });
			const chips = block.getByTestId('gym-set-type-chip');
			await expect(chips).toHaveCount(1);
			await expect(chips.first()).toHaveText('Warm-up');
		} finally {
			await admin.from('gym_workouts').delete().eq('id', workoutId);
		}
	});
});
