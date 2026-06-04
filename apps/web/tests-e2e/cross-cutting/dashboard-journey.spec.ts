import { expect, test, type Page } from '@playwright/test';

import { switchRunsToAllTime } from '../fixtures/helpers';
import { USER_A } from '../fixtures/users';

/**
 * End-to-end dashboard journey: setup → mutate → verify across the
 * stat cards, the goal grid, the Recent Runs list, and the goal
 * editor — all the dashboard widgets that derive off the same
 * `runs` + `goals` state.
 *
 * Phases (one test, broken into test.step blocks):
 *   1. Plant a 25 km/week distance goal in localStorage.
 *   2. Snapshot dashboard initial state (Total Runs, Longest Run,
 *      Recent Runs first row).
 *   3. Add a 10 km manual run via /history UI (covers RunEditor +
 *      createManualRun + redirect to /runs/[new-id]).
 *   4. Re-open dashboard → verify Total Runs +1, the new run is
 *      first in Recent Runs, the goal-card shows 40% (10/25).
 *   5. Edit the goal target via the goal-card editor → 5 km/week.
 *      Verify the goal-card now shows 100% (10 km against 5 km cap).
 *   6. Delete the run from /runs/[id]. Verify Total Runs returns to
 *      initial, the new run is gone from Recent Runs, the goal-card
 *      drops back near 0% (only seed runs from March/April remain
 *      and don't fall in the current week).
 *
 * This isn't strictly cross-feature with sagas (single user, no
 * realtime); it's the "kitchen sink" reactivity test that pins all
 * the derived dashboard widgets against the same data flow.
 */

const GOAL_KEY = `run_app.goals_v1:${USER_A.id}`;
const GOAL_ID = 'e2e-journey-goal';

async function goalCardForTarget(page: Page, kmText: RegExp) {
	return page.locator('.goal-card').filter({ hasText: kmText });
}

async function readTotalRuns(page: Page): Promise<number> {
	const card = page.locator('.stat-card', { hasText: 'Total Runs' });
	await expect(card).toBeVisible({ timeout: 10_000 });
	const txt = (await card.locator('.stat-value').textContent()) ?? '';
	const n = parseInt(txt.trim(), 10);
	expect(Number.isFinite(n)).toBe(true);
	return n;
}

async function recentRunDistances(page: Page): Promise<string[]> {
	const cells = page.locator('.run-row .run-distance');
	await expect(cells.first()).toBeVisible({ timeout: 10_000 });
	return await cells.allTextContents();
}

