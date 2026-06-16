import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun, deleteRun } from '../fixtures/simulate';

/**
 * Cross-modal /history timeline journey — one runner logs activity in all
 * THREE modalities (a run, a gym workout, a food entry), and the unified
 * /history timeline stitches them into one reverse-chronological feed. The
 * thread the per-surface spec (gym/multimodal_home_history.spec.ts) only
 * touches a slice at a time, walked end to end on a CLEAN, fully-owned canvas
 * so the interleave order + the per-chip filter are unambiguous.
 *
 * What gym/multimodal_home_history.spec.ts already owns (and this does NOT
 * re-litigate): the data-presence chip self-hiding (chips appear once a
 * second modality exists), the All-view Log menu's keyboard support, the
 * single-modality direct-action + "View all" header shape, and the back-nav
 * snapshot restore race-guard. That spec seeds ONLY a lift (as the shared
 * USER_A, whose runs/meals are seed data) and never asserts the timeline
 * INTERLEAVES the three modalities in time order, nor that each kind chip
 * filters to exactly its own modality, nor that all three Log actions open
 * their distinct editors.
 *
 * This journey owns that uncovered STITCHED cross-modal arc:
 *   1. Seed one run + one lift + one meal, all on the SAME recent day at
 *      three distinct times-of-day (lift newest, then run, then meal oldest)
 *      via service-role (insertRun + gym_workouts/gym_sets + food_log). A
 *      clean saga user means these three are the ONLY activities, so the
 *      timeline order is fully deterministic.
 *   2. /history All tab: the three rows render in one day group, newest-first
 *      by started_at — lift → run → meal — proving the `activities` view's
 *      cross-modal UNION (each branch injects its own `kind`) is interleaved
 *      by time, not grouped by modality.
 *   3. Kind chips (Runs / Lifts / Meals) appear (>1 modality present) and each
 *      filters the timeline to exactly its own modality — one row, the right
 *      glyph kind, the others gone.
 *   4. The All-view Log menu opens each of the three editors in place: Log run
 *      → RunEditor ("Add a run" dialog), Log workout → GymEditor ("New
 *      workout"), Log food → FoodLogEditor ("Log food") — no navigation away
 *      from /history.
 *   5. Tear everything down in try/finally (run via deleteRun for its Storage
 *      sweep; the gym workout + food row explicitly; the saga user + its
 *      cascade last).
 *
 * Grounding for the per-row shape (src/routes/history/+page.svelte):
 *   - rows are `.timeline-row[data-kind=run|lift|meal]`; run/lift are <a>
 *     links (activityHref → /runs/[id], /gym/[id]), meals render as a read-only
 *     <div> (no detail route yet).
 *   - the lift row's primary text is the workout title; the run row's primary
 *     is the formatted distance; the meal row's primary is item_name.
 *   - chips are role=group buttons labelled All/Runs/Lifts/Meals; client-side
 *     filter over the already-fetched window (no per-chip round-trip).
 *
 * The saga user pre-accepts the GDPR cookie banner (role="dialog", floats
 * over the Log modals + could intercept the menu clicks) via an init script
 * injected before the first navigation — the consent module reads
 * localStorage once on import.
 */
