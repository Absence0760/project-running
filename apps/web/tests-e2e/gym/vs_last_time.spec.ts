import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /gym/[id] — the "vs last time" progressive-overload hint
 * (lib/gym/exercise_history.ts#previousExerciseSession, decisions §63,
 * multi_modal.md § Gym). The all-time PR chips only fire when you beat your
 * best; this hint shows what you did the previous session of each exercise and
 * how today compares, even when it isn't a PR.
 *
 * Logs two sessions of one exercise (100 kg then 110 kg), opens the heavier
 * workout's detail, and asserts the hint shows the previous session's top set
 * with a +10 kg delta and links to that exercise's progression. Unique
 * exercise name per run so it never collides with prior rows in the seed DB.
 */
test.describe('/gym/[id] — vs last time hint', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('previous session, +/- delta, minus glyph, link, and no-prior case', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const exercise = `E2E Row ${stamp}`;
		const workoutIds: Record<string, string> = {};

		for (const weight of ['100', '110', '95']) {
			await page.goto('/gym');
			await page.getByTestId('gym-log').click();
			await page.getByPlaceholder('e.g. Push day').fill(`${exercise} ${weight}`);
			await page.getByPlaceholder('Exercise name').first().fill(exercise);
			const setRow = page.locator('.set-row').first();
			await setRow.locator('input[type="number"]').nth(0).fill('5');
			await setRow.locator('input[type="number"]').nth(1).fill(weight);
			await page.getByRole('button', { name: 'Save workout' }).click();
			await expect(page.locator('.workout-row', { hasText: `${exercise} ${weight}` })).toBeVisible({
				timeout: 10_000,
			});
		}

		const { data: created } = await admin
			.from('gym_workouts')
			.select('id, title')
			.eq('user_id', USER_A.id)
			.like('title', `${exercise}%`);
		for (const w of created ?? []) workoutIds[w.title as string] = w.id as string;
		expect(Object.keys(workoutIds).length).toBe(3);

		try {
			// Second session (110) vs the first (100): a +10 kg gain, shown green.
			await page.goto(`/gym/${workoutIds[`${exercise} 110`]}`);
			const hint = page.locator('.last-time');
			await expect(hint).toBeVisible({ timeout: 10_000 });
			await expect(hint).toContainText('100 kg × 5');
			await expect(hint.locator('.lt-up')).toContainText('+10 kg');
			await expect(hint.locator('.lt-down')).toHaveCount(0);
			// Links to this exercise's progression page.
			await expect(hint).toHaveAttribute('href', /\/gym\/exercise\?name=/);

			// Third session (95) vs the previous (110): a regression, shown neutral
			// with the proper minus glyph (U+2212), not a hyphen.
			await page.goto(`/gym/${workoutIds[`${exercise} 95`]}`);
			const downHint = page.locator('.last-time');
			await expect(downHint).toBeVisible({ timeout: 10_000 });
			await expect(downHint).toContainText('110 kg × 5');
			await expect(downHint.locator('.lt-down')).toContainText('−15 kg');
			await expect(downHint.locator('.lt-up')).toHaveCount(0);

			// The first (lighter) workout has no earlier session → no hint.
			await page.goto(`/gym/${workoutIds[`${exercise} 100`]}`);
			await expect(page.locator('.exercise-block', { hasText: exercise })).toBeVisible({
				timeout: 10_000,
			});
			await expect(page.locator('.last-time')).toHaveCount(0);
		} finally {
			for (const id of Object.values(workoutIds)) {
				await admin.from('gym_workouts').delete().eq('id', id);
			}
		}
	});
});
