import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { setUserSetting } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /dashboard — gym-aware readiness (decisions §63 amendment, the "do them all"
 * cross-modality pass).
 *
 * Gym sessions feed the same fitness/fatigue/form curve as runs. This pins the
 * two user-visible halves of that: (1) by default a recent gym session surfaces
 * a transparency note on the Fitness card, and (2) the
 * `exclude_gym_from_readiness` pref flips the note to "excluded" (and, in the
 * model, drops lifts from the curve — the run-only curve stays recoverable).
 *
 * Self-seeds its own recent gym workout so the test doesn't depend on the
 * seed fixture's gym rows; cleans up the workout + resets the pref.
 */
test.describe('/dashboard — gym-aware readiness', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('recent gym session shows on readiness; exclude pref flips the note', async ({
		page,
	}) => {
		const admin = getAdminClient();
		const startedAt = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
		const { data: workout } = await admin
			.from('gym_workouts')
			.insert({
				user_id: USER_A.id,
				title: 'E2E Readiness Lift',
				started_at: startedAt,
				duration_s: 3600,
			})
			.select('id')
			.single();
		await admin.from('gym_sets').insert([
			{ workout_id: workout!.id, set_index: 0, exercise_name: 'Bench press', reps: 5, weight_kg: 60 },
			{ workout_id: workout!.id, set_index: 1, exercise_name: 'Bench press', reps: 5, weight_kg: 60 },
		]);

		try {
			// Default: gym counts toward fatigue → "factored in" note.
			await setUserSetting(USER_A.id, 'exclude_gym_from_readiness', false);
			await page.goto('/dashboard');
			const note = page.getByTestId('gym-readiness-note');
			await expect(note).toBeVisible({ timeout: 10_000 });
			await expect(note).toContainText(/factored into your fatigue/i);

			// Opt out: the note flips to "excluded".
			await setUserSetting(USER_A.id, 'exclude_gym_from_readiness', true);
			await page.goto('/dashboard');
			await expect(note).toBeVisible({ timeout: 10_000 });
			await expect(note).toContainText(/excluded/i);
		} finally {
			await setUserSetting(USER_A.id, 'exclude_gym_from_readiness', false);
			await admin.from('gym_workouts').delete().eq('id', workout!.id);
		}
	});
});
