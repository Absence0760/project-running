import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym — the Phase 4 multi-modal gym module (decisions §63,
 * docs/features/multi_modal.md § Gym).
 *
 * Covers the lightweight-tier loop end to end: log a free-form workout
 * (title + exercise + sets), see it on the list with a PR badge (first
 * time an exercise is logged is always a PR — gym_prs.ts), open the
 * detail screen and confirm the per-exercise PR chip + set rows, then
 * delete it. The route is reachable by URL regardless of the
 * `multi_modal_nav` sidebar flag (the flag only gates the nav link), so
 * the test drives it directly.
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
		await expect(block.locator('.sets li').first()).toContainText('60');

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
});
