import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /gym/routines/library — the public gym-routine library (migration
 * 20270224_001, docs/features/gym_programming.md).
 *
 * Covers: an owner publishes a personal routine to the public library and
 * unpublishes it (set_gym_routine_public); a different signed-in user browses
 * the library, previews a public routine's planned sets, and adopts (clones) it
 * into their own routine list (clone_gym_routine_template public branch).
 *
 * Each run uses a unique title so rows never collide in the shared seed DB and
 * cleans up its own backend rows.
 */
test.describe('/gym/routines/library — publish, browse, preview, adopt', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('owner publishes + unpublishes a routine to/from the public library', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Public Toggle ${stamp}`;

		const { data: r } = await admin
			.from('gym_routines')
			.insert({ author_id: USER_A.id, title, exercise_count: 0 })
			.select('id')
			.single();
		const routineId = r!.id as string;

		try {
			await page.goto(`/gym/routines/${routineId}`);
			// Publish.
			await page.getByTestId('routine-toggle-public').click();
			await expect(page.getByTestId('routine-public-badge')).toBeVisible({ timeout: 10_000 });
			let { data: after } = await admin
				.from('gym_routines')
				.select('is_public_template')
				.eq('id', routineId)
				.single();
			expect(after!.is_public_template).toBe(true);

			// Unpublish.
			await page.getByTestId('routine-toggle-public').click();
			await expect(page.getByTestId('routine-public-badge')).toHaveCount(0, { timeout: 10_000 });
			({ data: after } = await admin
				.from('gym_routines')
				.select('is_public_template')
				.eq('id', routineId)
				.single());
			expect(after!.is_public_template).toBe(false);
		} finally {
			await admin.from('gym_routines').delete().eq('id', routineId);
		}
	});

	test('a signed-in user browses, previews, and adopts a public routine', async ({ page }) => {
		const admin = getAdminClient();
		const stamp = Date.now();
		const title = `E2E Public Lib ${stamp}`;
		const exercise = `E2E Squat ${stamp}`;

		// Seed a public template owned by USER_B with one exercise + two sets.
		const { data: r } = await admin
			.from('gym_routines')
			.insert({ author_id: USER_B.id, title, exercise_count: 1, is_public_template: true })
			.select('id')
			.single();
		const templateId = r!.id as string;
		const { data: ex } = await admin
			.from('gym_routine_exercises')
			.insert({
				routine_id: templateId,
				exercise_name: exercise,
				exercise_key: exercise.trim().toLowerCase(),
				position: 0,
			})
			.select('id')
			.single();
		await admin.from('gym_routine_sets').insert([
			{ routine_exercise_id: ex!.id, set_index: 0, target_reps_min: 5, target_weight_kg: 100 },
			{ routine_exercise_id: ex!.id, set_index: 1, target_reps_min: 5, target_weight_kg: 100 },
		]);

		let adoptedId: string | null = null;
		try {
			// Browse: the library lists the public template (search narrows to it).
			await page.goto('/gym/routines/library');
			await page.getByRole('searchbox').fill(title);
			await expect(page.getByTestId('gym-library-list')).toBeVisible({ timeout: 10_000 });
			await page.getByRole('link', { name: new RegExp(title) }).click();

			// Preview: the planned exercise + sets render.
			await expect(page.getByTestId('gym-library-adopt')).toBeVisible({ timeout: 10_000 });
			await expect(page.locator('.exercise-name', { hasText: exercise })).toBeVisible();

			// Adopt → lands on the new personal routine detail.
			await page.getByTestId('gym-library-adopt').click();
			await expect(page).toHaveURL(/\/gym\/routines\/[0-9a-f-]+$/, { timeout: 10_000 });
			await expect(page.getByTestId('routine-exercises')).toContainText(exercise);

			// A new personal (club-less, non-public) routine is owned by USER_A.
			const { data: clones } = await admin
				.from('gym_routines')
				.select('id, club_id, is_public_template, exercise_count')
				.eq('author_id', USER_A.id)
				.eq('title', title);
			expect(clones?.length).toBe(1);
			adoptedId = clones![0].id as string;
			expect(clones![0].club_id).toBeNull();
			expect(clones![0].is_public_template).toBe(false);

			const { data: clonedEx } = await admin
				.from('gym_routine_exercises')
				.select('id, exercise_key')
				.eq('routine_id', adoptedId);
			expect(clonedEx?.length).toBe(1);
			const { data: clonedSets } = await admin
				.from('gym_routine_sets')
				.select('target_weight_kg')
				.eq('routine_exercise_id', clonedEx![0].id);
			expect(clonedSets?.length).toBe(2);
			expect(Number(clonedSets![0].target_weight_kg)).toBe(100);
		} finally {
			if (adoptedId) await admin.from('gym_routines').delete().eq('id', adoptedId);
			await admin.from('gym_routines').delete().eq('id', templateId);
		}
	});
});
