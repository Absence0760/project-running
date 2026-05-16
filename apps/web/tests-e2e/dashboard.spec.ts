import { expect, test } from '@playwright/test';

import { deleteRun, insertRun } from './fixtures/simulate';
import { USER_A } from './fixtures/users';

/**
 * /dashboard — User A's home screen after sign-in.
 *
 * Tests cover the page mount + the interactive stat cards. The
 * notification-bell flow is in cross-user/notifications.spec.ts
 * because it's a multi-context test. The training-load chart and
 * goals-card lifecycle live here as future tests when those
 * surfaces deepen.
 */

test.describe('/dashboard', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('renders with seeded mileage + recent runs', async ({ page }) => {
		await page.goto('/dashboard');

		// "Mileage" + "Recent Runs" are h2's on the dashboard. Asserting
		// them proves the page rendered past the loading skeleton AND
		// the per-section components loaded their seeded data.
		await expect(
			page.getByRole('heading', { name: /mileage/i, level: 2 })
		).toBeVisible();
		await expect(
			page.getByRole('heading', { name: /recent runs/i, level: 2 })
		).toBeVisible();
	});

	test('mileage chart Week → Month → Year toggle activates the matching button', async ({
		page
	}) => {
		// The mileage card has three view buttons (Week / Month / Year)
		// that flip `mileageView` and re-derive the chart data. The
		// regression risk is the buttons drifting from the $state
		// (e.g. a refactor that breaks the class:active wiring).
		// We assert the active class flips, not the chart contents
		// (which depend on seed dates that can drift).
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		const weekBtn = page.getByRole('button', { name: 'Week', exact: true });
		const monthBtn = page.getByRole('button', { name: 'Month', exact: true });
		const yearBtn = page.getByRole('button', { name: 'Year', exact: true });

		// Default is weekly.
		await expect(weekBtn).toHaveClass(/active/);
		await expect(monthBtn).not.toHaveClass(/active/);

		await monthBtn.click();
		await expect(monthBtn).toHaveClass(/active/);
		await expect(weekBtn).not.toHaveClass(/active/);

		await yearBtn.click();
		await expect(yearBtn).toHaveClass(/active/);
		await expect(monthBtn).not.toHaveClass(/active/);

		// Restore so the period-summary test below sees the default
		// state (this test is alphabetically first by describe).
		await weekBtn.click();
		await expect(weekBtn).toHaveClass(/active/);
	});

	test('goal create + delete round-trip: + Add goal → fill distance → Save → goal-card visible → Delete', async ({
		page
	}) => {
		// Goals live in user_settings.prefs.goals (a jsonb array).
		// The dashboard surfaces them as goal-cards with a progress
		// ring. "+ Add goal" opens the editor modal; filling
		// distance + clicking Save persists to user_settings + makes
		// a card appear; clicking the card re-opens the editor;
		// Delete inside the editor removes it.
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		// runner's seed has `weekly_mileage_goal_m=50000` which the
		// dashboard surfaces as a synthetic week-period goal-card.
		// IMPORTANT: creating a *real* week-period distance goal would
		// REPLACE the synthetic one (see `displayGoals` derived in
		// dashboard/+page.svelte), so we create a Month-period goal —
		// the synthetic stays + the real one is added → count goes
		// from 1 → 2.
		const initialCount = await page.locator('.goal-card').count();

		// ── Create ──
		await page.getByRole('button', { name: /\+ Add goal/ }).click();
		await expect(page.locator('.modal-header h2', { hasText: 'Edit goal' }))
			.toBeVisible({ timeout: 5_000 });

		// Switch period to Month (synthetic-replacement guard).
		await page
			.locator('.modal')
			.getByRole('button', { name: 'Month', exact: true })
			.click();

		// Fill distance (km — runner's preferred_unit). 100 km/month.
		await page.locator('.modal input[type="number"]').first().fill('100');
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await expect(page.locator('.modal')).toHaveCount(0);

		// New goal-card visible (initial + 1).
		await expect(page.locator('.goal-card')).toHaveCount(initialCount + 1);

		// ── Delete via the editor ──
		// Two cards visible (synthetic Week + new Month). Click the
		// Month one — clicking the synthetic instead navigates to
		// /settings/preferences (it's its only edit affordance).
		await page
			.locator('.goal-card')
			.filter({ hasText: 'Month' })
			.click();
		await expect(page.locator('.modal-header h2', { hasText: 'Edit goal' }))
			.toBeVisible({ timeout: 5_000 });
		await page.getByRole('button', { name: 'Delete', exact: true }).click();
		await expect(page.locator('.modal')).toHaveCount(0);

		// Card count returns to baseline.
		await expect(page.locator('.goal-card')).toHaveCount(initialCount);
	});

	test('clicking "This Week" stat tile opens the period summary modal', async ({
		page
	}) => {
		// The dashboard's "This Week" stat card is a button (rather
		// than a static tile) so the user can drill into the period.
		// On click it sets `periodModal = { type: 'week', date: now }`
		// which mounts the shared <PeriodSummary> inside a Modal with
		// title "Period summary".
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		// The stat card may render with a 0 km value if "this week"
		// (real wall-clock) doesn't intersect any seeded run — that's
		// fine, we're testing modal-open, not the contents.
		const thisWeekCard = page.getByRole('button', { name: /This Week/ }).first();
		await expect(thisWeekCard).toBeVisible();
		await thisWeekCard.click();

		// The Modal shell from app.css uses .modal-backdrop + .modal,
		// with the title rendered in .modal-header h2. Asserting the
		// header text is the most stable signal that the right modal
		// opened (not e.g. the goal editor).
		await expect(
			page.locator('.modal-header h2', { hasText: 'Period summary' })
		).toBeVisible({ timeout: 5_000 });

		// PeriodSummary's own week/month toggle is inside the modal;
		// its presence confirms the body mounted, not just the shell.
		await expect(
			page.locator('.modal').getByRole('button', { name: 'Week' })
		).toBeVisible();
	});

	test('the four stat cards (This Week / Total Runs / Longest Run / Pace) render', async ({
		page
	}) => {
		await page.goto('/dashboard');
		const labels = page.locator('.stat-label');
		await expect(labels.filter({ hasText: 'This Week' }).first())
			.toBeVisible({ timeout: 10_000 });
		await expect(labels.filter({ hasText: 'Total Runs' }).first()).toBeVisible();
		await expect(labels.filter({ hasText: 'Longest Run' }).first()).toBeVisible();
		await expect(labels.filter({ hasText: /Pace/ }).first()).toBeVisible();
	});

	test('Activity heatmap renders below the Mileage chart', async ({ page }) => {
		await page.goto('/dashboard');
		await expect(page.getByRole('heading', { level: 2, name: 'Activity' }))
			.toBeVisible({ timeout: 10_000 });
	});

	test('Mileage chart Year toggle is reachable and stays selected', async ({
		page
	}) => {
		await page.goto('/dashboard');
		await page.getByRole('button', { name: 'Year', exact: true }).click();
		await expect(page.getByRole('button', { name: 'Year', exact: true }))
			.toHaveClass(/active/);
	});

	test('inserting a new run via service-role bumps Total Runs and updates Longest Run on reload', async ({
		page
	}) => {
		// Pin "data → dashboard" reactivity. Total Runs is `filteredRuns.length`
		// and Longest Run is `max(distance_m)`. Plant a run that is 1 km
		// longer than any seed (the seed's longest is the 18 km long run,
		// so 50 km wins by a wide margin) and reload — both stats must
		// reflect it. A regression that broke fetchRuns wiring or the
		// derived stat would show up here.
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		const totalRunsCard = page
			.locator('.stat-card')
			.filter({ has: page.locator('.stat-label', { hasText: 'Total Runs' }) });
		const longestCard = page
			.locator('.stat-card')
			.filter({ has: page.locator('.stat-label', { hasText: 'Longest Run' }) });

		const initialTotalText = await totalRunsCard.locator('.stat-value').innerText();
		const initialTotal = parseInt(initialTotalText.trim(), 10);
		expect(Number.isFinite(initialTotal)).toBe(true);

		// 50 km — well above any seeded distance. preferred_unit is km
		// for runner so the card formats as "50.0 km".
		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 50_000,
			duration_s: 18_000,
			is_public: false
		});

		try {
			await page.reload();
			await page.waitForLoadState('networkidle');

			// Total Runs incremented.
			await expect(totalRunsCard.locator('.stat-value')).toHaveText(
				String(initialTotal + 1),
				{ timeout: 10_000 }
			);

			// Longest Run reflects the 50 km — formatDistance prints
			// "50.0 km" with one decimal.
			await expect(longestCard.locator('.stat-value')).toContainText('50.0', {
				timeout: 5_000
			});
		} finally {
			await deleteRun(planted);
		}
	});

	test('deleting a planted run via service-role decrements Total Runs on reload', async ({
		page
	}) => {
		// Companion to the insert test above. Pins the inverse direction:
		// data removed → stat decrements. Catches a regression where
		// fetchRuns aggressively caches and a deletion isn't reflected
		// until the next session.
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		const totalRunsCard = page
			.locator('.stat-card')
			.filter({ has: page.locator('.stat-label', { hasText: 'Total Runs' }) });
		const baselineTotal = parseInt(
			(await totalRunsCard.locator('.stat-value').innerText()).trim(),
			10
		);

		const planted = await insertRun({
			user_id: USER_A.id,
			distance_m: 3_000,
			duration_s: 900,
			is_public: false
		});

		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(totalRunsCard.locator('.stat-value')).toHaveText(
			String(baselineTotal + 1),
			{ timeout: 10_000 }
		);

		await deleteRun(planted);
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(totalRunsCard.locator('.stat-value')).toHaveText(
			String(baselineTotal),
			{ timeout: 10_000 }
		);
	});

	test('Plans is NOT in the sidebar nav — dashboard is the entry point + Manage-plans link surfaces it', async ({
		page
	}) => {
		// Plans used to be its own top-level sidebar tab. Most users keep
		// one active plan at a time, so the dedicated tab + list page was
		// mostly redundant with the today-card already on the dashboard.
		// New shape: drop /plans from the sidebar, treat the dashboard as
		// the plan entry-point (today-card + Manage-plans link), keep the
		// /plans route around for archive / multi-plan management.
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		// Sidebar no longer carries a Plans link.
		const sidebar = page.locator('.sidebar');
		await expect(sidebar.getByRole('link', { name: /^Plans$/ })).toHaveCount(0);

		// The seeded plan surfaces via the today-card + the secondary
		// row of links (Full plan / Manage plans). Both are clickable.
		const fullPlan = page.getByRole('link', { name: /Full plan/i });
		const managePlans = page.getByRole('link', { name: /Manage plans/i });
		await expect(fullPlan).toBeVisible({ timeout: 10_000 });
		await expect(managePlans).toBeVisible();

		// "Manage plans" still routes to /plans (we kept the list page
		// for archive / multi-plan management).
		await managePlans.click();
		await expect(page).toHaveURL(/\/plans$/);
		await expect(
			page.getByRole('heading', { name: /Sydney Half 2026/ })
		).toBeVisible({ timeout: 10_000 });
	});
});
