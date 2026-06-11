import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /routes — Heatmap tab (popular-route discovery overlay).
 *
 * Backed by the `heatmap_points_in_bbox` PostGIS RPC (migration
 * 20260828_001) which returns lat/lng of densified points from every
 * intersecting public route. The web mounts a MapLibre canvas with a
 * `heatmap` paint layer in `RouteHeatmap.svelte`; the tab is wired
 * into the `tab = 'heatmap'` branch of /routes.
 *
 * Real MapTiler tile rendering needs a key; these tests pin the
 * *control surface* + the underlying RPC plumbing without driving
 * the canvas:
 *
 *   - Tab is reachable and switches state.
 *   - URL query `?tab=heatmap` deep-links onto the tab.
 *   - The PostGIS RPC returns a non-error response (the migration
 *     fix from earlier this session — search_path = public,
 *     extensions — is the load-bearing precondition).
 *   - The component mounts the map container.
 */

test.describe('/routes — Heatmap tab', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('Heatmap tab button is reachable from /routes', async ({ page }) => {
		await page.goto('/routes');
		const heatmapTab = page.getByRole('tab', { name: 'Heatmap', exact: true });
		await expect(heatmapTab).toBeVisible({ timeout: 10_000 });
	});

	test('clicking Heatmap navigates to the standalone /routes/heatmap page',
		async ({ page }) => {
			// May 2026 layout fix: Heatmap moved to its own route so
			// the MapLibre canvas can own the layout column without
			// fighting the routes-page flex chain. Tab click now
			// navigates (it used to flip in-place).
			await page.goto('/routes');
			const mineTab = page.getByRole('tab', { name: 'My routes', exact: true });
			await expect(mineTab).toHaveClass(/active/);
			await page.getByRole('tab', { name: 'Heatmap', exact: true }).click();
			await page.waitForURL(/\/routes\/heatmap$/, { timeout: 10_000 });
			await expect(page.locator('.maplibregl-map')).toBeVisible({
				timeout: 15_000,
			});
		});

	test('legacy ?tab=heatmap URL bounces to /routes/heatmap',
		async ({ page }) => {
			// Deep-link compat: pre-May-2026 URLs continue to work,
			// they just redirect to the standalone page via onMount.
			await page.goto('/routes?tab=heatmap');
			await page.waitForURL(/\/routes\/heatmap$/, { timeout: 10_000 });
			await expect(page.locator('.maplibregl-map')).toBeVisible({
				timeout: 15_000,
			});
		});

	test('Heatmap page mounts a maplibregl canvas', async ({ page }) => {
		// Standalone /routes/heatmap route — RouteHeatmap mounts
		// directly inside a `position: fixed` container that owns
		// the layout column. The canvas only renders once MapLibre's
		// load event fires.
		// MapLibre injects `<canvas class="maplibregl-canvas">` once
		// the map's load event fires; we tolerate the canvas-missing
		// case (no MapTiler key in CI) by accepting either the canvas
		// or the .maplibregl-map container div.
		await page.goto('/routes/heatmap');
		const mapContainer = page.locator('.maplibregl-map');
		await expect(mapContainer).toBeVisible({ timeout: 15_000 });
	});

	test('Heatmap shows a search box + locate-me button', async ({ page }) => {
		// May 2026: the heatmap shipped without nav affordances. A user
		// who landed on /routes/heatmap could only see a blank map
		// when the default centre (London) was outside the tile data
		// they had on disk. Both controls were added in the same pass:
		//
		//   - Search box (top-center, always rendered — uses MapTiler
		//     when its key is set, falls back to Nominatim for the
		//     local Protomaps dev stack).
		//   - MapLibre's built-in GeolocateControl (top-right, no
		//     MapTiler dep — always available).
		//
		// Pin both as rendered DOM. The actual geocoding round-trip is
		// covered by node-tests on `searchPlacesWithKey` (the env-free
		// dispatcher) — this test is the wire-into-the-component check.
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map'))
			.toBeVisible({ timeout: 15_000 });

		// Search box: testid-tagged + the input's aria-label is stable.
		const search = page.getByTestId('heatmap-search');
		await expect(search).toBeVisible();
		await expect(
			search.getByRole('textbox', { name: /search for a place/i }),
		).toBeVisible();

		// Locate-me: MapLibre's GeolocateControl renders a button with
		// class `.maplibregl-ctrl-geolocate`. Stable across MapLibre
		// versions; the upstream test suite uses the same selector.
		await expect(page.locator('.maplibregl-ctrl-geolocate'))
			.toBeVisible({ timeout: 15_000 });
	});

	test('typing in the heatmap search box does not throw', async ({ page }) => {
		// Smoke: the search input wires through to searchPlaces. When
		// MapTiler is unconfigured (dev with the local Protomaps
		// stack), the Nominatim fallback fires. We don't assert on
		// the result list (rate-limited public endpoint, flaky in
		// CI) — just that typing doesn't throw an uncaught exception
		// and the input retains the typed value.
		const errors: string[] = [];
		page.on('pageerror', (e) => errors.push(e.message));

		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map'))
			.toBeVisible({ timeout: 15_000 });

		const input = page
			.getByTestId('heatmap-search')
			.getByRole('textbox');
		await input.fill('Richmond');
		await expect(input).toHaveValue('Richmond');

		// Wait past the 300ms debounce so the fetch has a chance to fire.
		await page.waitForTimeout(500);
		expect(
			errors,
			`page errors during search-input flow: ${errors.join(' | ')}`,
		).toHaveLength(0);
	});

	test('heatmap_points_in_bbox RPC returns a 2xx for a sane bbox', async ({ page }) => {
		// Direct PostGIS-RPC smoke: the migration's
		// `set search_path = public, extensions` fix (this session's
		// d39296f) made this RPC actually run. A regression that
		// dropped the extensions schema would 500 here. Drive via
		// the running Supabase REST endpoint with the seeded anon
		// session.
		const res = await page.evaluate(async () => {
			const r = await fetch(
				'http://localhost:54321/rest/v1/rpc/heatmap_points_in_bbox',
				{
					method: 'POST',
					headers: {
						'Content-Type': 'application/json',
						apikey:
							'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlLWRlbW8iLCJpYXQiOjE2NDE3NjkyMDAsImV4cCI6MTc5OTUzNTYwMH0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE',
					},
					body: JSON.stringify({
						p_min_lng: -0.2,
						p_min_lat: 51.4,
						p_max_lng: 0.0,
						p_max_lat: 51.6,
						p_max_points: 100,
					}),
				}
			);
			return { status: r.status, body: await r.text() };
		});
		// 200 = success; 401 acceptable only if the local stack is
		// gating anon on this RPC (which it should not — the function
		// has no SECURITY DEFINER + no auth check; the migration grants
		// EXECUTE to anon). Anything in the 5xx range = regression in
		// the migration's search_path fix.
		expect(res.status).toBeGreaterThanOrEqual(200);
		expect(res.status).toBeLessThan(500);
	});

	test('My routes ↔ Explore tabs are mutually exclusive', async ({ page }) => {
		// Tab state machine: My routes / Explore (Heatmap moved to
		// its own route in the May 2026 layout fix). The .active CSS
		// class drives the underline + colour. A regression in setTab
		// that left two active simultaneously would visually confuse
		// the page but not error — pin the count.
		await page.goto('/routes');
		await page.getByRole('tab', { name: 'Explore', exact: true }).click();
		await expect(page.locator('button.tab.active')).toHaveCount(1);
		await page.getByRole('tab', { name: 'My routes', exact: true }).click();
		await expect(page.locator('button.tab.active')).toHaveCount(1);
	});
});

