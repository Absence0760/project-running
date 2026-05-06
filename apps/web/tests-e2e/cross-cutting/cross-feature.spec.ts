import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Inter-feature interaction tests — surfaces where two product
 * primitives meet in the UI. Unit tests pin the math (goals.test.ts,
 * training.test.ts); these tests pin the actual cross-surface render.
 *
 * Today: runs ↔ goals (a fresh run lifts a dashboard goal-card to
 * 100%) and runs ↔ plans (Mark-as-done from the plan grid sets the
 * manually_completed flag, the day cell flips to .completed). Future:
 * a real run row linked via plan_workout_id auto-completes the
 * workout (would exercise linkRunToTodayWorkout) and the cross-user
 * kudos counter on a run-detail page (already covered indirectly by
 * cross-user/kudos but not on the run page itself).
 */

const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';
const GOAL_KEY = `run_app.goals_v1:${USER_A.id}`;

test.describe('runs ↔ goals on /dashboard', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.afterEach(async ({ context }) => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch (_) {
				/* best-effort */
			}
			runId = null;
		}
		// Clear the planted goal so the next test sees the default
		// (synthetic-only) goal-card set. The init-script wrote to
		// localStorage on the page that just ran; nuke it on every
		// open page so the in-memory view doesn't carry over.
		await context.clearCookies();
	});

	test('a 30 km run this week lifts a planted 25 km/week goal-card to 100%', async ({
		page,
		context
	}) => {
		// Plant the goal in localStorage BEFORE the dashboard mounts.
		// addInitScript runs on every navigation in the context. The
		// dashboard reads goals via loadGoals(auth.user?.id) which
		// keys by user-scoped storage key (legacy 'run_app.goals_v1'
		// migration is irrelevant — we write the new key).
		const goalId = `e2e-goal-${Date.now()}`;
		const goalJson = JSON.stringify([
			{ id: goalId, period: 'week', distance_m: 25_000 }
		]);
		await context.addInitScript(
			(args: { key: string; value: string }) => {
				localStorage.setItem(args.key, args.value);
			},
			{ key: GOAL_KEY, value: goalJson }
		);

		// Plant a 30 km run RIGHT NOW so it lands in the current week
		// regardless of week-start preference (Mon vs Sun). 30 km
		// against a 25 km goal also exercises the percent-cap path:
		// `Math.min(1, totalMetres / goal.distanceMetres)` → caps at
		// 1.0, "100%". Catches a regression where the cap was dropped
		// and the goal-card showed "120%".
		runId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date().toISOString(),
			duration_s: 9000,
			distance_m: 30_000,
			is_public: false,
			metadata: { activity_type: 'run' }
		});

		await page.goto('/dashboard');

		// Wait for at least one goal-card to render past the loading
		// state. Recent Runs visibility implies fetchRuns resolved,
		// and the goal-grid renders alongside Recent Runs.
		await expect(page.locator('.run-row .run-distance').first())
			.toBeVisible({ timeout: 10_000 });

		// The goal-card with our 25 km/week target should land at
		// 100% — the .goal-overall span renders `${pct * 100}%`.
		const goalCard = page
			.locator('.goal-card')
			.filter({ hasText: /25(\.0+)?\s*km/ });
		await expect(goalCard).toBeVisible({ timeout: 10_000 });
		await expect(goalCard.locator('.goal-overall')).toHaveText('100%');
	});
});

test.describe('runs ↔ plans on /plans/[id]', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		// Clear any manually_completed=true row on the Sydney Half plan
		// — the seed has zero (the one seeded completion uses
		// completed_run_id, not manually_completed), so this scoops
		// up exactly the workout the test marked.
		const admin = getAdminClient();
		const { data: weeks } = await admin
			.from('plan_weeks')
			.select('id')
			.eq('plan_id', SYDNEY_HALF_PLAN_ID);
		const weekIds = (weeks ?? []).map((w) => (w as { id: string }).id);
		if (weekIds.length === 0) return;
		await admin
			.from('plan_workouts')
			.update({ manually_completed: false })
			.in('week_id', weekIds)
			.eq('manually_completed', true);
	});

	test('Mark-as-done in the plan grid flips the day cell to .completed', async ({
		page
	}) => {
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(
			page.getByRole('heading', { level: 1, name: /Sydney Half 2026/ })
		).toBeVisible({ timeout: 10_000 });

		// Snapshot the seeded completion count. The seed has exactly
		// one .day.completed (from completed_run_id on the week-0
		// long-run match in seed.sql lines ~496-510).
		const completedBefore = await page.locator('.day.completed').count();
		expect(completedBefore).toBe(1);

		// Click the first non-rest, non-completed day-link. Day order
		// matches workout-scheduled-date order, so picking .first()
		// is deterministic across runs.
		await page
			.locator('.day:not(.rest):not(.completed) .day-link')
			.first()
			.click();

		// WorkoutEditor mounts inside a Modal; the "Mark as done"
		// button writes manually_completed=true via markWorkoutCompleted.
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		await modal.getByRole('button', { name: 'Mark as done' }).click();

		// Modal closes + the parent reloads via load() (see the
		// `onSaved` handler in /plans/[id]/+page.svelte). The freshly
		// completed workout's day cell now carries .completed.
		await expect(modal).toHaveCount(0);
		await expect(page.locator('.day.completed')).toHaveCount(
			completedBefore + 1,
			{ timeout: 10_000 }
		);
	});
});