test.describe('history cross-modal timeline journey — three modalities interleave, chips filter, Log opens each editor', () => {
	test('a run + a lift + a meal stitch into one time-ordered timeline; kind chips filter; Log opens RunEditor / GymEditor / FoodLogEditor', async ({
		browser,
	}) => {
		const admin = getAdminClient();
		const stamp = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const liftTitle = `e2e-xmodal-lift-${stamp}`;
		const mealName = `e2e-xmodal-meal-${stamp}`;

		// Three distinct times-of-day on the SAME recent day so all three land
		// in one timeline day group and their newest-first order is exact:
		// lift (newest) → run → meal (oldest). Anchored ~2 days back (well
		// inside the 200-activity window, and unambiguously NOT "today" if a
		// clock crosses midnight — the day label doesn't matter, the relative
		// order within the group does).
		const dayBase = Date.now() - 2 * 86_400_000;
		const liftAt = new Date(dayBase + 18 * 3600_000).toISOString(); // newest
		const runAt = new Date(dayBase + 12 * 3600_000).toISOString();
		const mealAt = new Date(dayBase + 7 * 3600_000).toISOString(); // oldest

		let users: SagaUser[] = [];
		let runId = '';
		let workoutId: string | null = null;
		let foodId: string | null = null;

		try {
			users = await createSagaUsers(1, { displayNames: ['Cross-Modal Saga'] });
			const user = users[0];

			// ── Seed all three modalities for this clean, fully-owned canvas ──
			await test.step('seed one run + one lift + one meal at three distinct same-day times', async () => {
				// Run (5 km, 30 min) — appears as a timeline row whose primary is
				// the formatted distance and whose href is /runs/[id].
				runId = await insertRun({
					user_id: user.id,
					started_at: runAt,
					distance_m: 5000,
					duration_s: 1800,
				});

				// Lift — a gym_workouts row + one weighted set; the set trigger
				// (20261214_001) maintains set_count/volume_kg the view reads.
				const { data: w, error: wErr } = await admin
					.from('gym_workouts')
					.insert({
						user_id: user.id,
						title: liftTitle,
						started_at: liftAt,
						last_modified_at: liftAt,
					})
					.select('id')
					.single();
				expect(wErr).toBeNull();
				workoutId = (w?.id as string) ?? null;
				expect(workoutId).not.toBeNull();
				const { error: setErr } = await admin.from('gym_sets').insert({
					workout_id: workoutId,
					exercise_name: `e2e-bench-${stamp}`,
					set_index: 0,
					reps: 8,
					weight_kg: 60,
				});
				expect(setErr).toBeNull();

				// Meal — a food_log row. NOTE: the time column is `started_at`
				// (renamed from logged_at in 20261208_001); the activities view's
				// meal branch projects it as the timeline timestamp.
				const { data: f, error: fErr } = await admin
					.from('food_log')
					.insert({
						user_id: user.id,
						started_at: mealAt,
						last_modified_at: mealAt,
						item_name: mealName,
						meal_slot: 'breakfast',
						calories: 420,
					})
					.select('id')
					.single();
				expect(fErr).toBeNull();
				foodId = (f?.id as string) ?? null;
				expect(foodId).not.toBeNull();
			});

			const ctx = await browser.newContext({ storageState: user.storageStatePath });
			// Pre-accept the GDPR cookie banner so its role="dialog" can't float
			// over the Log modals and intercept the menu-item clicks. Inject
			// before the first navigation (consent reads localStorage on import).
			await ctx.addInitScript(() => {
				localStorage.setItem(
					'cookie_consent',
					JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
				);
			});
			const page = await ctx.newPage();

			try {
				// ── 1. All tab interleaves the three modalities by time ──
				await test.step('All tab stitches lift → run → meal in newest-first time order', async () => {
					await page.goto('/history');

					// The three planted rows are the ONLY activities (clean saga
					// canvas), so the timeline holds exactly three rows.
					const rows = page.locator('.timeline-row');
					await expect(rows).toHaveCount(3, { timeout: 15_000 });

					// Newest-first ordering across modalities: lift (18:00) first,
					// run (12:00) second, meal (07:00) last — the cross-modal UNION
					// is interleaved by started_at, not grouped per modality. Assert
					// both the kind sequence and the per-row identity.
					await expect(rows.nth(0)).toHaveAttribute('data-kind', 'lift');
					await expect(rows.nth(0)).toContainText(liftTitle);
					await expect(rows.nth(1)).toHaveAttribute('data-kind', 'run');
					await expect(rows.nth(2)).toHaveAttribute('data-kind', 'meal');
					await expect(rows.nth(2)).toContainText(mealName);

					// The run row links to its detail route; the meal row is a
					// read-only div (no detail route yet), so it carries no href.
					await expect(rows.nth(1)).toHaveAttribute('href', `/runs/${runId}`);
					await expect(rows.nth(2)).not.toHaveAttribute('href', /.+/);
				});

				// ── 2. Each kind chip filters to exactly its modality ──
				await test.step('Runs / Lifts / Meals chips each filter to one row of the right kind', async () => {
					const rows = page.locator('.timeline-row');

					// Chips only exist because a second modality is present — assert
					// all three modality chips render (the data-presence gate).
					const runsChip = page.getByRole('button', { name: 'Runs', exact: true });
					const liftsChip = page.getByRole('button', { name: 'Lifts', exact: true });
					const mealsChip = page.getByRole('button', { name: 'Meals', exact: true });
					await expect(runsChip).toBeVisible();
					await expect(liftsChip).toBeVisible();
					await expect(mealsChip).toBeVisible();

					// Runs chip → only the run row survives the client-side filter.
					await runsChip.click();
					await expect(rows).toHaveCount(1);
					await expect(rows.first()).toHaveAttribute('data-kind', 'run');
					await expect(rows.first()).toHaveAttribute('href', `/runs/${runId}`);

					// Lifts chip → only the lift row, linking to its gym detail.
					await liftsChip.click();
					await expect(rows).toHaveCount(1);
					await expect(rows.first()).toHaveAttribute('data-kind', 'lift');
					await expect(rows.first()).toContainText(liftTitle);
					await expect(rows.first()).toHaveAttribute('href', `/gym/${workoutId}`);

					// Meals chip → only the meal row.
					await mealsChip.click();
					await expect(rows).toHaveCount(1);
					await expect(rows.first()).toHaveAttribute('data-kind', 'meal');
					await expect(rows.first()).toContainText(mealName);

					// Back to All → all three return.
					await page.getByRole('button', { name: 'All', exact: true }).click();
					await expect(rows).toHaveCount(3);
				});

				// ── 3. The All-view Log menu opens each of the three editors ──
				await test.step('Log menu opens RunEditor / GymEditor / FoodLogEditor in place', async () => {
					const logBtn = page.getByRole('button', { name: 'Log', exact: true });
					await expect(logBtn).toBeVisible();

					// Log run → RunEditor in the "Add a run" modal, no navigation.
					// Close each via Escape (Modal listens for it) so the next
					// open starts clean — the menu trigger is the only "Log" button.
					await logBtn.click();
					await page.getByRole('menuitem', { name: 'Log run' }).click();
					await expect(page.getByRole('dialog', { name: 'Add a run' })).toBeVisible();
					await expect(page).toHaveURL(/\/history$/);
					await page.keyboard.press('Escape');
					await expect(page.getByRole('dialog', { name: 'Add a run' })).toHaveCount(0);

					// Log workout → GymEditor in the "New workout" modal.
					await logBtn.click();
					await page.getByRole('menuitem', { name: 'Log workout' }).click();
					await expect(page.getByRole('dialog', { name: 'New workout' })).toBeVisible();
					await expect(page).toHaveURL(/\/history$/);
					await page.keyboard.press('Escape');
					await expect(page.getByRole('dialog', { name: 'New workout' })).toHaveCount(0);

					// Log food → FoodLogEditor in the "Log food" modal.
					await logBtn.click();
					await page.getByRole('menuitem', { name: 'Log food' }).click();
					await expect(page.getByRole('dialog', { name: 'Log food' })).toBeVisible();
					await expect(page).toHaveURL(/\/history$/);
				});
			} finally {
				await ctx.close();
			}
		} finally {
			// Sweep planted rows before the saga user (the CASCADE would also
			// take the gym/food rows, but be explicit + use deleteRun for its
			// Storage sweep). Best-effort — never mask a journey failure.
			if (runId) await deleteRun(runId).catch(() => {});
			if (workoutId) await admin.from('gym_workouts').delete().eq('id', workoutId).then(() => {}, () => {});
			if (foodId) await admin.from('food_log').delete().eq('id', foodId).then(() => {}, () => {});
			if (users.length > 0) await deleteSagaUsers(users).catch(() => {});
		}
	});
});
