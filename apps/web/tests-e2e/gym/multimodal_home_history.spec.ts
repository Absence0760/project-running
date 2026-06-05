import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Multi-modal Home + History (docs/features/multi_modal.md §§ Home,
 * History). Both surfaces self-hide their gym affordances purely on **data
 * presence** — there is no `multi_modal_nav` flag any more (decisions §63
 * amendment: web was ungated to match mobile). A pure runner with no gym
 * data sees today's app unchanged; logging a session lights up the gym
 * slice. This spec seeds a gym session and asserts the slice appears on
 * /dashboard (Recent lifts card) and /history (kind chips + a lift row in
 * the unified timeline) WITHOUT touching any flag.
 */
test.describe.configure({ mode: 'serial' });

test.describe('multi-modal Home + History', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const stamp = Date.now();
	const liftTitle = `E2E MM Lift ${stamp}`;
	let workoutId: string | null = null;

	test.beforeAll(async () => {
		const admin = getAdminClient();

		// Seed a lift session logged today (so it lands on Today + in the
		// activities view) with one weighted set. No flag flip — the gym
		// slice now appears on data presence alone.
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
	});

	test('sidebar shows Gym + Nutrition items (always present, ungated)', async ({ page }) => {
		// The core of the §63 amendment: the sidebar entry points are always
		// present, no flag — a runner can always reach gym/nutrition.
		await page.goto('/dashboard');
		// The nav-link's accessible name includes the material-symbols icon
		// ligature text, so match the visible label span exactly instead.
		const nav = page.locator('nav.sidebar');
		await expect(nav.locator('.nav-label', { hasText: /^Gym$/ })).toBeVisible({
			timeout: 15_000,
		});
		await expect(nav.locator('.nav-label', { hasText: /^Nutrition$/ })).toBeVisible();
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
