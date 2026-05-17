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

	test('Pace Format <select> save round-trip persists across reload', async ({
		page
	}) => {
		// pace_format is a separate prefs key (currently used by chart
		// axes + workout/coach surfaces). The Save handler stitches it
		// into the same upsert as theme/unit/map_style; pin the round-
		// trip here so a regression that dropped the field from the
		// payload would surface as the dropdown reverting on reload.
		// The propagation to formatPace currently goes through
		// preferred_unit (not pace_format) — see units.svelte.ts.
		// Pinning the persistence is the load-bearing assertion.
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');

		const sel = page
			.locator('label', { has: page.getByText('Pace Format', { exact: true }) })
			.locator('select');
		const before = await sel.inputValue();
		await sel.selectOption('min_per_mi');
		await page.getByRole('button', { name: /Save Preferences/ }).click();
		await expect(page.getByRole('button', { name: /Saved!/ })).toBeVisible({
			timeout: 5_000
		});

		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(sel).toHaveValue('min_per_mi');

		// Restore.
		await sel.selectOption(before);
		await page.getByRole('button', { name: /Save Preferences/ }).click();
		await expect(page.getByRole('button', { name: /Saved!/ })).toBeVisible({
			timeout: 5_000
		});
	});

	test('map style picker — selecting Satellite saves and survives reload', async ({
		page
	}) => {
		// `map_style` is stored in user_settings.prefs.map_style and read
		// by map-style.svelte.ts. The Settings select is a <select> with
		// 3 options. Pin Save → reload → option still selected. A
		// regression that dropped map_style from the saved prefs blob
		// (it shares a single Save handler with theme + unit) would
		// surface here.
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');

		// Pick Satellite via the labelled <select>.
		const sel = page
			.locator('label', { has: page.getByText('Map Style', { exact: true }) })
			.locator('select');
		await expect(sel).toBeVisible({ timeout: 10_000 });
		const before = await sel.inputValue();
		await sel.selectOption('satellite');
		await page.getByRole('button', { name: /Save Preferences/ }).click();
		await expect(
			page.getByRole('button', { name: /Saved!/ })
		).toBeVisible({ timeout: 5_000 });

		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(sel).toHaveValue('satellite');

		// Restore.
		await sel.selectOption(before);
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

	test('Save flow emits the success toast + the button re-arms after 2s', async ({
		page
	}) => {
		// The Save handler emits a `showToast('Preferences saved.', 'success')`
		// after `updateUniversal` resolves AND flips the button label to
		// "Saved!" for 2s before reverting to "Save Preferences". Pin both —
		// a regression that swallowed the toast (e.g. removing the
		// ToastContainer mount, or throwing inside the upsert) would leave
		// users with no feedback that the save took.
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');

		await page.getByRole('button', { name: /Save Preferences/ }).click();

		const toast = page.locator('.toast.toast-success', {
			hasText: 'Preferences saved.'
		});
		await expect(toast).toBeVisible({ timeout: 5_000 });

		// Button label cycle: Saving... → Saved! → Save Preferences. The
		// "Saved!" state lasts ~2s; assert the rearm so a regression that
		// stuck the button on "Saved!" (broken setTimeout) surfaces here.
		await expect(
			page.getByRole('button', { name: /Saved!/ })
		).toBeVisible({ timeout: 5_000 });
		await expect(
			page.getByRole('button', { name: 'Save Preferences', exact: true })
		).toBeVisible({ timeout: 5_000 });
	});

	test('skeleton renders during initial load + is replaced by real content', async ({
		page
	}) => {
		// The polished-this-session page paints a content-shape skeleton
		// (four card placeholders, each with a grid of field placeholders)
		// while `loading` is true. Once the settings fetch resolves the
		// skeleton is replaced by the real form. Pin both: a regression
		// that dropped the skeleton would show a blank page during the
		// fetch, and a regression that left `loading` stuck would leave
		// the skeleton up forever.
		//
		// On a fast local stack the real fetch resolves in <100ms which
		// races with Playwright's first assertion. Delay the user_settings
		// PostgREST call by 750ms so the skeleton is observable.
		await page.route('**/rest/v1/user_settings*', async (route) => {
			await new Promise((r) => setTimeout(r, 750));
			await route.continue();
		});

		await page.goto('/settings/preferences');

		await expect(page.locator('.skel-card').first()).toBeVisible({
			timeout: 5_000
		});

		// Then the real form replaces the skeletons.
		await expect(
			page.getByRole('heading', { name: 'Units & Display' })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.skel-card')).toHaveCount(0);
	});
});

test.describe('/settings/preferences — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor is auth-walled to /login with return_to', async ({
		page,
		context
	}) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		await page.goto('/settings/preferences');
		await page.waitForURL(/\/login(\?|$)/, { timeout: 10_000 });
		// return_to round-trip: the layout guard preserves the original
		// destination so post-sign-in the user lands back on the prefs
		// page (not the default dashboard).
		expect(page.url()).toMatch(/return_to=%2Fsettings%2Fpreferences/);
	});
});
