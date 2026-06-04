import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Multi-modal Home + History (docs/features/multi_modal.md §§ Home,
 * History). Both surfaces self-hide their gym affordances behind the
 * `multi_modal_nav` per-user flag AND data presence: a pure runner sees
 * today's app unchanged. This spec turns the flag on for USER_A, seeds a
 * gym session, and asserts the gym slice appears on /dashboard (Recent
 * lifts card) and /history (kind chips + a lift row in the unified timeline).
 *
 * The flag is read from user_settings.prefs.multi_modal_nav; we snapshot
 * the original prefs and restore them afterwards so no other spec inherits
 * a flipped flag in the shared seed DB.
 */
test.describe.configure({ mode: 'serial' });

test.describe('multi-modal Home + History', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const stamp = Date.now();
	const liftTitle = `E2E MM Lift ${stamp}`;
	let workoutId: string | null = null;
	let originalPrefs: Record<string, unknown> = {};

	test.beforeAll(async () => {
		const admin = getAdminClient();

		// Snapshot + flip the flag on.
		const { data: settings } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		originalPrefs = (settings?.prefs as Record<string, unknown>) ?? {};
		await admin
			.from('user_settings')
			.upsert(
				{ user_id: USER_A.id, prefs: { ...originalPrefs, multi_modal_nav: true } },
				{ onConflict: 'user_id' },
			);

		// Seed a lift session logged today (so it lands on Today + in the
		// activities view) with one weighted set.
		const { data: w } = await admin
			.from('gym_workouts')
			.insert({
				user_id: USER_A.id,
				title: liftTitle,
				started_at: new Date().toISOString(),
				last_modified_at: new Date().toISOString(),
			})
			.select('id')
			.single();
		workoutId = (w?.id as string) ?? null;
		expect(workoutId).not.toBeNull();
		await admin.from('gym_sets').insert({
			workout_id: workoutId,
			exercise_name: `E2E Bench ${stamp}`,
			set_index: 0,
			reps: 8,
			weight_kg: 60,
		});
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (workoutId) await admin.from('gym_workouts').delete().eq('id', workoutId);
		// Restore the original prefs blob (flag back to its prior state).
		await admin
			.from('user_settings')
			.upsert({ user_id: USER_A.id, prefs: originalPrefs }, { onConflict: 'user_id' });
	});

	test('Home shows the Recent lifts card', async ({ page }) => {
		await page.goto('/dashboard');
		const card = page.locator('section.card', { hasText: 'Recent lifts' });
		await expect(card).toBeVisible({ timeout: 15_000 });
		await expect(card.getByText(liftTitle)).toBeVisible();
	});

	test('History shows kind chips and a lift row under the Lifts chip', async ({ page }) => {
		await page.goto('/history');

		// Chips appear (a second modality now exists).
		const lifts = page.getByRole('button', { name: 'Lifts', exact: true });
		await expect(lifts).toBeVisible({ timeout: 15_000 });
		await expect(page.getByRole('button', { name: 'Runs', exact: true })).toBeVisible();

		// Filter to lifts → the seeded session shows as a timeline row that
		// links to its gym detail route.
		await lifts.click();
		const row = page.locator('.timeline-row', { hasText: liftTitle });
		await expect(row).toBeVisible({ timeout: 10_000 });
		await row.click();
		await expect(page).toHaveURL(new RegExp(`/gym/${workoutId}`));
	});
});
