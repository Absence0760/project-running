import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Navigation + layout-level state that spans every authenticated page.
 *
 * The sidebar collapsed flag, theme attribute, and sidebar-active
 * highlighting all live in the root layout — a regression in any of
 * them breaks state across every authed route. Tests here exercise
 * the layout shell from /dashboard but the assertions apply equally
 * to every page underneath.
 *
 * Future depth: sidebar nav active highlights match current pathname,
 * sidebar nav stays collapsed across route changes (not just reload),
 * notification-bell focus refresh on `window.focus`.
 */

test.describe('sidebar collapse', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('toggle collapses, reload preserves, expand restores', async ({
		page
	}) => {
		// Layout writes the boolean to localStorage as `sidebar_collapsed`
		// = '1' / '0'. Mounts read it on first paint; the class
		// .sidebar.collapsed drives the visual narrow state. The
		// regression risk: the writer happens-before the reader on
		// first render OR the localStorage key drifts between writer
		// and reader (e.g. someone renames it on one side only).
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		const sidebar = page.locator('nav.sidebar');
		await expect(sidebar).not.toHaveClass(/collapsed/);

		// The toggle button has aria-label "Collapse sidebar" / "Expand
		// sidebar" depending on state. Use the role+name pair so the
		// test reads as the user does.
		await page.getByRole('button', { name: 'Collapse sidebar' }).click();
		await expect(sidebar).toHaveClass(/collapsed/);

		// Reload — collapsed state must hold.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.locator('nav.sidebar')).toHaveClass(/collapsed/);

		// Restore so subsequent tests don't render against a collapsed
		// sidebar (selectors that assume the expanded layout would
		// silently break).
		await page.getByRole('button', { name: 'Expand sidebar' }).click();
		await expect(page.locator('nav.sidebar')).not.toHaveClass(/collapsed/);
	});

	test('sidebar nav highlights the active route with the .active class', async ({
		page
	}) => {
		// The layout marks the active sidebar link with `class="active"`.
		// Pin one route — /runs — so a regression that dropped the
		// active wiring (e.g. a refactor that swapped the matcher) is
		// caught.
		await page.goto('/runs');
		await page.waitForLoadState('networkidle');

		const navHistory = page.locator('nav.sidebar a', { hasText: 'History' });
		await expect(navHistory).toBeVisible();
		await expect(navHistory).toHaveClass(/active/);

		// Other nav items do NOT carry the active class.
		const navDashboard = page.locator('nav.sidebar a', { hasText: 'Dashboard' });
		await expect(navDashboard).not.toHaveClass(/active/);
	});
});