test.describe('dashboard end-to-end journey', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('add run → goal pct lifts → edit goal → delete run reverts every widget', async ({
		page,
		context
	}) => {
		// ── Setup ──────────────────────────────────────────────────
		// Plant a 25 km/week distance goal in localStorage BEFORE the
		// dashboard mounts. The dashboard reads goals via
		// `loadGoals(auth.user?.id)` keyed by user-scoped storage key.
		await test.step('plant goal in localStorage', async () => {
			const goalJson = JSON.stringify([
				{ id: GOAL_ID, period: 'week', distance_m: 25_000 }
			]);
			await context.addInitScript(
				(args: { key: string; value: string }) => {
					localStorage.setItem(args.key, args.value);
				},
				{ key: GOAL_KEY, value: goalJson }
			);
		});

		// ── Phase 1: snapshot initial dashboard state ──────────────
		let initialTotalRuns = 0;
		let initialFirstDistance = '';
		await test.step('snapshot dashboard initial state', async () => {
			await page.goto('/dashboard');

			initialTotalRuns = await readTotalRuns(page);
			expect(initialTotalRuns).toBeGreaterThan(0);

			const distances = await recentRunDistances(page);
			expect(distances.length).toBeGreaterThan(0);
			initialFirstDistance = distances[0];

			// Goal-card present at our 25 km/week target. Initial pct
			// should be 0% (seed runs are March/April, not current week).
			const goal = await goalCardForTarget(page, /25(\.0+)?\s*km/);
			await expect(goal).toBeVisible();
			await expect(goal.locator('.goal-overall')).toHaveText('0%');
		});

		// ── Phase 2: add a 10 km manual run via /history ──────────────
		let newRunId = '';
		await test.step('add a 10 km run via /history', async () => {
			await page.goto('/history');
			await switchRunsToAllTime(page);
			await page.getByRole('button', { name: '+ Add run' }).click();

			// RunEditor: started_at default is now; activity defaults
			// to 'run'; fill distance + duration explicitly. 10 km
			// against the 25 km/week goal lifts pct to 40%.
			await page.locator('input[type="datetime-local"]').first().fill(nowDatetimeLocal());
			await page.locator('input[type="number"]').first().fill('10');
			await page.locator('input[type="number"]').nth(1).fill('60');
			await page.locator('textarea').fill('e2e-dashboard-journey');
			await page.locator('form button[type="submit"]').click();

			// On success the page redirects to /runs/<new-id>.
			await page.waitForURL(/\/runs\/[0-9a-f-]+$/, { timeout: 10_000 });
			newRunId = page.url().match(/\/runs\/([0-9a-f-]+)$/)![1];
		});

		// ── Phase 3: dashboard reflects the new run ────────────────
		await test.step('dashboard shows +1 Total Runs, new entry in Recent, goal at 40%', async () => {
			await page.goto('/dashboard');
			expect(await readTotalRuns(page)).toBe(initialTotalRuns + 1);

			// Goal pct: 10 km / 25 km = 40%. The goal-overall span
			// renders rounded percent.
			const goal = await goalCardForTarget(page, /25(\.0+)?\s*km/);
			await expect(goal.locator('.goal-overall')).toHaveText('40%');

			// Recent Runs first row should now be the new run (most-
			// recent started_at). At minimum the first distance text
			// changed from the snapshot.
			const distances = await recentRunDistances(page);
			expect(distances[0]).not.toBe(initialFirstDistance);
		});

		// ── Phase 4: edit the goal target via the goal-card ────────
		await test.step('edit goal target → 5 km/week → goal-card shows 100%', async () => {
			const goal = await goalCardForTarget(page, /25(\.0+)?\s*km/);
			await goal.click();
			await expect(
				page.locator('.modal-header h2', { hasText: 'Edit goal' })
			).toBeVisible({ timeout: 5_000 });

			// First number input in the modal is the distance field.
			const distanceInput = page.locator('.modal input[type="number"]').first();
			await distanceInput.fill('5');
			await page.getByRole('button', { name: 'Save', exact: true }).click();
			await expect(page.locator('.modal')).toHaveCount(0);

			// 10 km / 5 km = 200% → capped at 100% by Math.min(1, ...).
			const updated = await goalCardForTarget(page, /5(\.0+)?\s*km/);
			await expect(updated.locator('.goal-overall')).toHaveText('100%');
		});

		// ── Phase 5: delete the run from /runs/[id] ────────────────
		await test.step('delete the run → all widgets revert', async () => {
			await page.goto(`/runs/${newRunId}`);
			await expect(page.getByRole('heading', { level: 1 })).toBeVisible({
				timeout: 10_000
			});

			// Header actions row has a Delete icon button (title="Delete")
			// that opens a ConfirmDialog with confirmLabel="Delete".
			await page.locator('button[title="Delete"]').click();
			const dialog = page.locator('.modal', { hasText: /Delete this run/ });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

			// Redirects back to /history after delete.
			await page.waitForURL(/\/history(\?.*)?$/, { timeout: 10_000 });
		});

		await test.step('dashboard widgets revert to initial', async () => {
			await page.goto('/dashboard');
			expect(await readTotalRuns(page)).toBe(initialTotalRuns);

			// Goal-card target is now 5 km (we edited it); pct drops
			// because the 10 km run is gone. Seed runs are
			// March/April so none fall in the current week → 0%.
			const updatedGoal = await goalCardForTarget(page, /5(\.0+)?\s*km/);
			await expect(updatedGoal.locator('.goal-overall')).toHaveText('0%');

			// Recent Runs first row should be back to the seeded value
			// (the new run is gone).
			const distances = await recentRunDistances(page);
			expect(distances[0]).toBe(initialFirstDistance);
		});
	});
});

function nowDatetimeLocal(): string {
	// `<input type="datetime-local">` accepts `YYYY-MM-DDTHH:MM` (no
	// timezone). Use the local clock minus 1 minute so the run is
	// stamped in the past and sorts above any other "today" runs.
	const d = new Date(Date.now() - 60_000);
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
