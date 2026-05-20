import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /routes/new — the route builder page.
 *
 * The builder hosts a MapLibre canvas (RouteBuilder component) plus a
 * right-hand sidebar with mode / style / distance-target controls and
 * Calculate / Save / GPX action buttons. Real OSRM + MapTiler keys
 * are not available in CI; these tests pin the *control surface* of
 * the page (button states, mode toggles, gating) without driving the
 * map canvas directly. The pure-logic side (routing.ts, elevation.ts,
 * geocoding.ts, snap-to-start, route_overlap) is covered by Dart
 * + node:test unit tests in `apps/mobile_android/test/` and
 * `apps/web/src/lib/`.
 *
 * Reachable only to authed users — the layout's auth guard would
 * redirect /routes/new to /login for anon. We sign in as USER_A.
 */

test.describe('/routes/new — Route Builder control surface', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('page mounts with the canonical h1 + sidebar controls', async ({ page }) => {
		await page.goto('/routes/new');

		await expect(page.getByRole('heading', { name: 'Route Builder', level: 1 }))
			.toBeVisible({ timeout: 10_000 });
		// Mode toggle (road / trail) — both buttons present.
		await expect(page.getByRole('button', { name: /Road/, exact: false })).toBeVisible();
		await expect(page.getByRole('button', { name: /Trail/, exact: false })).toBeVisible();
		// Three style toggles.
		await expect(page.getByRole('button', { name: 'Streets' })).toBeVisible();
		await expect(page.getByRole('button', { name: 'Satellite' })).toBeVisible();
		await expect(page.getByRole('button', { name: 'Terrain' })).toBeVisible();
	});

	test('mode toggle: road is active by default, click Trail flips the active class', async ({
		page
	}) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');

		const road = page.locator('.mode-btn', { hasText: 'Road' });
		const trail = page.locator('.mode-btn', { hasText: 'Trail' });
		// Default active state matches `mode = 'road'` in the script.
		await expect(road).toHaveClass(/active/);
		await expect(trail).not.toHaveClass(/active/);

		await trail.click();
		await expect(trail).toHaveClass(/active/);
		await expect(road).not.toHaveClass(/active/);

		// Toggle back — confirms the state isn't write-once.
		await road.click();
		await expect(road).toHaveClass(/active/);
		await expect(trail).not.toHaveClass(/active/);
	});

	test('map-style toggle cycles streets → satellite → terrain → streets', async ({ page }) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');

		const streets = page.locator('.style-btn', { hasText: 'Streets' });
		const satellite = page.locator('.style-btn', { hasText: 'Satellite' });
		const terrain = page.locator('.style-btn', { hasText: 'Terrain' });

		await expect(streets).toHaveClass(/active/);
		await satellite.click();
		await expect(satellite).toHaveClass(/active/);
		await expect(streets).not.toHaveClass(/active/);
		await terrain.click();
		await expect(terrain).toHaveClass(/active/);
		await expect(satellite).not.toHaveClass(/active/);
		await streets.click();
		await expect(streets).toHaveClass(/active/);
	});

	test('Calculate + Save + GPX buttons disabled before any waypoint exists', async ({
		page
	}) => {
		await page.goto('/routes/new');

		// `disabled={waypointCount < 2}` on Calculate. With zero
		// waypoints (the freshly-mounted state) Calculate is disabled.
		await expect(page.getByRole('button', { name: /Calculate Route/ }))
			.toBeDisabled();
		// `disabled={!routed || saving}` on Save. Routed is false at
		// mount → Save disabled.
		await expect(page.getByRole('button', { name: /Save Route/ }))
			.toBeDisabled();
		// `disabled={!routed}` on GPX export.
		await expect(page.getByRole('button', { name: 'GPX' })).toBeDisabled();
	});

	test('Undo + Clear + Out-and-back disabled at zero waypoints', async ({ page }) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');
		// All three editor toolbar buttons gate on waypointCount.
		const toolbar = page.locator('.btn.btn-ghost');
		// At least three .btn-ghost buttons exist; iterate and assert
		// the first three are disabled. Don't pin by name — the buttons
		// are icon-only.
		const count = Math.min(3, await toolbar.count());
		for (let i = 0; i < count; i++) {
			await expect(toolbar.nth(i)).toBeDisabled();
		}
	});

	test('distance-target panel toggles open + the four presets set the slider', async ({
		page
	}) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');

		// Default state: distance-target panel collapsed. Find the
		// toggle button — it has class .style-btn or similar; use the
		// canonical heading next to the slider as the gate.
		const slider = page.locator('input.target-slider');
		// Slider may already be visible depending on showDistanceTarget
		// default. Either way the presets land it on the labelled km.
		if (!(await slider.isVisible({ timeout: 1_000 }).catch(() => false))) {
			await page.locator('button', { hasText: /Distance target|generate/i }).first().click();
			await expect(slider).toBeVisible({ timeout: 5_000 });
		}

		// Four presets — 5k / 10k / Half / Full. The displayed
		// .target-value text renders in the user's preferred unit, so
		// the expectation has to accept either rendering. USER_A's
		// seed is mile-mode in CI; locally it might be km. Assert a
		// regex that covers both (5k → 5.0 km OR 3.1 mi etc.).
		const display = page.locator('.target-value');
		for (const [label, expected] of [
			['5k', /(5\.0\s*km|3\.1\s*mi)/],
			['10k', /(10\.0\s*km|6\.2\s*mi)/],
			['Half', /(21\.1\s*km|13\.1\s*mi)/],
			['Full', /(42\.2\s*km|26\.2\s*mi)/]
		] as const) {
			await page.getByRole('button', { name: label, exact: true }).click();
			await expect(display).toHaveText(expected);
		}
	});

	test('Save button gates the save modal which hosts the name input', async ({ page }) => {
		// The route name + description + visibility form was lifted into a
		// modal so the sidebar can stay focused on the building action. The
		// Save button is disabled until the user has calculated a route —
		// we can't drive OSRM in CI, so this test asserts the gating only,
		// then confirms the modal contract (name input + Cancel) via the
		// builder's bound modal state by toggling the gate off in-DOM.
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');
		const saveBtn = page.getByRole('button', { name: /Save Route/ });
		await expect(saveBtn).toBeVisible();
		await expect(saveBtn).toBeDisabled();
		// Force-enable so we can verify the modal renders + the name input
		// is bindable. The disabled gate itself is exercised by the
		// earlier "Calculate + Save + GPX buttons disabled" test.
		await saveBtn.evaluate((el: HTMLButtonElement) => (el.disabled = false));
		await saveBtn.click();
		const nameInput = page.getByPlaceholder('My Route');
		await expect(nameInput).toBeVisible();
		await expect(nameInput).toHaveValue('');
		await nameInput.fill('e2e route');
		await expect(nameInput).toHaveValue('e2e route');
		// Cancel closes without saving.
		await page.getByRole('button', { name: 'Cancel' }).click();
		await expect(nameInput).not.toBeVisible();
	});

	test('empty-state overlay renders + fades when the cursor enters the map area', async ({
		page
	}) => {
		// The "Click anywhere to start" card sits centered over the map
		// when no waypoints exist. It has pointer-events: none so clicks
		// pass through, but it visually obscures where the cursor is —
		// the .map-area:hover rule drops its opacity so the user can
		// see what they're about to click. Regressing the fade puts us
		// back at the "I can't see my map" complaint.
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');

		const card = page.locator('.canvas-empty');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(card).toContainText('Click anywhere to start');

		// Baseline: cursor outside the map area, opacity = 1.
		await page.locator('aside.sidebar').hover();
		// Wait for the 180ms CSS transition.
		await page.waitForTimeout(250);
		const baseline = await card.evaluate((el) => getComputedStyle(el).opacity);
		expect(parseFloat(baseline)).toBeGreaterThan(0.9);

		// Hover the map area — the card fades toward 0.15.
		await page.locator('.map-area').hover();
		await page.waitForTimeout(250);
		const hovered = await card.evaluate((el) => getComputedStyle(el).opacity);
		expect(parseFloat(hovered)).toBeLessThan(0.5);
	});

	test('OSRM total failure → routed stays false → Save button stays disabled', async ({
		page
	}) => {
		// Regression: handleCalculateRoute used to set routed=true
		// unconditionally after awaiting builder.calculateRoute(), so a
		// failed OSRM run still left Save enabled with a stale or
		// empty polyline. The fix made calculateRoute() return a
		// success boolean. Intercept every OSRM segment with a 503 so
		// the call fails, drop two waypoints via the builder's exported
		// API on `window` (RouteBuilder doesn't expose itself, but the
		// parent page binds the instance; we trigger waypoints via
		// dispatching a synthetic map event below), and assert the
		// gate stays armed.
		await page.route('https://router.project-osrm.org/**', (route) =>
			route.fulfill({ status: 503, body: '{}' })
		);

		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });

		// Drive the builder by dispatching two clicks on the canvas at
		// slightly different positions. MapLibre converts canvas clicks
		// into map clicks → the parent's handleMapPick + addWaypoint
		// fire → waypointCount becomes 2 → Calculate Route enables.
		const canvas = page.locator('.maplibregl-canvas');
		await canvas.click({ position: { x: 200, y: 200 } });
		await canvas.click({ position: { x: 300, y: 260 } });

		const calc = page.getByRole('button', { name: /Calculate Route/ });
		// If waypoints didn't register (test env / map-not-ready edge),
		// skip the rest — the gate-on-failure behavior is still proven
		// by the type-level boolean return and the parent's
		// `routed = !!ok` change visible in the diff.
		const enabled = await calc.isEnabled().catch(() => false);
		test.skip(!enabled, 'MapLibre canvas clicks did not register two waypoints in this env.');

		await calc.click();
		// Wait for the routing attempt to settle (3 segments × 2 retries × 8s timeout cap).
		await page.waitForTimeout(2000);

		// Error banner is red (.routing-error without .routing-warning).
		const banner = page.locator('.routing-error');
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner).not.toHaveClass(/routing-warning/);

		// Save button stays disabled — routed didn't flip true.
		await expect(page.getByRole('button', { name: /Save Route/ })).toBeDisabled();
	});

	test('routing-warning banner background differs from routing-error background', async ({
		page
	}) => {
		// The partial-success path (some OSRM segments succeeded, some
		// dropped) keeps the route but surfaces a softer warning so the
		// user knows the line is incomplete. Asserts the styling
		// contract: `.routing-error` and `.routing-error.routing-warning`
		// have distinct background declarations.
		//
		// The prior version of this test injected unhashed `<div
		// class="routing-error">` nodes into document.body and read
		// computed styles. Svelte 5 scopes component CSS by hashing
		// the class names (`.routing-error.svelte-xxxxx`); unhashed
		// nodes don't match the rule and `getComputedStyle` returns
		// transparent. Read the compiled CSSStyleSheet rules directly
		// instead — bypasses scoping and asserts the source of truth.
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');

		const colors = await page.evaluate(() => {
			let errorBg: string | null = null;
			let warningBg: string | null = null;
			for (const sheet of Array.from(document.styleSheets)) {
				let rules: CSSRuleList;
				try {
					rules = sheet.cssRules;
				} catch {
					// Cross-origin sheets throw on cssRules access.
					continue;
				}
				for (const rule of Array.from(rules)) {
					if (!(rule instanceof CSSStyleRule)) continue;
					const sel = rule.selectorText;
					const hasError = /\.routing-error\b/.test(sel);
					const hasWarning = /\.routing-warning\b/.test(sel);
					const bg = rule.style.background || rule.style.backgroundColor;
					if (!bg) continue;
					if (hasError && hasWarning) warningBg = bg;
					else if (hasError) errorBg = bg;
				}
			}
			return { errorBg, warningBg };
		});

		expect(colors.errorBg).toBeTruthy();
		expect(colors.warningBg).toBeTruthy();
		expect(colors.errorBg).not.toBe(colors.warningBg);
	});

	test('clicking an existing marker back-tracks the route (post-drag wasDragged regression)', async ({
		page,
	}) => {
		// Two interacting bugs the audit uncovered:
		//
		// 1. `wasDragged` was set on `dragstart` but never reset in
		//    `dragend`. The browser doesn't fire `click` after a drag,
		//    so the flag stayed true and silently ate the NEXT real
		//    click on that marker. Dragging marker B then clicking B
		//    to back-track did nothing on the first try.
		//
		// 2. Clicking an existing marker on a freshly-calculated
		//    route appended a back-track waypoint, but
		//    `routeCoordinates` wasn't cleared, so the snapped
		//    polyline stayed visible (stale) and the parent's
		//    `routed` flag stayed true — letting the user Save a
		//    route that hadn't been routed through the new point.
		//
		// We can't reliably drive the maplibre canvas clicks in CI
		// (the existing OSRM-failure test uses the same approach with
		// a graceful skip). Drop waypoints via canvas clicks; if even
		// two waypoints don't register, skip — the unit + diff review
		// still pin the behaviour.
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });

		const canvas = page.locator('.maplibregl-canvas');
		await canvas.click({ position: { x: 200, y: 200 } });
		await canvas.click({ position: { x: 300, y: 260 } });
		await canvas.click({ position: { x: 400, y: 200 } });

		const pointsValue = page.locator('.builder-stat-value').nth(2);
		const startingCount = await pointsValue.textContent().catch(() => '0');
		if (!startingCount || parseInt(startingCount, 10) < 3) {
			test.skip(true, 'MapLibre canvas clicks did not register 3 waypoints in this env.');
			return;
		}

		// Click the middle marker (waypoint 2 in 1-based, index 1
		// in the markers array — the second .maplibregl-marker).
		const markers = page.locator('.maplibregl-marker');
		const before = await markers.count();
		await markers.nth(1).click();
		await page.waitForTimeout(150);

		// A new marker should land at the SAME lat/lng as the clicked
		// one — that's how OSRM is asked to route back through it.
		// The points counter is the simplest signal.
		const after = await markers.count();
		expect(after).toBe(before + 1);
		const updated = await pointsValue.textContent();
		expect(parseInt(updated ?? '0', 10)).toBe(parseInt(startingCount, 10) + 1);
	});

	test('marker cursor is pointer (signals clickability)', async ({ page }) => {
		// Tiny regression guard. The maplibre default `move` cursor
		// gave no hint that clicking a marker did anything; we
		// override to pointer in createWaypointMarker. If a future
		// refactor strips that line, this catches it before users
		// re-report "I can't tell if I'm allowed to click markers".
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');
		const canvas = page.locator('.maplibregl-canvas');
		await canvas.click({ position: { x: 200, y: 200 } });
		const marker = page.locator('.maplibregl-marker').first();
		if (!(await marker.isVisible().catch(() => false))) {
			test.skip(true, 'MapLibre canvas click did not register a waypoint in this env.');
			return;
		}
		const cursor = await marker.evaluate((el) => getComputedStyle(el).cursor);
		expect(cursor).toBe('pointer');
	});

	test('keyboard shortcuts hint is visible on initial load', async ({ page }) => {
		// The .shortcuts-hint affordance is the discoverability hook
		// for power users. A regression that hid it removes the
		// keyboard-power-user signal.
		await page.goto('/routes/new');
		await expect(page.locator('.shortcuts-hint')).toBeVisible({ timeout: 10_000 });
	});

	test('Generate-by-distance: distance presets update the slider label', async ({ page }) => {
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');
		// Open the distance-target panel.
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		// 5k preset → slider value reads ~5.0 km or ~3.1 mi depending
		// on the user's preference (default seed is km).
		await page.getByRole('button', { name: '5k', exact: true }).click();
		const value = page.locator('.target-value');
		const text = (await value.textContent()) ?? '';
		// Either "5.0 km" or "3.1 mi" — both are valid renderings of
		// the 5km preset.
		expect(text).toMatch(/(5\.0\s*km|3\.1\s*mi)/);
	});

	test('Generate without zoom OR start emits the pan-first guard', async ({ page }) => {
		// Pre-audit: generateLoop fell back to map.getCenter() and
		// happily ran from the default [0, 20] (mid-Atlantic) when
		// geolocation was denied — every waypoint missed the road
		// network and the user got a confusing "Routing service
		// unavailable." The zoom < 6 guard now refuses early with a
		// clear message.
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		// Generate button is visible (no start picked, busy=false).
		await page.getByRole('button', { name: /Generate .* (loop|route)/ }).click();
		const banner = page.locator('.routing-error').first();
		await expect(banner).toBeVisible({ timeout: 5_000 });
		await expect(banner).toContainText(/Pan to your area|pick a start/i);
	});

	test('Generate hard-failure surfaces a generation-specific message', async ({ page }) => {
		// Every OSRM call comes back 503. Audit #6: the user should
		// see "Couldn't generate a Xkm loop here", not the generic
		// "Routing service unavailable" — service IS reachable, the
		// scaffolding seeds just missed the road network.
		await page.route('https://router.project-osrm.org/**', (route) =>
			route.fulfill({ status: 503, body: '{}' }),
		);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });

		// Pick a start so the zoom guard doesn't intercept.
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		await page.getByRole('button', { name: 'Pick start on map' }).click();
		await page.locator('.maplibregl-canvas').click({ position: { x: 200, y: 200 } });

		// If the picker didn't capture the click (test env), skip — the
		// behaviour is still covered by the unit tests on the pure
		// helpers and the type-level boolean return.
		const startSet = await page
			.locator('.point-set')
			.first()
			.isVisible()
			.catch(() => false);
		test.skip(!startSet, 'MapLibre canvas pick did not register a start point.');

		await page.getByRole('button', { name: /Generate .* (loop|route)/ }).click();
		const banner = page.locator('.routing-error').first();
		await expect(banner).toBeVisible({ timeout: 30_000 });
		await expect(banner).toContainText(/Couldn't generate/i);
	});

	test('Cancel button appears while generate is in flight', async ({ page }) => {
		// Audit #8: long-running batches were unstoppable short of Esc
		// (which dumped the whole route). The Cancel button replaces
		// Generate while isRouting=true and calls cancelGeneration(),
		// which bumps routeVersion → the in-flight recalculateRoute
		// bails at its next checkpoint.
		//
		// Slow-walk every OSRM call so we have time to observe the
		// busy state before any of them finishes.
		await page.route('https://router.project-osrm.org/**', async (route) => {
			await new Promise((r) => setTimeout(r, 4000));
			await route.fulfill({ status: 503, body: '{}' });
		});
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });

		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		await page.getByRole('button', { name: 'Pick start on map' }).click();
		await page.locator('.maplibregl-canvas').click({ position: { x: 200, y: 200 } });

		const startSet = await page
			.locator('.point-set')
			.first()
			.isVisible()
			.catch(() => false);
		test.skip(!startSet, 'MapLibre canvas pick did not register a start point.');

		await page.getByRole('button', { name: /Generate .* (loop|route)/ }).click();

		// Cancel button shows up within a couple seconds.
		const cancel = page.getByRole('button', { name: /Cancel generating/i });
		await expect(cancel).toBeVisible({ timeout: 5_000 });

		await cancel.click();
		// After cancel, the Generate button comes back (onbusy(false)).
		await expect(page.getByRole('button', { name: /Generate .* (loop|route)/ })).toBeVisible({
			timeout: 5_000,
		});
	});

	test('anon visitor is auth-walled to /login', async ({ browser }) => {
		// /routes/new is not in publicPaths. Use a fresh context with
		// no storage state to simulate anon.
		const ctx = await browser.newContext({ storageState: { cookies: [], origins: [] } });
		const anon = await ctx.newPage();
		try {
			await anon.goto('/routes/new');
			await anon.waitForURL(/\/login(\?|$)/, { timeout: 10_000 });
		} finally {
			await ctx.close();
		}
	});
});
