import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * /social?tab=feed — cross-modal lift cards (multi_modal.md § Social feed).
 *
 * A public gym workout from a followed user surfaces in the feed as a
 * "lift card" — title + set count + total volume — distinct from a run
 * card. The Lift filter chip narrows to lifts only; only is_public
 * workouts appear (privacy boundary).
 */

test.describe('/social?tab=feed — lift cards', () => {
	test.use({ storageState: USER_B.storageStatePath });

	let publicWorkoutId: string | null = null;
	let privateWorkoutId: string | null = null;
	const stamp = Date.now();
	const publicTitle = `E2E Public lift ${stamp}`;
	const privateTitle = `E2E Private lift ${stamp}`;

	test.beforeEach(async () => {
		const admin = getAdminClient();
		await admin
			.from('user_follows')
			.upsert(
				{ follower_id: USER_B.id, followee_id: USER_A.id },
				{ onConflict: 'follower_id,followee_id' }
			);
		const startedAt = new Date(Date.now() - 30 * 60 * 1000).toISOString();
		const { data: pub, error: pubErr } = await admin
			.from('gym_workouts')
			.insert({
				user_id: USER_A.id,
				title: publicTitle,
				started_at: startedAt,
				is_public: true
			})
			.select('id')
			.single();
		if (pubErr) throw pubErr;
		publicWorkoutId = (pub as { id: string }).id;
		// Two sets so set_count + volume_kg trigger-maintained columns populate.
		await admin.from('gym_sets').insert([
			{ workout_id: publicWorkoutId, set_index: 0, exercise_name: 'Bench', reps: 8, weight_kg: 60 },
			{ workout_id: publicWorkoutId, set_index: 1, exercise_name: 'Bench', reps: 8, weight_kg: 60 }
		]);

		const { data: priv, error: privErr } = await admin
			.from('gym_workouts')
			.insert({
				user_id: USER_A.id,
				title: privateTitle,
				started_at: startedAt,
				is_public: false
			})
			.select('id')
			.single();
		if (privErr) throw privErr;
		privateWorkoutId = (priv as { id: string }).id;
	});

	test.afterEach(async () => {
		const admin = getAdminClient();
		for (const id of [publicWorkoutId, privateWorkoutId]) {
			if (id) await admin.from('gym_workouts').delete().eq('id', id);
		}
		publicWorkoutId = null;
		privateWorkoutId = null;
	});

	test('public lift surfaces as a lift card; private one does not', async ({ page }) => {
		await page.goto('/social?tab=feed');
		// The public workout's lift card is present, links to its share page.
		const card = page.getByTestId('lift-card').filter({ hasText: publicTitle });
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card).toHaveAttribute('href', new RegExp(`/share/workout/${publicWorkoutId}`));
		// The 2 sets it logged show on the card.
		await expect(card).toContainText('2');
		// Privacy boundary: the private workout never appears.
		await expect(page.getByText(privateTitle)).toHaveCount(0);
	});

	test('Lift filter narrows to lifts and drops run cards', async ({ page }) => {
		await page.goto('/social?tab=feed');
		await expect(page.locator('article').first()).toBeVisible({ timeout: 10_000 });
		await page.getByRole('button', { name: 'Lift', exact: true }).click();
		// The lift card is retained under the Lift filter.
		await expect(
			page.getByTestId('lift-card').filter({ hasText: publicTitle })
		).toBeVisible({ timeout: 10_000 });
		// No run cards (kudos pill is run-only) remain under the Lift filter.
		await expect(page.locator('.kudos-pill')).toHaveCount(0);
	});
});