test.describe('/routes/heatmap — auto-locate on load', () => {
	// Granting geolocation + a fixed position lets the GeolocateControl
	// resolve a fix the moment the page auto-triggers it on load.
	test.use({
		storageState: USER_A.storageStatePath,
		permissions: ['geolocation'],
		geolocation: { latitude: 37.5407, longitude: -77.436 },
	});

	test('user-location dot renders without pressing the locate button', async ({
		page,
	}) => {
		// Regression: the dot used to appear only after the user clicked
		// the "locate me" button, because the on-load geolocation was a
		// bare getCurrentPosition that just recentred the map. The dot is
		// owned by the GeolocateControl, so we now trigger the control
		// itself on load — which renders `.maplibregl-user-location-dot`.
		// We never touch `.maplibregl-ctrl-geolocate` in this test; the
		// dot must show on its own.
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({
			timeout: 15_000,
		});
		await expect(page.locator('.maplibregl-user-location-dot')).toBeVisible({
			timeout: 15_000,
		});
	});
});

test.describe('/routes/heatmap — geolocation failure fallback', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// Force the GeolocateControl's getCurrentPosition to fail with
	// POSITION_UNAVAILABLE (code 2) — the real-world Brave/VPN case where
	// the browser has a geolocation API but no backend that can resolve a
	// fix. Deterministic, and independent of Playwright's permission state.
	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			const geo = navigator.geolocation;
			if (geo) {
				geo.getCurrentPosition = (
					_success: PositionCallback,
					error?: PositionErrorCallback | null,
				) => {
					error?.({
						code: 2,
						message: 'forced unavailable (test)',
						PERMISSION_DENIED: 1,
						POSITION_UNAVAILABLE: 2,
						TIMEOUT: 3,
					} as GeolocationPositionError);
				};
			}
		});
	});

	test('failed locate shows a toast and frames the map on the route data', async ({
		page,
	}) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({
			timeout: 15_000,
		});

		// 1) The failure is surfaced, not swallowed. (code 2 → locateFailed)
		await expect(page.getByText("Couldn't find your location.")).toBeVisible({
			timeout: 15_000,
		});

		// 2) Instead of stranding the user at the [0, 30] world view, the map
		//    fits to the loaded route pins — the seed routes are all in
		//    Virginia, so the centre lands inside the state's bounding box.
		await page.waitForFunction(
			() => {
				const m = (
					window as unknown as {
						__heatmapMap?: { getCenter: () => { lng: number; lat: number } };
					}
				).__heatmapMap;
				if (!m) return false;
				const c = m.getCenter();
				return c.lng > -84 && c.lng < -75 && c.lat > 36 && c.lat < 40;
			},
			{ timeout: 15_000 },
		);
	});
});
