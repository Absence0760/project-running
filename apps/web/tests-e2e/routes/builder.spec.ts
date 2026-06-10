import { expect, test, type Page } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Dev-only test hooks (see /routes/new/+page.svelte). The page exposes
 * the RouteBuilder component instance + a small page-level state
 * setter on `window` when import.meta.env.DEV is true (i.e. under
 * `vite dev`, which is what playwright.config.ts boots). Specs use
 * these instead of synthetic canvas clicks — MapLibre's WebGL pointer
 * pipeline doesn't deliver clicks reliably in headless chromium.
 */
type TestPoint = { lat: number; lng: number };

async function waitForRouteBuilder(page: Page): Promise<void> {
	await page.waitForFunction(
		() =>
			typeof (window as unknown as { __routeBuilder?: unknown }).__routeBuilder !==
			'undefined',
		undefined,
		{ timeout: 10_000 }
	);
}

/**
 * True when a local Protomaps tileserver override is configured for the
 * dev server (PUBLIC_TILE_STYLE_URL set). In that mode the style
 * switcher collapses to Streets-only (decisions §68), so the
 * Satellite / Terrain assertions don't apply. Read off the DEV-only
 * page hook — call waitForRouteBuilder first so the hook is live.
 */
async function tileOverrideActive(page: Page): Promise<boolean> {
	return page.evaluate(() =>
		Boolean(
			(
				window as unknown as {
					__routeBuilderPage?: { tileOverrideActive?: boolean };
				}
			).__routeBuilderPage?.tileOverrideActive
		)
	);
}

async function addWaypoints(page: Page, points: TestPoint[]): Promise<void> {
	await page.evaluate((pts) => {
		const b = (window as unknown as {
			__routeBuilder: { addWaypoint: (p: { lat: number; lng: number }) => void };
		}).__routeBuilder;
		for (const p of pts) b.addWaypoint(p);
	}, points);
}

/**
 * Drop N waypoints arranged in a small triangle around the map's
 * current center. The marker DOM elements need to be on-screen for
 * positional `.click()` to work; pinning absolute lat/lng to a fixed
 * location (e.g. Melbourne) can land the markers outside the default
 * map viewport.
 */
async function addWaypointsNearMapCenter(
	page: Page,
	offsets: Array<{ dLat: number; dLng: number }>
): Promise<void> {
	const center = await page.evaluate(() => {
		const b = (window as unknown as {
			__routeBuilder: { getMapCenter: () => { lat: number; lng: number } | null };
		}).__routeBuilder;
		return b.getMapCenter();
	});
	if (!center) throw new Error('Map center not available');
	const points = offsets.map((o) => ({
		lat: center.lat + o.dLat,
		lng: center.lng + o.dLng
	}));
	await addWaypoints(page, points);
}

