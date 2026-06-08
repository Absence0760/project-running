import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym/records — the personal-records surface (lib/gym/exercise_records.ts,
 * decisions §63, docs/features/multi_modal.md § Gym). The PR engine already
 * computes each exercise's bests for the per-workout badges; this surface
 * rolls them up so a lifter can see their current best for every weighted
 * exercise in one place.
 *
 * Drives it end to end: log a weighted workout, follow the Records link that
 * appears on /gym once a weighted set exists, and confirm the exercise's
 * record card shows its heaviest set. Unique exercise + title per run so
 * assertions and cleanup never collide with prior rows in the shared seed DB.
 */
test.describe('/gym/records — per-exercise current bests', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('log a weighted lift → Records link → record card with the heaviest set', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Records day ${stamp}`;
		const exercise = `E2E Deadlift ${stamp}`;

		await page.goto('/gym');
		await page.getByTestId('gym-log').click();
		await page.getByPlaceholder('e.g. Push day').fill(title);
		await page.getByPlaceholder('Exercise name').first().fill(exercise);
		const setRow = page.locator('.set-row').first();
		await setRow.locator('input[type="number"]').nth(0).fill('5'); // reps
		await setRow.locator('input[type="number"]').nth(1).fill('120'); // weight kg
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
			// The Records link is present now that a weighted set exists.
			const recordsLink = page.getByTestId('gym-records-link');
			await expect(recordsLink).toBeVisible();
			await recordsLink.click();
			await expect(page).toHaveURL(/\/gym\/records$/);

			// The record card for this exercise shows its heaviest set (120 kg × 5).
			const card = page.locator('.record-card', { hasText: exercise });
			await expect(card).toBeVisible({ timeout: 10_000 });
			// "× 5" is the heaviest-set rep suffix — unambiguous, unlike a bare
			// "5" which could match a digit in the Date.now()-stamped name.
			await expect(card).toContainText('120 kg × 5');
		} finally {
			await admin.from('gym_workouts').delete().eq('id', workoutId);
		}
	});
});
