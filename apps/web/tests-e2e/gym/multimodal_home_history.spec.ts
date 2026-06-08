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
		const card = page.locator('section.card-elevated', { hasText: 'Recent lifts' });
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

	test('History All view exposes a modality-aware Log menu', async ({ page }) => {
		await page.goto('/history');
		// Default chip is All once a second modality exists. The Log button
		// opens a menu offering all three create flows — runs no longer own a
		// standalone Add-run button on the unified timeline.
		const logBtn = page.getByRole('button', { name: 'Log', exact: true });
		await expect(logBtn).toBeVisible({ timeout: 15_000 });
		await logBtn.click();
		await expect(page.getByRole('menuitem', { name: 'Log run' })).toBeVisible();
		await expect(page.getByRole('menuitem', { name: 'Log workout' })).toBeVisible();
		await expect(page.getByRole('menuitem', { name: 'Log food' })).toBeVisible();

		// Picking Workout launches the gym editor modal in place — no navigation
		// away from /history.
		await page.getByRole('menuitem', { name: 'Log workout' }).click();
		await expect(page.getByRole('dialog', { name: 'New workout' })).toBeVisible();
		await expect(page).toHaveURL(/\/history$/);
	});

	test('Lifts chip surfaces the single Log workout action directly', async ({ page }) => {
		await page.goto('/history');
		await page.getByRole('button', { name: 'Lifts', exact: true }).click();
		// Under a single-modality chip the one matching action shows directly,
		// not behind the All-view menu — and that menu trigger is gone.
		await expect(page.getByRole('button', { name: 'Log workout', exact: true })).toBeVisible({
			timeout: 10_000,
		});
		await expect(page.getByRole('button', { name: 'Log', exact: true })).toHaveCount(0);
	});

	test('Runs chip shows run rows as a timeline + a View all link to /runs', async ({ page }) => {
		await page.goto('/history');
		await page.getByRole('button', { name: 'Runs', exact: true }).click();
		// The full run-list toolbar (filters + Add run + Heatmap) now lives on
		// /runs — under the Runs chip, runs render as timeline rows like
		// lifts/meals, so /history must not paint a `.toolbar`.
		await expect(page.locator('.toolbar')).toHaveCount(0);
		// The header offers a consistent "View all" link (→ /runs) + the single
		// Log run action, matching the Lifts/Meals tabs.
		const viewAll = page.getByRole('link', { name: /View all/ });
		await expect(viewAll).toBeVisible();
		await expect(viewAll).toHaveAttribute('href', '/runs');
		await expect(page.getByRole('button', { name: 'Log run', exact: true })).toBeVisible();
		await expect(page.getByRole('button', { name: 'Log', exact: true })).toHaveCount(0);
	});

	test('History holds a skeleton until activities resolve — no chip flash', async ({
		page,
	}) => {
		// Regression guard: /history holds a neutral timeline skeleton until the
		// activities feed lands, then paints the chips + timeline once — it never
		// flashes a chip-less layout first. The full run-list toolbar lives on
		// /runs now, so /history must never render a `.toolbar`. Gate the feed so
		// the pre-resolve paint is observable.
		let release!: () => void;
		const gate = new Promise<void>((r) => (release = r));
		await page.route('**/rest/v1/activities*', async (route) => {
			if (route.request().method() !== 'GET') return route.continue();
			await gate;
			return route.continue();
		});

		await page.goto('/history');

		// While the feed is pending: the timeline skeleton is shown and the
		// run-list toolbar (which now lives on /runs) is never painted here.
		await expect(page.locator('.timeline-skel')).toBeVisible({ timeout: 15_000 });
		await expect(page.locator('.toolbar')).toHaveCount(0);

		// Release the feed → the unified timeline takes over (a second modality
		// exists). The run-list toolbar is still never shown.
		release();
		await expect(page.getByRole('button', { name: 'Lifts', exact: true })).toBeVisible({
			timeout: 15_000,
		});
		await expect(page.locator('.timeline')).toBeVisible();
		await expect(page.locator('.toolbar')).toHaveCount(0);
	});

	test('timeline flows day groups into multiple columns on a wide canvas', async ({ page }) => {
		// The unified timeline lays each day group into a responsive grid
		// (repeat(auto-fill, minmax(30rem, 1fr))) so a wide canvas isn't left
		// with ~40% dead space on the right; it collapses to one column when
		// narrow. Seed a second day so there are deterministically >=2 day
		// groups to place side by side, and clean it up afterward.
		const admin = getAdminClient();
		const yStamp = Date.now();
		const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
		const { data: yw } = await admin
			.from('gym_workouts')
			.insert({
				user_id: USER_A.id,
				title: `E2E MM Yesterday ${yStamp}`,
				started_at: yesterday,
				last_modified_at: yesterday,
			})
			.select('id')
			.single();
		const yId = (yw?.id as string) ?? null;
		expect(yId).not.toBeNull();
		await admin.from('gym_sets').insert({
			workout_id: yId,
			exercise_name: `E2E Row ${yStamp}`,
			set_index: 0,
			reps: 5,
			weight_kg: 40,
		});

		try {
			await page.setViewportSize({ width: 1600, height: 1000 });
			await page.goto('/history');
			const groups = page.locator('.timeline-group');
			await expect(groups.first()).toBeVisible({ timeout: 15_000 });
			expect(await groups.count()).toBeGreaterThanOrEqual(2);

			// Wide: the first two day groups share a row (overlapping vertical
			// spans) with the second to the right of the first — a real
			// multi-column grid, not a single stranded column.
			const a = (await groups.nth(0).boundingBox())!;
			const b = (await groups.nth(1).boundingBox())!;
			expect(b.x).toBeGreaterThan(a.x + a.width / 2);
			expect(b.y).toBeLessThan(a.y + a.height);

			// Narrow: the grid collapses to one column — the second group
			// stacks below the first.
			await page.setViewportSize({ width: 720, height: 1000 });
			await expect
				.poll(async () => {
					const c = (await groups.nth(0).boundingBox())!;
					const d = (await groups.nth(1).boundingBox())!;
					return d.y >= c.y + c.height - 4;
				})
				.toBe(true);
		} finally {
			await admin.from('gym_workouts').delete().eq('id', yId);
		}
	});
});