async function setStartPoint(page: Page, point: TestPoint): Promise<void> {
	await page.evaluate((p) => {
		const pg = (window as unknown as {
			__routeBuilderPage: { setStartPoint: (p: { lat: number; lng: number } | null) => void };
		}).__routeBuilderPage;
		pg.setStartPoint(p);
	}, point);
}

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
		await waitForRouteBuilder(page);

		await expect(page.getByRole('heading', { name: 'Route Builder', level: 1 }))
			.toBeVisible({ timeout: 10_000 });
		// Mode toggle (road / trail) — both buttons present.
		await expect(page.getByRole('button', { name: /Road/, exact: false })).toBeVisible();
		await expect(page.getByRole('button', { name: /Trail/, exact: false })).toBeVisible();
		// Streets is always present; Satellite + Terrain collapse to
		// Streets-only under a local tileserver override (decisions §68),
		// so only assert them when the override is off.
		await expect(page.getByRole('button', { name: 'Streets' })).toBeVisible();
		if (!(await tileOverrideActive(page))) {
			await expect(page.getByRole('button', { name: 'Satellite' })).toBeVisible();
			await expect(page.getByRole('button', { name: 'Terrain' })).toBeVisible();
		}
	});

	test('mode toggle: road is active by default, click Trail flips the active class', async ({
		page
	}) => {
		await page.goto('/routes/new');

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
		await waitForRouteBuilder(page);
		// The 3-way switcher only exists without a tileserver override
		// (decisions §68); skip when one is configured for the dev server.
		test.skip(
			await tileOverrideActive(page),
			'tileserver override collapses the style switcher to Streets-only'
		);

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

	test('Save + GPX buttons disabled before any waypoint exists', async ({
		page
	}) => {
		await page.goto('/routes/new');

		// Routing is now automatic (no Calculate button). With zero
		// waypoints `routed` is false → both gates stay armed.
		// `disabled={!routed || saving}` on Save.
		await expect(page.getByRole('button', { name: /Save Route/ }))
			.toBeDisabled();
		// `disabled={!routed}` on GPX export.
		await expect(page.getByRole('button', { name: 'GPX' })).toBeDisabled();
	});

	test('Undo + Clear + Out-and-back disabled at zero waypoints', async ({ page }) => {
		await page.goto('/routes/new');
		// Needed: next read is .count() (snapshot — no auto-retry).
		// Without the wait, a 0 here loops zero times and the test
		// passes vacuously without actually asserting disabled state.
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
		// Regression: a failed OSRM run must not leave Save enabled with
		// a stale or empty polyline. Routing is now automatic — dropping
		// the second waypoint kicks off the snap with no button press.
		// Intercept every OSRM segment with a 503 so the auto-route
		// fails, drop two waypoints via the builder's dev-exposed
		// addWaypoint API (synthetic canvas clicks don't land reliably on
		// MapLibre's WebGL pointer pipeline in headless chromium), and
		// assert the gate stays armed.
		await page.route('https://router.project-osrm.org/**', (route) =>
			route.fulfill({ status: 503, body: '{}' })
		);

		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypoints(page, [
			{ lng: 144.97, lat: -37.816 },
			{ lng: 144.975, lat: -37.82 }
		]);

		// The auto-route fires after the debounce and settles (1 segment
		// × 2 retries × 8s timeout cap). Error banner is red
		// (.routing-error without .routing-warning).
		const banner = page.locator('.routing-error');
		await expect(banner).toBeVisible({ timeout: 30_000 });
		await expect(banner).not.toHaveClass(/routing-warning/);

		// Save button stays disabled — routed didn't flip true.
		await expect(page.getByRole('button', { name: /Save Route/ })).toBeDisabled();
	});

	test('auto-routing fetches only the new segment per added waypoint (cache)', async ({
		page,
	}) => {
		// The headline behaviour ported from mobile: dropping the Nth pin
		// re-routes only the one new segment, reusing the N-2 already
		// snapped before it. Without the per-segment cache, adding 4
		// waypoints one at a time would cost 1+2+3 = 6 OSRM /route calls;
		// with it, exactly 3 (A→B, then B→C, then C→D). Counting the
		// calls is the cleanest proof that placement stays O(1), not
		// O(n), as the route grows.
		let routeCalls = 0;
		await page.route('https://router.project-osrm.org/route/v1/**', (route) => {
			routeCalls++;
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					code: 'Ok',
					routes: [
						{
							geometry: {
								coordinates: [
									[0, 0],
									[0.001, 0.001],
								],
							},
							distance: 100,
						},
					],
					waypoints: [{ location: [0, 0] }, { location: [0.001, 0.001] }],
				}),
			});
		});
		// Elevation is fetched after each successful snap — stub it so the
		// route settles offline.
		await page.route('https://api.open-meteo.com/**', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ elevation: Array(100).fill(10) }),
			})
		);

		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);

		const addOne = async (lng: number, lat: number) => {
			await page.evaluate(
				(p) => {
					(
						window as unknown as {
							__routeBuilder: { addWaypoint: (q: { lat: number; lng: number }) => void };
						}
					).__routeBuilder.addWaypoint(p);
				},
				{ lng, lat }
			);
		};

		// First point: no segment yet (need >= 2 waypoints).
		await addOne(144.97, -37.816);
		await page.waitForTimeout(300);
		expect(routeCalls).toBe(0);

		// Second point → 1 segment fetched.
		await addOne(144.975, -37.82);
		await expect.poll(() => routeCalls, { timeout: 5_000 }).toBe(1);

		// Third point → only B→C fetched (A→B reused from cache).
		await addOne(144.98, -37.824);
		await expect.poll(() => routeCalls, { timeout: 5_000 }).toBe(2);

		// Fourth point → only C→D fetched. Total 3, not 6.
		await addOne(144.985, -37.828);
		await expect.poll(() => routeCalls, { timeout: 5_000 }).toBe(3);

		// A real route was produced → Save enables with no button press.
		await expect(page.getByRole('button', { name: /Save Route/ })).toBeEnabled({
			timeout: 5_000,
		});
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
		// Needed: next call is page.evaluate() which reads CSSStyleSheets
		// directly; no Playwright auto-wait on raw DOM snapshots.
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
		// Use the dev-exposed addWaypoint API to plant three waypoints
		// deterministically — synthetic canvas clicks on the MapLibre
		// WebGL surface aren't reliable in headless chromium. Plant
		// them near the map's current center so the marker DOM lands
		// inside the viewport (needed for the marker.click() below).
		// Waypoint placement now auto-routes. Stub OSRM so the background
		// snap is deterministic + offline (this test only cares about
		// waypoint-count bookkeeping, not the snapped geometry).
		await page.route('https://router.project-osrm.org/**', (route) =>
			route.fulfill({ status: 503, body: '{}' })
		);

		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypointsNearMapCenter(page, [
			{ dLat: 0, dLng: 0 },
			{ dLat: -0.05, dLng: 0.05 },
			{ dLat: 0, dLng: 0.1 }
		]);

		const pointsValue = page.locator('.builder-stat-value').nth(2);
		await expect(pointsValue).toHaveText('3', { timeout: 5_000 });
		const startingCount = '3';

		// Click the middle marker (waypoint 2 in 1-based, index 1
		// in the markers array — the second .maplibregl-marker).
		// force: true bypasses Playwright's "subtree intercepts pointer
		// events" check — the SVG path inside the marker is part of
		// the marker's own DOM, not an unrelated overlay; the
		// component's click handler listens at the marker root and
		// fires regardless of which descendant the synthetic click
		// originates on.
		const markers = page.locator('.maplibregl-marker');
		const before = await markers.count();
		await markers.nth(1).click({ force: true });
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
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypoints(page, [{ lng: 144.97, lat: -37.816 }]);
		const marker = page.locator('.maplibregl-marker').first();
		await expect(marker).toBeVisible({ timeout: 5_000 });
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

	test('shortcuts hint does NOT overlap the "Click anywhere to start" card', async ({
		page,
	}) => {
		// Field report: "the click anywhere to start modal is underneath
		// another info modal in the bottom left." Both the empty-state
		// onboarding card (.canvas-empty, z-index 5) and the keyboard
		// shortcuts hint (.shortcuts-hint, z-index 10) used to live in the
		// bottom-left corner, so the hint covered the onboarding card. The
		// fix moves the hint to bottom-right. Assert the two boxes don't
		// intersect so the regression can't silently come back.
		await page.goto('/routes/new');
		await waitForRouteBuilder(page);

		const card = page.locator('.canvas-empty');
		const hint = page.locator('.shortcuts-hint');
		await expect(card).toBeVisible({ timeout: 10_000 });
		await expect(hint).toBeVisible({ timeout: 10_000 });

		const cardBox = await card.boundingBox();
		const hintBox = await hint.boundingBox();
		expect(cardBox).not.toBeNull();
		expect(hintBox).not.toBeNull();

		const a = cardBox!;
		const b = hintBox!;
		const disjoint =
			a.x + a.width <= b.x ||
			b.x + b.width <= a.x ||
			a.y + a.height <= b.y ||
			b.y + b.height <= a.y;
		expect(
			disjoint,
			`shortcuts hint ${JSON.stringify(b)} overlaps the empty-state ` +
				`card ${JSON.stringify(a)} — they must not share the corner`,
		).toBe(true);
	});

	test('builder.flyTo pans the map to the given point', async ({ page }) => {
		// New export backing the sidebar's "use my location" + typed-coord
		// affordances: setting a Generate start/end now recentres the map so
		// the click has visible feedback. Drive the export directly and
		// assert getMapCenter() moves to the requested point.
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);

		const target = { lat: 51.5074, lng: -0.1278 }; // London
		await page.evaluate((p) => {
			(
				window as unknown as {
					__routeBuilder: { flyTo: (q: { lat: number; lng: number }, z?: number) => void };
				}
			).__routeBuilder.flyTo(p, 14);
		}, target);

		await expect
			.poll(
				async () => {
					const c = await page.evaluate(() =>
						(
							window as unknown as {
								__routeBuilder: { getMapCenter: () => { lat: number; lng: number } | null };
							}
						).__routeBuilder.getMapCenter(),
					);
					if (!c) return Infinity;
					return Math.abs(c.lat - target.lat) + Math.abs(c.lng - target.lng);
				},
				{ timeout: 8_000 },
			)
			.toBeLessThan(0.5);
	});

	test('Generate-by-distance: distance presets update the slider label', async ({ page }) => {
		await page.goto('/routes/new');
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
		// Loop generation tries the server endpoint first; force it
		// unavailable so the builder falls back to the (failing) OSRM
		// heuristic and surfaces its generation-specific error.
		await page.route('**/api/routes/generate', (route) => route.fulfill({ status: 501, body: '{}' }));
		await page.route('https://router.project-osrm.org/**', (route) =>
			route.fulfill({ status: 503, body: '{}' }),
		);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);

		// Open the distance-target panel + plant the start point
		// programmatically (the page hook bypasses the WebGL pick-on-map
		// click). Generate then runs the same OSRM path the user would.
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		await setStartPoint(page, { lng: 144.97, lat: -37.816 });
		await expect(page.locator('.point-set').first()).toBeVisible({ timeout: 5_000 });

		await page.getByRole('button', { name: /Generate .* (loop|route)/ }).click();
		const banner = page.locator('.routing-error').first();
		await expect(banner).toBeVisible({ timeout: 30_000 });
		await expect(banner).toContainText(/Couldn't generate/i);
	});

	// Reason: a field report surfaced that the Generate-by-distance
	// start picker had no visual confirmation — the user clicked
	// "Pick start on map", clicked the map, and saw only a sidebar
	// text label change. The marker on the map only appeared AFTER
	// they clicked "Generate". The fix paints a green flag marker
	// the moment the start point is set (and a red flag for the
	// optional end point) via two new builder exports
	// setGenerationStart / setGenerationEnd. None of the prior
	// builder e2e tests asserted what was on the map between pick
	// and Generate — they only checked the post-Generate state
	// (error banner / Cancel button) — which is why the gap stayed
	// invisible.
	test('Pick start on map paints a green flag marker BEFORE Generate runs', async ({
		page,
	}) => {
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);

		// Open the distance-target panel. Pre-pick, no endpoint markers.
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		await expect(
			page.locator('[data-testid="generation-endpoint-start"]'),
		).toHaveCount(0);

		// Plant a start. The page's $effect feeds it into the builder via
		// the dev hook; the builder's renderEndpointMarker mounts the
		// green flag.
		await setStartPoint(page, { lng: 144.97, lat: -37.816 });

		const startMarker = page.locator(
			'[data-testid="generation-endpoint-start"]',
		);
		await expect(startMarker).toBeVisible({ timeout: 5_000 });
		// Marker must be inside the map container, not a stray DOM node.
		const inMap = await startMarker.evaluate((el) =>
			Boolean(el.closest('.maplibregl-map')),
		);
		expect(inMap).toBe(true);
		// And the sidebar text label is still there — visual + textual
		// confirmation together, not one OR the other.
		await expect(page.locator('.point-set').first()).toBeVisible();
	});

	test('Clearing the picked start removes its marker', async ({ page }) => {
		// Page-level state has a clear path (the X button next to the
		// picked-coords pill). Pre-fix the marker stayed because no
		// marker existed; now that one exists, the clear MUST drop it
		// so the user can re-pick from scratch.
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		await setStartPoint(page, { lng: 144.97, lat: -37.816 });

		const startMarker = page.locator(
			'[data-testid="generation-endpoint-start"]',
		);
		await expect(startMarker).toBeVisible({ timeout: 5_000 });

		// Use the page hook to null the start — same shape the Clear
		// button uses (`startPoint = null`).
		await page.evaluate(() => {
			const pg = (window as unknown as {
				__routeBuilderPage: {
					setStartPoint: (p: { lat: number; lng: number } | null) => void;
				};
			}).__routeBuilderPage;
			pg.setStartPoint(null);
		});

		await expect(startMarker).toHaveCount(0, { timeout: 5_000 });
	});

	test('Cancel button appears while generate is in flight', async ({ page }) => {
		// Audit #8: long-running batches were unstoppable short of Esc
		// (which dumped the whole route). The Cancel button replaces
		// Generate while isRouting=true and calls cancelGeneration(),
		// which bumps routeVersion → the in-flight recalculateRoute
		// bails at its next checkpoint.
		//
		// Loop generation tries the server endpoint first; force it
		// unavailable (fast 501) so the in-flight, cancellable work is the
		// slow OSRM fallback below.
		await page.route('**/api/routes/generate', (route) => route.fulfill({ status: 501, body: '{}' }));
		// Slow-walk every OSRM call so we have time to observe the
		// busy state before any of them finishes.
		await page.route('https://router.project-osrm.org/**', async (route) => {
			await new Promise((r) => setTimeout(r, 4000));
			await route.fulfill({ status: 503, body: '{}' });
		});
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);

		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		await setStartPoint(page, { lng: 144.97, lat: -37.816 });
		await expect(page.locator('.point-set').first()).toBeVisible({ timeout: 5_000 });

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

test.describe('/routes/new — "use my location" pans the map', () => {
	// Field report: "the locate start marker doesnt do anything." The
	// start/end "use my location" buttons set a sidebar label + painted a
	// marker, but never recentred the map — so on the default world view
	// (geolocation denied at mount) the click looked dead. The fix flies
	// the map to the located point. Grant geolocation + a fixed position
	// so the button resolves a real fix.
	const FIX = { latitude: 48.8566, longitude: 2.3522 }; // Paris
	test.use({
		storageState: USER_A.storageStatePath,
		permissions: ['geolocation'],
		geolocation: FIX,
	});

	async function mapCenter(page: Page): Promise<{ lat: number; lng: number } | null> {
		return page.evaluate(() =>
			(
				window as unknown as {
					__routeBuilder: { getMapCenter: () => { lat: number; lng: number } | null };
				}
			).__routeBuilder.getMapCenter(),
		);
	}

	test('clicking "Use my location for start" recentres the map + paints the start marker', async ({
		page,
	}) => {
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);

		// The on-mount geolocation may already centre near the fix; move
		// the map far away (Sydney) first so the locate click has an
		// observable effect to assert.
		const SYDNEY = { lat: -33.8688, lng: 151.2093 };
		await page.evaluate((s) => {
			(
				window as unknown as {
					__routeBuilder: { flyTo: (q: { lat: number; lng: number }, z?: number) => void };
				}
			).__routeBuilder.flyTo(s, 12);
		}, SYDNEY);
		await expect
			.poll(
				async () => {
					const c = await mapCenter(page);
					if (!c) return Infinity;
					return Math.abs(c.lat - SYDNEY.lat) + Math.abs(c.lng - SYDNEY.lng);
				},
				{ timeout: 8_000 },
			)
			.toBeLessThan(0.5);

		// Open the distance-target panel so the start point-row (with the
		// my_location button) is mounted, then click it.
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		await page.getByRole('button', { name: 'Use my location for start' }).click();

		// Map flies back to the geolocation fix...
		await expect
			.poll(
				async () => {
					const c = await mapCenter(page);
					if (!c) return Infinity;
					return Math.abs(c.lat - FIX.latitude) + Math.abs(c.lng - FIX.longitude);
				},
				{ timeout: 10_000 },
			)
			.toBeLessThan(0.5);

		// ...and the green start marker is painted (driven by the page's
		// $effect → setGenerationStart) + the sidebar reads "My location".
		await expect(
			page.locator('[data-testid="generation-endpoint-start"]'),
		).toBeVisible({ timeout: 5_000 });
		await expect(page.locator('.point-set').first()).toContainText('My location');
	});

	test('typed start coordinates recentre the map', async ({ page }) => {
		// Same visual-confirmation fix on the keyboard-accessible coord
		// entry: typing a start lat/lng + "Set start" flies the map there.
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);

		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		// New York — far from the Paris geolocation fix the map mounts at.
		await page.getByLabel('Start latitude').fill('40.7128');
		await page.getByLabel('Start longitude').fill('-74.0060');
		await page.getByRole('button', { name: 'Set start', exact: true }).click();

		await expect
			.poll(
				async () => {
					const c = await mapCenter(page);
					if (!c) return Infinity;
					return Math.abs(c.lat - 40.7128) + Math.abs(c.lng - -74.006);
				},
				{ timeout: 10_000 },
			)
			.toBeLessThan(0.5);
	});
});
