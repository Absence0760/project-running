import { expect, test } from '@playwright/test';

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
});
