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

		// Switch to Miles.
		await page.getByRole('button', { name: 'Miles', exact: true }).click();
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });

		// Visit /runs; distances on the cards should now read in mi.
		await page.goto('/runs');
		await page.getByLabel('Date range').selectOption('all');
		const firstStat = page.locator('.run-card .run-stat-value').first();
		await expect(firstStat).toBeVisible({ timeout: 10_000 });
		await expect(firstStat).toContainText('mi');

		// Restore to km so subsequent tests render against the default.
		await page.goto('/settings/preferences');
		await page.getByRole('button', { name: 'Kilometres', exact: true }).click();
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
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

		await page.getByRole('button', { name: 'Miles', exact: true }).click();
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });

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
		await page.getByRole('link', { name: /Richmond Half 2026/ }).click();
		const firstWeekVolume = page.locator('.week-volume').first();
		await expect(firstWeekVolume).toContainText('mi', { timeout: 10_000 });

		// Restore to km so subsequent tests render against the default.
		await page.goto('/settings/preferences');
		await page.getByRole('button', { name: 'Kilometres', exact: true }).click();
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
	});

	test('Distance unit km → mi propagates to /routes/new builder sidebar + distance-target slider', async ({
		page,
	}) => {
		// Route-builder regression test. The sidebar's stat row and the
		// distance-target slider both used to hardcode " km" / " /km"
		// in the template — flipping the preference made every other
		// surface in the app re-render except this one. The audit
		// caught it; this test pins the new unit-aware bindings so it
		// can't silently regress.
		await page.goto('/settings/preferences');
		await page.getByRole('button', { name: 'Miles', exact: true }).click();
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });

		try {
			await page.goto('/routes/new');
			await expect(
				page.getByRole('heading', { level: 1, name: 'Route Builder' }),
			).toBeVisible({ timeout: 10_000 });

			// ── Sidebar stat label ──
			// The "0.00 km" / "0.00 mi" pair lives in .builder-stat;
			// with zero waypoints the value is 0.00 and the unit label
			// is what we care about. Distance stat is the first one in
			// the row.
			const distLabel = page.locator('.builder-stat .builder-stat-label').first();
			await expect(distLabel).toHaveText('mi', { timeout: 10_000 });

			// ── Distance-target slider label ──
			// The "Generate a route by distance" panel is collapsed by
			// default; open it and assert the slider value reads mi.
			await page
				.getByRole('button', { name: /Generate a route by distance/ })
				.click();
			const targetValue = page.locator('.target-value');
			await expect(targetValue).toContainText('mi', { timeout: 5_000 });
			await expect(targetValue).not.toContainText('km');

			// ── Generate-button label ──
			const generateBtn = page.getByRole('button', { name: /Generate .* (?:route|loop)/ });
			await expect(generateBtn).toContainText('mi');
			await expect(generateBtn).not.toContainText(/\bkm\b/);
		} finally {
			// Restore to km so subsequent tests render against the default.
			await page.goto('/settings/preferences');
			await page.getByRole('button', { name: 'Kilometres', exact: true }).click();
			await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
		}
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
		// Needed: inputValue() below snapshots — no auto-retry — so a
		// pre-fetch read would capture the default rather than the
		// user's saved selection.
		await page.waitForLoadState('networkidle');

		const sel = page
			.locator('label', { has: page.getByText('Pace Format', { exact: true }) })
			.locator('select');
		const before = await sel.inputValue();
		await sel.selectOption('min_per_mi');
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });

		await page.reload();
		await expect(sel).toHaveValue('min_per_mi');

		// Restore.
		await sel.selectOption(before);
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
	});

	test('Email notifications <select> save round-trip persists across reload', async ({
		page
	}) => {
		// email_notifications gates the Go worker's notification_email
		// channel (all | important | off, default important). The handler
		// reads user_settings.prefs.email_notifications server-side, so the
		// load-bearing assertion is that the picker actually writes the bag
		// and the value survives a reload — a regression that dropped the
		// key from the autoSave payload would silently leave every user on
		// the default forever.
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');

		const sel = page
			.locator('label', { has: page.getByText('Email notifications', { exact: true }) })
			.locator('select');
		// Default when the key is absent.
		await expect(sel).toHaveValue('important');
		const before = await sel.inputValue();

		await sel.selectOption('all');
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });

		await page.reload();
		await expect(sel).toHaveValue('all');

		// The full kill-switch value also round-trips.
		await sel.selectOption('off');
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
		await page.reload();
		await expect(sel).toHaveValue('off');

		// Restore so later specs see the default.
		await sel.selectOption(before);
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
	});

	test('Weekly digest opt-in toggle save round-trip persists across reload', async ({
		page
	}) => {
		// email_weekly_digest is OPT-IN consent for the weekly engagement digest
		// (bulk/promotional mail), stored as 'on'|'off' (default 'off'), a
		// deliberately separate key from the transactional email_notifications.
		// The Go worker's weekly_digest handler reads it server-side, so the
		// load-bearing assertion is that the toggle writes the bag with the
		// 'on'/'off' string and survives a reload — a regression that dropped
		// the key from autoSave would leave every user permanently opted out.
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');

		const toggle = page.getByTestId('email-weekly-digest');
		// Default when the key is absent: off (unchecked).
		await expect(toggle).not.toBeChecked();

		// Opt in. The bag write must be the literal 'on' string.
		const optInPatch = page.waitForRequest(
			(req) =>
				req.method() === 'PATCH' &&
				req.url().includes('/rest/v1/user_settings') &&
				(req.postData() ?? '').includes('"email_weekly_digest":"on"'),
			{ timeout: 8_000 }
		);
		await toggle.check();
		await optInPatch; // throws if the opt-in write never fires
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });

		await page.reload();
		await expect(page.getByTestId('email-weekly-digest')).toBeChecked();

		// Opt back out so later specs see the default; the write is 'off'.
		const optOutToggle = page.getByTestId('email-weekly-digest');
		await optOutToggle.uncheck();
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
		await page.reload();
		await expect(page.getByTestId('email-weekly-digest')).not.toBeChecked();
	});

	test('changing language writes locale to the settings bag (email localization)', async ({
		page
	}) => {
		// The UI locale stays client-side; separately the applied tag is
		// mirrored into user_settings.prefs.locale so the worker can localize
		// email (decisions §120). Assert the write actually fires by catching
		// the user_settings PATCH — a regression dropping it would silently
		// leave every user's email in English.
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');

		const sel = page.getByTestId('language-select');
		const before = await sel.inputValue();

		const patch = page.waitForRequest(
			(req) =>
				req.method() === 'PATCH' &&
				req.url().includes('/rest/v1/user_settings') &&
				(req.postData() ?? '').includes('"locale":"de"'),
			{ timeout: 8_000 }
		);
		await sel.selectOption('de');
		await patch; // throws if the locale write never fires

		// Restore (writes the bag back to the prior locale).
		await sel.selectOption(before);
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
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

		// Pick Satellite via the labelled <select>.
		const sel = page
			.locator('label', { has: page.getByText('Map Style', { exact: true }) })
			.locator('select');
		await expect(sel).toBeVisible({ timeout: 10_000 });
		const before = await sel.inputValue();
		await sel.selectOption('satellite');
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });

		await page.reload();
		await expect(sel).toHaveValue('satellite');

		// Restore.
		await sel.selectOption(before);
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
	});

	test('Resting + Max HR inputs render and round-trip through save', async ({
		page
	}) => {
		// resting_hr_bpm + max_hr_bpm are universal prefs mobile already
		// exposes (settings_preferences_screen.dart). Web is the canonical
		// surface so it must offer them too — a beta-blocked runner whose
		// formula HR-max is wrong has no other way to set a measured max.
		// Pin: both inputs render under the HR section, persist through the
		// same Save handler as every other pref, and survive reload. The
		// clear-to-null path matters (an empty input must NOT write 0).
		await page.goto('/settings/preferences');
		await page.waitForLoadState('networkidle');

		const resting = page
			.locator('label', { has: page.getByText('Resting HR (bpm)', { exact: true }) })
			.locator('input');
		const max = page
			.locator('label', { has: page.getByText('Max HR (bpm)', { exact: true }) })
			.locator('input');
		await expect(resting).toBeVisible({ timeout: 10_000 });
		await expect(max).toBeVisible();

		// Number inputs auto-save on blur — fill, then blur the last field so
		// its on-blur write fires before we wait for the cue.
		await resting.fill('48');
		await max.fill('182');
		await max.blur();
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });

		await page.reload();
		await expect(resting).toHaveValue('48');
		await expect(max).toHaveValue('182');

		// Clearing both must round-trip to unset (null), not 0.
		await resting.fill('');
		await max.fill('');
		await max.blur();
		await expect(page.getByTestId('save-status')).toContainText('Saved', { timeout: 8_000 });
		await page.reload();
		await expect(resting).toHaveValue('');
		await expect(max).toHaveValue('');
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

		await page.getByRole('button', { name: 'Dark', exact: true }).click();
		await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');

		// Reload to confirm initTheme on a fresh load resurrects it.
		await page.reload();
		await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');

		// Restore to Auto so subsequent tests don't render against a
		// stale dark-mode root attribute. (Auto + no media-query
		// preference still puts data-theme=auto on the root.)
		await page.getByRole('button', { name: 'Auto', exact: true }).click();
		await expect(page.locator('html')).toHaveAttribute('data-theme', 'auto');
	});

	test('auto-save shows a transient "Saved" cue that clears after a moment', async ({
		page
	}) => {
		// There is no global Save button — changing a control auto-saves and
		// the inline status cue flips to "Saved", then clears (the savedTimer
		// rearm). A regression that never showed the cue, or left it stuck on
		// "Saved", surfaces here. Errors still toast; the happy path is silent
		// beyond this cue.
		await page.goto('/settings/preferences');
		const status = page.getByTestId('save-status');

		await page.getByRole('button', { name: 'Miles', exact: true }).click();
		await expect(status).toContainText('Saved', { timeout: 8_000 });
		// The cue clears itself (rearm) so it isn't permanently stuck.
		await expect(status).not.toContainText('Saved', { timeout: 5_000 });

		// Restore to km so later tests render against the default.
		await page.getByRole('button', { name: 'Kilometres', exact: true }).click();
		await expect(status).toContainText('Saved', { timeout: 8_000 });
	});

	test('demographics are NOT auto-saved — explicit consent-gated Save only', async ({
		page
	}) => {
		// Unlike the rest of the page, gender/DOB (GDPR Art 9 special-category
		// data) persist only via the explicit "Save demographics" button — a
		// change must NOT trigger the auto-save path. This pins the deliberate
		// asymmetry. All interactions here are in-memory (nothing is saved, so
		// USER_A's stored consent + profile are untouched).
		await page.goto('/settings/preferences');
		await expect(page.getByTestId('save-demographics')).toBeVisible();

		const consent = page
			.locator('label.consent-checkbox', { hasText: 'date of birth' })
			.locator('input[type="checkbox"]');
		const gender = page
			.locator('select')
			.filter({ has: page.getByRole('option', { name: 'Prefer not to say' }) });

		// Gender is gated on consent (in-memory toggle, no write).
		const startedChecked = await consent.isChecked();
		if (startedChecked) await consent.uncheck();
		await expect(gender).toBeDisabled();
		await consent.check();
		await expect(gender).toBeEnabled();

		// Changing gender must NOT fire the auto-save cue (demographics are
		// explicit-save only).
		await gender.selectOption('nonbinary');
		await expect(page.getByTestId('save-status')).not.toContainText('Saved');

		// Leave consent unticked + unsaved so nothing persists for USER_A.
		await consent.uncheck();
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

	test('activity-level labels describe a non-exercise baseline (dynamic-TDEE double-count guard)', async ({
		page,
	}) => {
		// Regression guard (decisions §134): the dynamic-TDEE "base + exercise"
		// model treats nutrition_activity_level as a NON-exercise baseline and
		// adds logged workout calories on top. The select renders from the
		// `prefs.activity_*` i18n keys (not ACTIVITY_LEVELS[].label), so those
		// strings must NOT describe weekly exercise frequency — that wording
		// guides a runner into the exact double-count this avoids.
		await page.goto('/settings/preferences');
		const optionText = (
			await page.getByTestId('activity-level').locator('option').allInnerTexts()
		)
			.join(' ')
			.toLowerCase();
		expect(optionText).not.toMatch(/\/\s*week|days\/week|twice a day|little exercise/);
		// The hint discloses that logged workouts are added automatically.
		await expect(
			page.locator('.section-hint', { hasText: /added to your goal automatically/i })
		).toBeVisible();
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
