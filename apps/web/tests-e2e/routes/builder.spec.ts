import { expect, test, type Page } from '@playwright/test';

import { deleteRoute } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Stub OSRM (host-agnostic — the dev server points at localhost:5000
 * locally and the public demo in CI, so match `** /route/v1/**`) so a
 * segment snaps to a clean polyline that echoes the requested waypoints,
 * plus the open-meteo elevation lookup. With this a dropped pair of
 * waypoints auto-routes to a real (non-deviating) line and Save / GPX
 * enable with no network.
 */
async function stubRoutingSuccess(page: Page): Promise<void> {
	await page.route('**/route/v1/**', (route) => {
		const url = route.request().url();
		const m = url.match(/\/foot\/([-0-9.,;]+)/);
		const coords: [number, number][] = m
			? m[1].split(';').map((p) => p.split(',').map(Number) as [number, number])
			: [
					[0, 0],
					[0.001, 0.001],
				];
		route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify({
				code: 'Ok',
				routes: [{ geometry: { coordinates: coords }, distance: 1000 }],
				waypoints: coords.map((c) => ({ location: c })),
			}),
		});
	});
	await page.route('https://api.open-meteo.com/**', (route) =>
		route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify({ elevation: Array(100).fill(10) }),
		}),
	);
}

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
		// Host-agnostic so the per-segment counter works against both CI's
		// demo host and the local localhost:5000 OSRM override.
		await page.route('**/route/v1/**', (route) => {
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
		// Host-agnostic OSRM match (route + nearest both contain `/v1/foot/`;
		// elevation is `/v1/elevation`) so the mock intercepts both the CI
		// demo host and the local localhost:5000 OSRM override.
		await page.route('**/v1/foot/**', (route) =>
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
		// Slow-walk every OSRM call (route + nearest, host-agnostic) so we
		// have time to observe the busy state before any of them finishes.
		await page.route('**/v1/foot/**', async (route) => {
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

	test('typed coordinates: invalid input shows an error + sets no point, then valid clears it', async ({
		page,
	}) => {
		// applyCoords validates the keyboard-entry fields (WCAG 2.1.1
		// alternative to map-tap). Untested until now: a non-numeric or
		// out-of-range entry must surface .coord-error AND leave the point
		// unset, and a subsequent valid entry must clear the error + set it.
		await page.goto('/routes/new');
		await waitForRouteBuilder(page);
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();

		const startRow = page.locator('.point-row').first();
		const err = page.locator('.coord-error').first();

		// Non-numeric → numeric error, start stays unset.
		await page.getByLabel('Start latitude').fill('abc');
		await page.getByLabel('Start longitude').fill('10');
		await page.getByRole('button', { name: 'Set start', exact: true }).click();
		await expect(err).toBeVisible();
		await expect(err).toContainText(/numeric/i);
		await expect(startRow.locator('.point-unset')).toBeVisible();

		// Out-of-range latitude → range error, still unset.
		await page.getByLabel('Start latitude').fill('200');
		await page.getByLabel('Start longitude').fill('10');
		await page.getByRole('button', { name: 'Set start', exact: true }).click();
		await expect(err).toContainText(/-90\.\.90|range|180/i);
		await expect(startRow.locator('.point-unset')).toBeVisible();

		// Valid → error clears + the point pill renders the coords.
		await page.getByLabel('Start latitude').fill('-37.8136');
		await page.getByLabel('Start longitude').fill('144.9631');
		await page.getByRole('button', { name: 'Set start', exact: true }).click();
		await expect(err).toHaveCount(0);
		await expect(startRow.locator('.point-set')).toContainText('-37.81');
	});

	test('Undo pops the last waypoint; Clear resets to the empty state', async ({ page }) => {
		// The "disabled at zero waypoints" test only pins the gate; this
		// drives the toolbar actions themselves. OSRM 503 so the background
		// auto-route settles offline — we only assert waypoint bookkeeping.
		await page.route('**/route/v1/**', (route) =>
			route.fulfill({ status: 503, body: '{}' }),
		);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypointsNearMapCenter(page, [
			{ dLat: 0, dLng: 0 },
			{ dLat: -0.02, dLng: 0.02 },
			{ dLat: 0, dLng: 0.04 },
		]);

		const points = page.locator('.builder-stat-value').nth(2);
		await expect(points).toHaveText('3', { timeout: 5_000 });

		await page.locator('.toolbar-group .btn', { hasText: 'Undo' }).click();
		await expect(points).toHaveText('2');

		await page.locator('.toolbar-group .btn', { hasText: 'Clear' }).click();
		await expect(points).toHaveText('0');
		// Empty-state onboarding card comes back once the route is cleared.
		await expect(page.locator('.canvas-empty')).toBeVisible();
	});

	test('Out & back doubles the point-to-point sequence', async ({ page }) => {
		// outAndBack on a non-loop [a,b,c] appends the reversed interior
		// (minus the turnaround) → [a,b,c,b,a]; the points stat goes 3 → 5.
		await page.route('**/route/v1/**', (route) =>
			route.fulfill({ status: 503, body: '{}' }),
		);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypointsNearMapCenter(page, [
			{ dLat: 0, dLng: 0 },
			{ dLat: -0.02, dLng: 0.02 },
			{ dLat: 0, dLng: 0.04 },
		]);

		const points = page.locator('.builder-stat-value').nth(2);
		await expect(points).toHaveText('3', { timeout: 5_000 });

		await page.locator('.toolbar-group .btn', { hasText: 'Out & back' }).click();
		await expect(points).toHaveText('5', { timeout: 5_000 });
	});

	test('GPX + KML export buttons download a file once a route is calculated', async ({
		page,
	}) => {
		// handleExportGpx / handleExportKml build the file in-browser from
		// the snapped coordinates + elevations and trigger a download. The
		// buttons are gated on `routed`; stub OSRM so a clean route exists.
		await stubRoutingSuccess(page);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypoints(page, [
			{ lng: 144.97, lat: -37.816 },
			{ lng: 144.975, lat: -37.82 },
		]);

		const gpx = page.getByRole('button', { name: 'GPX' });
		await expect(gpx).toBeEnabled({ timeout: 10_000 });
		const [gpxDownload] = await Promise.all([page.waitForEvent('download'), gpx.click()]);
		expect(gpxDownload.suggestedFilename()).toMatch(/\.gpx$/);

		const kml = page.getByRole('button', { name: 'KML' });
		await expect(kml).toBeEnabled();
		const [kmlDownload] = await Promise.all([page.waitForEvent('download'), kml.click()]);
		expect(kmlDownload.suggestedFilename()).toMatch(/\.kml$/);
	});

	test('clicking the START marker with 3+ waypoints closes the loop', async ({ page }) => {
		// The marker click handler has a distinct branch for the start
		// marker (index 0) once there are >= 3 waypoints: it appends a
		// closing waypoint at the start coords so OSRM routes back to the
		// origin. The existing back-track test only clicks a MIDDLE marker,
		// so this close-the-loop branch was uncovered.
		await page.route('**/route/v1/**', (route) =>
			route.fulfill({ status: 503, body: '{}' }),
		);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypointsNearMapCenter(page, [
			{ dLat: 0, dLng: 0 },
			{ dLat: -0.03, dLng: 0.03 },
			{ dLat: 0.03, dLng: 0.03 },
		]);

		const points = page.locator('.builder-stat-value').nth(2);
		await expect(points).toHaveText('3', { timeout: 5_000 });

		// First marker = the start (index 0, green).
		await page.locator('.maplibregl-marker').first().click({ force: true });
		await expect(points).toHaveText('4');

		// The appended closing waypoint sits exactly on the start.
		const wp = await page.evaluate(
			() =>
				(
					window as unknown as {
						__routeBuilder: {
							getRouteData: () => { waypoints: { lat: number; lng: number }[] };
						};
					}
				).__routeBuilder.getRouteData().waypoints,
		);
		expect(wp.length).toBe(4);
		expect(wp[wp.length - 1].lat).toBeCloseTo(wp[0].lat, 9);
		expect(wp[wp.length - 1].lng).toBeCloseTo(wp[0].lng, 9);
	});

	test('dragging a waypoint marker moves that waypoint (and only that one)', async ({
		page,
	}) => {
		// The marker dragend handler rewrites waypoints[currentIndex] to the
		// dropped position, invalidates the snapped polyline, and re-routes.
		// Pixel-drag the second marker and assert its underlying coord moved
		// while the first marker's coord is untouched.
		await stubRoutingSuccess(page);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypointsNearMapCenter(page, [
			{ dLat: 0, dLng: 0 },
			{ dLat: 0.03, dLng: 0.03 },
		]);
		await expect(page.getByRole('button', { name: /Save Route/ })).toBeEnabled({
			timeout: 10_000,
		});

		const readWaypoints = () =>
			page.evaluate(
				() =>
					(
						window as unknown as {
							__routeBuilder: {
								getRouteData: () => { waypoints: { lat: number; lng: number }[] };
							};
						}
					).__routeBuilder.getRouteData().waypoints,
			);
		const before = await readWaypoints();

		const marker = page.locator('.maplibregl-marker').nth(1);
		const box = await marker.boundingBox();
		expect(box).not.toBeNull();
		const cx = box!.x + box!.width / 2;
		const cy = box!.y + box!.height / 2;
		await page.mouse.move(cx, cy);
		await page.mouse.down();
		await page.mouse.move(cx + 70, cy + 50, { steps: 10 });
		await page.mouse.up();

		// dragend updates the model; poll until waypoint[1] differs.
		await expect
			.poll(
				async () => {
					const w = await readWaypoints();
					return w[1].lat !== before[1].lat || w[1].lng !== before[1].lng;
				},
				{ timeout: 5_000 },
			)
			.toBe(true);

		const after = await readWaypoints();
		// The start (index 0) is untouched by dragging marker 1.
		expect(after[0].lat).toBe(before[0].lat);
		expect(after[0].lng).toBe(before[0].lng);
	});

	test('numbered pin labels stay 1..N after a mid-route insert', async ({ page }) => {
		// Each marker bakes its 1-based number in at creation. A mid-route
		// insert splices a marker into the array, shifting every later
		// marker's index — but nothing renumbered them, so the later pins
		// kept stale numbers (a duplicate appears, the top number goes
		// missing). The numbers exist specifically so users can count pins
		// and tell which to drag, so a wrong number is a real defect.
		await page.route('**/v1/foot/**', (route) =>
			route.fulfill({ status: 503, body: '{}' }),
		);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypointsNearMapCenter(page, [
			{ dLat: 0, dLng: 0 },
			{ dLat: 0.02, dLng: 0.02 },
			{ dLat: 0.04, dLng: 0 },
		]);
		const points = page.locator('.builder-stat-value').nth(2);
		await expect(points).toHaveText('3', { timeout: 5_000 });

		// Insert between pin #1 and #2 via the public API.
		await page.evaluate(() => {
			const b = (
				window as unknown as {
					__routeBuilder: {
						insertWaypoint: (p: { lat: number; lng: number }, i: number) => void;
						getMapCenter: () => { lat: number; lng: number };
					};
				}
			).__routeBuilder;
			const c = b.getMapCenter();
			b.insertWaypoint({ lng: c.lng + 0.01, lat: c.lat + 0.01 }, 1);
		});
		await expect(points).toHaveText('4');

		// Every pin must carry a distinct sequential number 1..4.
		const labels = (await page.locator('.waypoint-marker-label').allTextContents())
			.map(Number)
			.sort((a, b) => a - b);
		expect(labels).toEqual([1, 2, 3, 4]);
	});

	test('numbered pin labels stay 1..N after deleting a middle waypoint', async ({
		page,
	}) => {
		// Mirror of the insert case for removeWaypoint (right-click delete):
		// removing a middle pin shifts every later index down, which must
		// renumber the remaining pins.
		await page.route('**/v1/foot/**', (route) =>
			route.fulfill({ status: 503, body: '{}' }),
		);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypointsNearMapCenter(page, [
			{ dLat: 0, dLng: 0 },
			{ dLat: 0.02, dLng: 0.02 },
			{ dLat: 0.04, dLng: 0 },
			{ dLat: 0.06, dLng: 0.02 },
		]);
		const points = page.locator('.builder-stat-value').nth(2);
		await expect(points).toHaveText('4', { timeout: 5_000 });

		// Delete the second pin (index 1).
		await page.evaluate(() => {
			(
				window as unknown as {
					__routeBuilder: { removeWaypoint: (i: number) => void };
				}
			).__routeBuilder.removeWaypoint(1);
		});
		await expect(points).toHaveText('3');

		const labels = (await page.locator('.waypoint-marker-label').allTextContents())
			.map(Number)
			.sort((a, b) => a - b);
		expect(labels).toEqual([1, 2, 3]);
	});

	// --- Adversarial: failure + boundary paths ---

	test('partial OSRM failure keeps the route — warning banner + Save stays enabled', async ({
		page,
	}) => {
		// Contract: when SOME segments snap and some don't, the builder
		// keeps the route (straight-line fallback through the gaps) and
		// surfaces a soft warning — Save must stay enabled. 3 waypoints =
		// 2 segments; fail only the segment that touches the 3rd (a
		// distinctive lng) so okSegments=1 < total=2 → partial success.
		const BAD_LNG = '145.999';
		await page.route('**/route/v1/**', (route) => {
			const url = route.request().url();
			if (url.includes(BAD_LNG)) {
				route.fulfill({ status: 503, body: '{}' });
				return;
			}
			const m = url.match(/\/foot\/([-0-9.,;]+)/);
			const coords: [number, number][] = m
				? m[1].split(';').map((p) => p.split(',').map(Number) as [number, number])
				: [
						[0, 0],
						[0.001, 0.001],
					];
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					code: 'Ok',
					routes: [{ geometry: { coordinates: coords }, distance: 1000 }],
					waypoints: coords.map((c) => ({ location: c })),
				}),
			});
		});
		await page.route('https://api.open-meteo.com/**', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ elevation: Array(100).fill(10) }),
			}),
		);

		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypoints(page, [
			{ lng: 144.97, lat: -37.816 },
			{ lng: 144.975, lat: -37.82 },
			{ lng: 145.999, lat: -37.83 },
		]);

		// Soft warning banner (distinct .routing-warning class), not a hard
		// error — and Save is still reachable.
		await expect(page.locator('.routing-error.routing-warning')).toBeVisible({
			timeout: 20_000,
		});
		await expect(page.getByRole('button', { name: /Save Route/ })).toBeEnabled();
	});

	test('coordinate entry accepts the 90/180 boundary but rejects just beyond it', async ({
		page,
	}) => {
		// The validation is `lat < -90 || lat > 90 || lng < -180 || lng >
		// 180` — so the exact poles / antimeridian are valid and anything
		// past them is not. Pins the off-by-one boundary.
		await page.goto('/routes/new');
		await waitForRouteBuilder(page);
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();

		const err = page.locator('.coord-error').first();
		const startRow = page.locator('.point-row').first();

		await page.getByLabel('Start latitude').fill('90');
		await page.getByLabel('Start longitude').fill('180');
		await page.getByRole('button', { name: 'Set start', exact: true }).click();
		await expect(err).toHaveCount(0);
		await expect(startRow.locator('.point-set')).toContainText('90.00');

		await page.getByLabel('Start latitude').fill('90.0001');
		await page.getByLabel('Start longitude').fill('180');
		await page.getByRole('button', { name: 'Set start', exact: true }).click();
		await expect(err).toBeVisible();
		await expect(err).toContainText(/-90\.\.90|180|range/i);
	});

	test('whitespace-only name keeps the modal Save button disabled', async ({ page }) => {
		// canSave = routed && name.trim().length > 0. A naive name.length
		// check would let three spaces through; the trim gate must not.
		await stubRoutingSuccess(page);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypoints(page, [
			{ lng: 144.97, lat: -37.816 },
			{ lng: 144.975, lat: -37.82 },
		]);
		const saveBtn = page.getByRole('button', { name: /Save Route/ });
		await expect(saveBtn).toBeEnabled({ timeout: 10_000 });
		await saveBtn.click();

		await page.getByPlaceholder('My Route').fill('   ');
		await expect(
			page.getByRole('button', { name: 'Save route', exact: true }),
		).toBeDisabled();
	});

	test('save server error surfaces in the modal + does NOT navigate away', async ({ page }) => {
		// The route INSERT fails (500). handleSaveRoute must catch it,
		// show .save-error, keep the modal open, and leave the user on
		// /routes/new with their work intact — never a half-navigated
		// dead end. Fail only the POST so detail-page reads still work.
		await stubRoutingSuccess(page);
		await page.route('**/rest/v1/routes**', async (route) => {
			if (route.request().method() === 'POST') {
				await route.fulfill({
					status: 500,
					contentType: 'application/json',
					body: JSON.stringify({ message: 'simulated insert failure', code: '' }),
				});
			} else {
				await route.fallback();
			}
		});

		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypoints(page, [
			{ lng: 144.97, lat: -37.816 },
			{ lng: 144.975, lat: -37.82 },
		]);
		const saveBtn = page.getByRole('button', { name: /Save Route/ });
		await expect(saveBtn).toBeEnabled({ timeout: 10_000 });
		await saveBtn.click();
		await page.getByPlaceholder('My Route').fill('e2e-failsave');
		await page.getByRole('button', { name: 'Save route', exact: true }).click();

		await expect(page.locator('.save-error')).toBeVisible({ timeout: 10_000 });
		// Still on the builder, modal still open, nothing lost.
		await expect(page).toHaveURL(/\/routes\/new$/);
		await expect(page.getByPlaceholder('My Route')).toHaveValue('e2e-failsave');
	});

	test('use-my-location with permission denied shows an error toast + sets no point', async ({
		page,
	}) => {
		// Round-1 fix: the locate buttons must not fail silently. Force
		// geolocation to report PERMISSION_DENIED (code 1) and assert the
		// sidebar "use my location" surfaces the toast + leaves start unset.
		await page.addInitScript(() => {
			const denied = (_ok: PositionCallback, err?: PositionErrorCallback | null) => {
				err?.({ code: 1, message: 'denied' } as GeolocationPositionError);
			};
			navigator.geolocation.getCurrentPosition = denied;
			navigator.geolocation.watchPosition = () => 0;
		});
		await page.goto('/routes/new');
		await waitForRouteBuilder(page);
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		await page.getByRole('button', { name: 'Use my location for start' }).click();

		const toast = page.locator('.toast.toast-error');
		await expect(toast).toBeVisible({ timeout: 5_000 });
		await expect(toast).toContainText(/permission denied/i);
		await expect(page.locator('.point-row').first().locator('.point-unset')).toBeVisible();
	});

	test('map "locate me" with permission denied shows an error toast', async ({ page }) => {
		// Same fail-loud contract on the map's own locate button
		// (goToMyLocation) — a separate code path from the sidebar one.
		await page.addInitScript(() => {
			const denied = (_ok: PositionCallback, err?: PositionErrorCallback | null) => {
				err?.({ code: 1, message: 'denied' } as GeolocationPositionError);
			};
			navigator.geolocation.getCurrentPosition = denied;
			navigator.geolocation.watchPosition = () => 0;
		});
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await page.locator('.locate-btn').click();

		const toast = page.locator('.toast.toast-error');
		await expect(toast).toBeVisible({ timeout: 5_000 });
		await expect(toast).toContainText(/permission denied/i);
	});

	test('export filename stays usable for a non-ASCII route name (never a bare ".gpx")', async ({
		page,
	}) => {
		// Bug found this round: the export filename sanitizer strips every
		// non-Latin character, so a Japanese / emoji route name collapsed
		// to "" and the download was named just ".gpx". Set such a name via
		// the Save modal (routeName persists after Cancel), then export and
		// assert the filename has a real basename.
		await stubRoutingSuccess(page);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypoints(page, [
			{ lng: 144.97, lat: -37.816 },
			{ lng: 144.975, lat: -37.82 },
		]);
		const saveBtn = page.getByRole('button', { name: /Save Route/ });
		await expect(saveBtn).toBeEnabled({ timeout: 10_000 });
		await saveBtn.click();
		await page.getByPlaceholder('My Route').fill('マラソン大会');
		await page.getByRole('button', { name: 'Cancel' }).click();

		const [dl] = await Promise.all([
			page.waitForEvent('download'),
			page.getByRole('button', { name: 'GPX' }).click(),
		]);
		const fname = dl.suggestedFilename();
		expect(fname).toMatch(/\.gpx$/);
		expect(fname).not.toBe('.gpx');
		expect(fname.length).toBeGreaterThan('.gpx'.length);
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

test.describe('/routes/new — save flow', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// The new route row is written for real; delete it after each test so
	// the suite stays idempotent (same shape as save-as-route.spec.ts).
	let routeId: string | null = null;
	test.afterEach(async () => {
		if (routeId) {
			try {
				await deleteRoute(routeId);
			} catch (_) {
				/* best-effort */
			}
			routeId = null;
		}
	});

	test('calculate → Save Route → modal → save → navigate to /routes/[id] with the chosen name', async ({
		page,
	}) => {
		// The prior save test only force-enabled the gate + cancelled. This
		// drives the whole flow: a stubbed OSRM route flips `routed` true,
		// the sidebar Save opens the modal, the name persists, and Save
		// writes the row + navigates to the detail page rendering that name.
		await stubRoutingSuccess(page);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForRouteBuilder(page);
		await addWaypoints(page, [
			{ lng: 144.97, lat: -37.816 },
			{ lng: 144.975, lat: -37.82 },
		]);

		const saveBtn = page.getByRole('button', { name: /Save Route/ });
		await expect(saveBtn).toBeEnabled({ timeout: 10_000 });
		await saveBtn.click();

		const name = `e2e-builder-${Date.now()}`;
		const nameInput = page.getByPlaceholder('My Route');
		await expect(nameInput).toBeVisible();
		await nameInput.fill(name);

		// Modal submit is "Save route" (lowercase r) — distinct from the
		// sidebar "Save Route" behind it.
		await page.getByRole('button', { name: 'Save route', exact: true }).click();

		await page.waitForURL(/\/routes\/[0-9a-f-]+$/, { timeout: 15_000 });
		const m = page.url().match(/\/routes\/([0-9a-f-]+)$/);
		expect(m).not.toBeNull();
		routeId = m![1];

		await expect(page.getByRole('heading', { level: 1, name })).toBeVisible({
			timeout: 10_000,
		});
	});
});
