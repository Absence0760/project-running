import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

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
		// Clear any manually_completed=true row on the Richmond Half plan
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
			page.getByRole('heading', { level: 1, name: /Richmond Half 2026/ })
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

	test('Mark-as-done in /plans/[id] propagates to the progress circle (.pct)', async ({
		page
	}) => {
		// The plan-detail page renders a progress ring with
		// `<span class="pct">{pct}%</span>` and `<span class="done">
		// {completed} / {totalActive}</span>`. Both are derived from
		// the same workouts array the day-grid renders from, BUT
		// they live in a different component (the hero block, not
		// the week-grid `.day` cells). Pins the load → render →
		// reload flow that ties the two views together.
		//
		// Tried writing this against the dashboard's `.plan-progress`
		// span instead, but that span only mounts inside the
		// `{#if planOverview?.todayWorkout}` branch — there's no
		// today-workout in the seed for the current wall-clock, so
		// the span doesn't render and the test had no signal to read.
		// Same-page is still cross-component (week-grid + progress
		// ring), and the same `markWorkoutCompleted` → `load()`
		// pipeline is what would feed the dashboard if a today-
		// workout were present.
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.pct')).toBeVisible({ timeout: 10_000 });
		const beforeText = (await page.locator('.pct').textContent()) ?? '';
		const beforePct = parseInt(beforeText.match(/(\d+)/)?.[1] ?? '-1', 10);
		expect(beforePct).toBeGreaterThanOrEqual(0);

		await page
			.locator('.day:not(.rest):not(.completed) .day-link')
			.first()
			.click();
		const modal = page.locator('.modal');
		await expect(modal).toBeVisible({ timeout: 5_000 });
		await modal.getByRole('button', { name: 'Mark as done' }).click();
		await expect(modal).toHaveCount(0);

		// Same-page re-fetch: load() in /plans/[id] runs after the
		// editor's onSaved callback. The .pct value should be strictly
		// higher than before — exact +N% varies with plan size, so
		// the contract is "more than before."
		await expect
			.poll(async () => {
				const txt = (await page.locator('.pct').textContent()) ?? '';
				return parseInt(txt.match(/(\d+)/)?.[1] ?? '-1', 10);
			}, { timeout: 10_000 })
			.toBeGreaterThan(beforePct);
	});
});

/**
 * Cross-user kudos → owner-side count refresh on /runs/[id].
 *
 * `cross-user/kudos.spec.ts` covers alex's write + reload-persists +
 * rescind on the SHARE page. This test covers the OTHER side: runner
 * (the owner) navigating to their own /runs/[id] sees the kudos
 * count alex just wrote. Pins:
 *   - run_kudos visibility crosses the owner / non-owner boundary
 *     (RLS via is_run_visible_to allows the owner to read kudos a
 *     non-owner gave).
 *   - The same `fetchRunKudos` call resolves the same number on
 *     /runs/[id] as on /share/run/[id], so the kudos count isn't a
 *     surface-specific quirk.
 */
test.describe('runs ↔ cross-user kudos', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('alex kudos on /share/run/[id] surfaces as count=1 on runner\'s /runs/[id]', async ({
		page,
		browser
	}) => {
		// Alex writes the kudos in a separate browser context. The
		// share page is the canonical non-owner kudos surface; owner
		// /runs/[id] would be RLS-blocked for alex anyway.
		const alexCtx = await browser.newContext({
			storageState: USER_B.storageStatePath
		});
		const alexPage = await alexCtx.newPage();
		try {
			await alexPage.route('**/functions/v1/clip-public-track', (route) =>
				route.fulfill({
					status: 200,
					contentType: 'application/json',
					body: JSON.stringify({ points: [] })
				})
			);
			await alexPage.goto(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
			const alexBtn = alexPage.locator('.kudos-btn');
			await expect(alexBtn).toBeVisible({ timeout: 10_000 });
			// Pinned run starts at 0 kudos (seed excludes it from the
			// cross-user-engagement inserts via the `id != '...'` filter).
			await expect(alexPage.locator('.kudos-count')).toHaveText('0');
			await alexBtn.click();
			// Wait for the optimistic + DB-confirmed state to settle —
			// proves the row is actually written before runner reads.
			await expect(alexBtn).toHaveClass(/given/);
			await expect(alexPage.locator('.kudos-count')).toHaveText('1');

			// Now runner reads. /runs/[id] is the owner-only detail page;
			// fetchRunById gates on user_id, RunSocial mounts and calls
			// fetchRunKudos which reads run_kudos via is_run_visible_to.
			await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
			await expect(page.getByRole('heading', { level: 1 })).toBeVisible({
				timeout: 10_000
			});
			await expect(page.locator('.kudos-count')).toHaveText('1', {
				timeout: 10_000
			});

			// Cleanup — alex rescinds so the suite stays idempotent.
			await alexPage.locator('.kudos-btn').click();
			await expect(alexPage.locator('.kudos-count')).toHaveText('0');
		} finally {
			await alexCtx.close();
		}
	});
});
