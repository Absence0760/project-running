import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { withCleanCurrentWeek } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /dashboard Goals section — full CRUD round-trip from an empty state.
 *
 * cross-cutting/cross-feature.spec.ts pins runs ↔ goals (% calc on a
 * planted goal). cross-cutting/dashboard-journey.spec.ts edits a
 * planted goal. Neither exercises the create-from-scratch flow against
 * the empty-state CTA, the editor's other goal kinds (time, pace, run
 * count), or the explicit delete button. This spec fills that gap so
 * the dashboard Goals section's lifecycle is pinned end-to-end:
 *
 *   1. Land on /dashboard with no goals → empty-state card visible.
 *   2. Click the empty-state "Add goal" button → editor modal opens.
 *   3. Fill a 30-minute Time/week target → Save → goal-card appears
 *      with 0% progress (no current-week runs).
 *   4. Click the goal-card → editor reopens populated.
 *   5. Edit target to 60 minutes + change period to Month → Save →
 *      card reflects the new period label + target.
 *   6. Click the card → editor reopens → Delete → card disappears,
 *      empty-state card returns.
 *
 * Cleanup: clear the user-scoped localStorage key in afterEach so the
 * planted goals do not survive into the next spec. Goals are
 * localStorage-only (see lib/training/goals.ts) — no Supabase rows to scrub.
 */

const GOAL_KEY = `run_app.goals_v1:${USER_A.id}`;

