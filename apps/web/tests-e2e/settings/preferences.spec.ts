import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/preferences — units / pace format / map style / theme /
 * default activity / privacy zones / coach personality, etc.
 *
 * The theme toggle is the load-bearing test today because it pins
 * BOTH the localStorage round-trip AND the html[data-theme] attribute
 * the layout reads on every mount. Future rounds: distance unit
 * propagates to /runs format, privacy zone picker round-trip, voice
 * feedback toggle persists.
 */

test.describe('/settings/preferences', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('distance unit toggle: km → mi propagates to /runs after save', async ({
		page
	}) => {
		// Distance unit is stored in user_profiles.preferred_unit (and
		// mirrored to the user_settings prefs bag for cross-device
		// sync). The reactive `unit.value` signal in units.svelte.ts
		// drives `formatDistance(metres)` everywhere. Save → reload
		// /runs → assert distances render with " mi" suffix instead
		// of " km". Catches regressions in the auth store's setUnit
		// fan-out OR the Save handler dropping preferredUnit.
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');

		// Switch to Miles.
		await page.getByRole('button', { name: 'Miles', exact: true }).click();
		await page.getByRole('button', { name: /Save Preferences/ }).click();
		await expect(
			page.getByRole('button', { name: /Saved!/ })
		).toBeVisible({ timeout: 5_000 });

		// Visit /runs; distances on the cards should now read in mi.
		await page.goto('/runs');
		await page.getByLabel('Date range').selectOption('all');
		const firstStat = page.locator('.run-card .run-stat-value').first();
		await expect(firstStat).toBeVisible({ timeout: 10_000 });
		await expect(firstStat).toContainText('mi');

		// Restore to km so subsequent tests render against the default.
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');
		await page.getByRole('button', { name: 'Kilometres', exact: true }).click();
		await page.getByRole('button', { name: /Save Preferences/ }).click();
		await expect(
			page.getByRole('button', { name: /Saved!/ })
		).toBeVisible({ timeout: 5_000 });
	});

	test('theme toggle: Dark applies html[data-theme] + survives reload', async ({
		page
	}) => {
		// `applyTheme` writes `html.dataset.theme = <value>` AND
		// localStorage; the layout's onMount calls `initTheme()` which
		// reads localStorage. The combination should be idempotent
		// across navigations and reloads — a regression here means
		// "user picks dark, comes back tomorrow, sees light" which is
		// a subtle UX bug you'd never catch without an integration
		// test.
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');

		await page.getByRole('button', { name: 'Dark', exact: true }).click();
		await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');

		// Reload to confirm initTheme on a fresh load resurrects it.
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');

		// Restore to Auto so subsequent tests don't render against a
		// stale dark-mode root attribute. (Auto + no media-query
		// preference still puts data-theme=auto on the root.)
		await page.getByRole('button', { name: 'Auto', exact: true }).click();
		await expect(page.locator('html')).toHaveAttribute('data-theme', 'auto');
	});
});
