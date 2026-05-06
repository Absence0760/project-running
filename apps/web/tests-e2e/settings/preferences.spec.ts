import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
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

	test('Distance unit km → mi propagates to dashboard stat cards + run detail + plan week grid + pace suffix', async ({
		page
	}) => {
		// The companion test above pins the /runs (list) propagation
		// path; this one pins the OTHER surfaces that re-render off the
		// shared `unit.value` signal. Distance / pace are the two
		// formatters in `units.svelte.ts`, used through ~6 pages —
		// regressions historically came from a *page* forgetting to
		// import the formatter (hardcoding " km" in the template) OR
		// from `auth.setUnit(...)` not running on a fresh page mount.
		// Touching multiple surfaces in one test catches both classes.
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');

		await page.getByRole('button', { name: 'Miles', exact: true }).click();
		await page.getByRole('button', { name: /Save Preferences/ }).click();
		await expect(
			page.getByRole('button', { name: /Saved!/ })
		).toBeVisible({ timeout: 5_000 });

		// ── /dashboard Recent Runs (formatDistance per-row) ──
		// Stat cards are an unreliable target: "Longest Run" pre-fetch
		// renders as 0, which formats as "0 yd" in mi mode — substring-
		// matches "mi" → false-pass / false-fail depending on race. The
		// .run-row distance is rendered from a non-empty `filteredRuns`
		// so its presence already proves the fetch completed.
		await page.goto('/dashboard');
		const recentRunDistance = page
			.locator('.run-row .run-distance')
			.first();
		await expect(recentRunDistance).toBeVisible({ timeout: 10_000 });
		await expect(recentRunDistance).toContainText('mi');
		await expect(recentRunDistance).not.toContainText(/\bkm\b/);

		// ── /runs/[id] key-stats (Distance + Avg Pace) ──
		// formatDistance + formatPace both flow off `unit.value`. Avg
		// Pace also pins the "/mi" suffix in formatPace.
		await page.goto(`/runs/${RUNNER_PUBLIC_RUN_ID}`);
		const distanceStat = page
			.locator('.key-stat', { hasText: 'Distance' })
			.locator('.key-stat-value');
		await expect(distanceStat).toContainText('mi', { timeout: 10_000 });
		const paceStat = page
			.locator('.key-stat', { hasText: 'Avg Pace' })
			.locator('.key-stat-value');
		// formatPace appends "/mi" — anchored to avoid matching
		// "5:00 /km" if the suffix accidentally falls back.
		await expect(paceStat).toContainText('/mi');
		await expect(paceStat).not.toContainText('/km');

		// ── /plans/[id] week-volume grid (fmtKm) ──
		// fmtKm is a separate formatter (used by training-plan
		// surfaces); pinning it here proves both formatters track the
		// same signal.
		await page.goto('/plans');
		await page.getByRole('link', { name: /Sydney Half 2026/ }).click();
		const firstWeekVolume = page.locator('.week-volume').first();
		await expect(firstWeekVolume).toContainText('mi', { timeout: 10_000 });

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