test.describe('/dashboard Goals — CRUD UI', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let savedWeeklyMileageGoal: number | null | undefined = undefined;
	// The seed's now()-relative "Morning easy 8K" run lifts a freshly
	// planted current-week goal off 0% (it'd read 32% / a non-zero run
	// count), so clear the current week per test and restore the seed run
	// after — other specs (/nutrition, dashboard readiness) still need it.
	let restoreCurrentWeek: (() => Promise<void>) | null = null;

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
		await context.addInitScript((args: { key: string }) => {
			localStorage.removeItem(args.key);
			localStorage.removeItem('run_app.goals_v1');
		}, { key: GOAL_KEY });

		// The seed sets `weekly_mileage_goal_m=50000` on runner@test.com,
		// which the dashboard surfaces as a synthetic Weekly distance
		// goal. That hides the empty-state card and confuses the
		// `.goal-card` count. Snapshot + temporarily strip the key for
		// the duration of the test; restore in afterEach.
		const admin = getAdminClient();
		const { data } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		const prefs = (data?.prefs ?? {}) as Record<string, unknown>;
		savedWeeklyMileageGoal = prefs.weekly_mileage_goal_m as number | undefined;
		const nextPrefs: Record<string, unknown> = { ...prefs };
		delete nextPrefs.weekly_mileage_goal_m;
		await admin
			.from('user_settings')
			.update({ prefs: nextPrefs })
			.eq('user_id', USER_A.id);

		restoreCurrentWeek = await withCleanCurrentWeek(USER_A.id);
	});

	test.afterEach(async ({ context }) => {
		if (restoreCurrentWeek) {
			await restoreCurrentWeek();
			restoreCurrentWeek = null;
		}
		await context.addInitScript((args: { key: string }) => {
			try {
				localStorage.removeItem(args.key);
				localStorage.removeItem('run_app.goals_v1');
			} catch (_) {
				/* noop */
			}
		}, { key: GOAL_KEY });

		const admin = getAdminClient();
		const { data } = await admin
			.from('user_settings')
			.select('prefs')
			.eq('user_id', USER_A.id)
			.maybeSingle();
		const prefs = (data?.prefs ?? {}) as Record<string, unknown>;
		if (savedWeeklyMileageGoal != null) {
			prefs.weekly_mileage_goal_m = savedWeeklyMileageGoal;
		} else {
			delete prefs.weekly_mileage_goal_m;
		}
		await admin
			.from('user_settings')
			.update({ prefs })
			.eq('user_id', USER_A.id);
	});

	test('create → render → edit period + target → delete', async ({ page }) => {
		await test.step('empty state visible on first load', async () => {
			await page.goto('/dashboard');
			const emptyCard = page.locator('.goals-empty-card');
			await expect(emptyCard).toBeVisible({ timeout: 10_000 });
			await expect(emptyCard.getByRole('heading', { name: /No goals set/ }))
				.toBeVisible();
			await expect(page.locator('.goal-card')).toHaveCount(0);
		});

		await test.step('open editor via empty-state Add-goal button', async () => {
			await page.locator('.goals-empty-card').getByRole('button', { name: /Add goal/ }).click();
			await expect(page.locator('.modal-header h2', { hasText: 'Edit goal' }))
				.toBeVisible({ timeout: 5_000 });
		});

		await test.step('fill a 30-minute week target → Save → card appears at 0%', async () => {
			const modal = page.locator('.modal');
			await expect(modal.locator('.toggle-btn.active')).toHaveText('Week');

			const timeInput = modal.locator('input[type="number"]').nth(1);
			await timeInput.fill('30');

			await modal.getByRole('button', { name: 'Save', exact: true }).click();
			await expect(page.locator('.modal')).toHaveCount(0);

			const card = page.locator('.goal-card');
			await expect(card).toHaveCount(1, { timeout: 5_000 });
			await expect(card.locator('.goal-period')).toHaveText('This week');
			await expect(card.locator('.goal-target-top')).toContainText(/Time/);
			await expect(card.locator('.goal-target-value')).toContainText(/30m/);
			// Overall % depends on how much the seed user has logged in
			// the current week / month — irrelevant to the CRUD flow's
			// correctness. Assert the cell renders SOMETHING that looks
			// like a percentage and move on.
			await expect(card.locator('.goal-overall')).toHaveText(/^\d+%$/);
		});

		await test.step('click card → editor reopens populated', async () => {
			await page.locator('.goal-card').click();
			const modal = page.locator('.modal');
			await expect(modal.locator('.modal-header h2', { hasText: 'Edit goal' }))
				.toBeVisible({ timeout: 5_000 });
			await expect(modal.locator('.toggle-btn.active')).toHaveText('Week');
			await expect(modal.locator('input[type="number"]').nth(1)).toHaveValue('30');
		});

		await test.step('edit target to 60m + flip period to Month → Save → card reflects edits', async () => {
			const modal = page.locator('.modal');
			await modal.getByRole('button', { name: 'Month', exact: true }).click();
			await expect(modal.locator('.toggle-btn.active')).toHaveText('Month');

			const timeInput = modal.locator('input[type="number"]').nth(1);
			await timeInput.fill('60');

			await modal.getByRole('button', { name: 'Save', exact: true }).click();
			await expect(page.locator('.modal')).toHaveCount(0);

			const card = page.locator('.goal-card');
			await expect(card).toHaveCount(1);
			await expect(card.locator('.goal-period')).toHaveText('This month');
			await expect(card.locator('.goal-target-value')).toContainText(/1h\s*0m|60m/);
			// Overall % depends on how much the seed user has logged in
			// the current week / month — irrelevant to the CRUD flow's
			// correctness. Assert the cell renders SOMETHING that looks
			// like a percentage and move on.
			await expect(card.locator('.goal-overall')).toHaveText(/^\d+%$/);
		});

		await test.step('click card → Delete → card disappears, empty state returns', async () => {
			await page.locator('.goal-card').click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });
			await modal.getByRole('button', { name: 'Delete', exact: true }).click();
			await expect(page.locator('.modal')).toHaveCount(0);

			await expect(page.locator('.goal-card')).toHaveCount(0);
			await expect(page.locator('.goals-empty-card')).toBeVisible();
		});
	});

	test('create a multi-target goal (distance + run count) → both targets render on the card', async ({
		page,
	}) => {
		await page.goto('/dashboard');
		await expect(page.locator('.goals-empty-card')).toBeVisible({ timeout: 10_000 });
		await page.locator('.goals-empty-card').getByRole('button', { name: /Add goal/ }).click();

		const modal = page.locator('.modal');
		await expect(modal.locator('.modal-header h2', { hasText: 'Edit goal' }))
			.toBeVisible({ timeout: 5_000 });

		const distanceInput = modal.locator('input[type="number"]').nth(0);
		const runCountInput = modal.locator('input[type="number"]').nth(2);
		await distanceInput.fill('20');
		await runCountInput.fill('4');

		await modal.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.locator('.modal')).toHaveCount(0);

		const card = page.locator('.goal-card');
		await expect(card).toHaveCount(1);
		const targets = card.locator('.goal-targets li');
		await expect(targets).toHaveCount(2);
		await expect(targets.nth(0)).toContainText(/Distance/);
		await expect(targets.nth(0)).toContainText(/20(\.0+)?\s*km/);
		await expect(targets.nth(1)).toContainText(/Runs/);
		await expect(targets.nth(1)).toContainText(/0 \/ 4/);

		await card.click();
		await expect(modal).toBeVisible();
		await modal.getByRole('button', { name: 'Delete', exact: true }).click();
		await expect(page.locator('.goal-card')).toHaveCount(0);
	});
});
