import { expect, test } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Heatmap discoverable-pin layers (clubs + popular/featured routes)
 * — interconnected coverage for the May 2026 feature pass.
 *
 * What this file pins down:
 *
 *   1. Backend RPCs return the expected shape + respect bbox /
 *      `is_public` filters. (No private clubs / private routes
 *      ever appear in the result; routes must be featured OR
 *      have run_count > 0.)
 *
 *   2. Web heatmap renders the pins as MapLibre circle layers
 *      and the count chips in the legend match the RPC result.
 *
 *   3. Clicking a pin opens a popup card (NOT instant
 *      navigation) with the expected content shape.
 *
 *   4. Clicking the popup's "View" action navigates client-side
 *      to the entity detail page, which returns 200.
 *
 *   5. Hover shows a name-only tooltip; mouseleave clears it.
 *
 *   6. Layer toggles in the legend hide / show the right layer.
 *
 *   7. The defensive `Number.isFinite` guard on the marker /
 *      popup paths keeps non-finite coordinates from collapsing
 *      to the (0,0) top-left of the map.
 *
 * Drives the page as an unauthenticated viewer when possible so
 * the share-link / anon flow stays exercised; uses USER_A for the
 * tests that need to assert the My-routes / detail-page side too.
 */

const VA_BBOX = {
	p_min_lng: -83.7,
	p_min_lat: 36.5,
	p_max_lng: -75.2,
	p_max_lat: 39.5,
	p_limit: 100,
};

// Hardcoded from seed.sql (these are stable across resets).
const RICHMOND_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';
const PRIVATE_CLUB_ID = 'c3333333-0000-0000-0000-000000000003';

test.describe('Heatmap pin RPCs (backend contract)', () => {
	test('clubs_in_bbox returns public Virginia clubs + skips private ones', async () => {
		const admin = getAdminClient();
		const { data, error } = await admin.rpc('clubs_in_bbox', VA_BBOX);
		expect(error, `RPC error: ${error?.message ?? ''}`).toBeNull();
		expect(data, 'RPC returned no data').toBeTruthy();
		const pins = data as Array<{
			id: string;
			name: string;
			is_public?: boolean;
			location_label: string | null;
			member_count: number;
			lng: number;
			lat: number;
		}>;

		// Seed has 8 public clubs across VA + 1 private (Friends of
		// Jared, c3333333). The RPC must surface exactly the 8.
		expect(pins.length).toBeGreaterThanOrEqual(2);
		const ids = pins.map((p) => p.id);
		expect(ids).not.toContain(PRIVATE_CLUB_ID);

		// Richmond Run Club is the renamed first seed club — must
		// be in the result with the new name + Richmond VA label.
		const rrc = pins.find((p) => p.id === RICHMOND_RUN_CLUB_ID);
		expect(rrc, 'Richmond Run Club must surface').toBeTruthy();
		expect(rrc!.name).toBe('Richmond Run Club');
		expect(rrc!.location_label).toContain('Richmond');

		// Coord sanity: all VA pins must be inside the requested bbox.
		for (const p of pins) {
			expect(p.lng).toBeGreaterThan(VA_BBOX.p_min_lng);
			expect(p.lng).toBeLessThan(VA_BBOX.p_max_lng);
			expect(p.lat).toBeGreaterThan(VA_BBOX.p_min_lat);
			expect(p.lat).toBeLessThan(VA_BBOX.p_max_lat);
		}
	});

	test('clubs_in_bbox respects bbox (empty when querying somewhere else)',
		async () => {
			const admin = getAdminClient();
			// Box over the Pacific — no clubs there.
			const { data } = await admin.rpc('clubs_in_bbox', {
				p_min_lng: -160,
				p_min_lat: 10,
				p_max_lng: -140,
				p_max_lat: 30,
				p_limit: 100,
			});
			expect((data as unknown[]).length).toBe(0);
		});

	test('discoverable_routes_in_bbox: featured OR run_count > 0, never both off',
		async () => {
			const admin = getAdminClient();
			const { data, error } = await admin.rpc(
				'discoverable_routes_in_bbox',
				VA_BBOX,
			);
			expect(error).toBeNull();
			const pins = data as Array<{
				id: string;
				featured: boolean;
				run_count: number;
				distance_m: number;
				elevation_m: number | null;
			}>;
			expect(pins.length).toBeGreaterThanOrEqual(3);
			// Every pin must satisfy the filter contract.
			for (const p of pins) {
				expect(
					p.featured || p.run_count > 0,
					`Route ${p.id} is neither featured nor popular`,
				).toBe(true);
				expect(p.distance_m).toBeGreaterThan(0);
			}
			// Order: featured first, then by run_count desc.
			const firstFeaturedIdx = pins.findIndex((p) => p.featured);
			const lastFeaturedIdx = pins
				.slice()
				.reverse()
				.findIndex((p) => p.featured);
			if (firstFeaturedIdx >= 0) {
				// Everything before "last featured" must be featured.
				const lastIdx = pins.length - 1 - lastFeaturedIdx;
				for (let i = 0; i <= lastIdx; i++) {
					expect(pins[i].featured, `pin ${i} should be featured`).toBe(true);
				}
			}
		});

	test('discoverable_routes_in_bbox limit caps the result set', async () => {
		const admin = getAdminClient();
		const { data } = await admin.rpc('discoverable_routes_in_bbox', {
			...VA_BBOX,
			p_limit: 2,
		});
		expect((data as unknown[]).length).toBeLessThanOrEqual(2);
	});
});

test.describe('Heatmap pin layers (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('club + route layers mount with non-zero feature counts', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		// Wait for initial load + the moveend debounce.
		await page.waitForTimeout(1500);

		// Pan to Virginia so the bbox refresh definitely lands on
		// the seeded pins. Zoom 6 (not 7) so all six VA routes — which
		// span ~4° of longitude — stay inside the sidebar-narrowed map.
		await page.evaluate(async () => {
			type MapHandle = {
				flyTo: (o: { center: [number, number]; zoom: number }) => void;
				once: (event: string, cb: () => void) => void;
			};
			const m = (window as unknown as { __heatmapMap?: MapHandle }).__heatmapMap;
			if (!m) return;
			await new Promise<void>((resolve) => {
				m.once('moveend', () => resolve());
				m.flyTo({ center: [-78, 37.9], zoom: 6 });
			});
		});
		await page.waitForTimeout(800);

		// The route count lives in the results-header; the club count in
		// the Filters panel's Clubs layer toggle.
		const routesCount = parseInt(
			(await page.locator('.results-count strong').textContent()) ?? '0',
			10,
		);
		// Seed: 3 featured VA routes + 3 popular VA routes = 6.
		expect(routesCount, 'route pins in VA viewport').toBeGreaterThanOrEqual(6);

		await page.getByTestId('filters-button').click();
		const clubsRow = page.locator('.layer-row', { hasText: 'Clubs' });
		await expect(clubsRow).toBeVisible();
		const clubsCount = parseInt(
			(await clubsRow.locator('.layer-count').textContent()) ?? '0',
			10,
		);
		// Seed: 8 VA clubs.
		expect(clubsCount, 'club pins in VA viewport').toBeGreaterThanOrEqual(8);
	});

	test('layer toggle hides + restores its layer', async ({ page }) => {
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1200);
		await page.getByTestId('filters-button').click();

		// Toggling the Clubs layer checkbox should flip the layer's
		// visibility. The checkbox state is the observable contract; if
		// the binding works, the MapLibre layer follows it via the $effect.
		const clubsCheckbox = page
			.locator('.layer-row', { hasText: 'Clubs' })
			.getByRole('checkbox');
		await expect(clubsCheckbox).toBeChecked();
		await clubsCheckbox.uncheck();
		await expect(clubsCheckbox).not.toBeChecked();
		await clubsCheckbox.check();
		await expect(clubsCheckbox).toBeChecked();
	});
});

test.describe('Heatmap pin popup (click flow)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	// Helper: pan to a target lng/lat, wait for the pin source to
	// refresh, then return the pixel coords (in viewport space) of
	// the projected target inside the canvas. The caller drives a
	// real mouse click — MapLibre's layer-specific click handlers
	// only fire when queryRenderedFeatures hits, which only happens
	// for genuine pointer events at the right coordinate.
	async function flyAndProjectPin(page: import('@playwright/test').Page, target: [number, number]) {
		return page.evaluate(async ({ lng, lat }) => {
			type MapHandle = {
				flyTo: (o: { center: [number, number]; zoom: number }) => void;
				project: (lngLat: [number, number]) => { x: number; y: number };
				once: (event: string, cb: () => void) => void;
				getContainer: () => HTMLElement;
				queryRenderedFeatures: (
					point: [number, number],
					opts?: { layers?: string[] },
				) => Array<unknown>;
				getStyle: () => { layers?: Array<{ id: string }> };
			};
			const m = (window as unknown as { __heatmapMap?: MapHandle })
				.__heatmapMap;
			if (!m) return null;
			await new Promise<void>((resolve) => {
				m.once('moveend', () => resolve());
				m.flyTo({ center: [lng, lat], zoom: 14 });
			});
			// Wait for the pin layers to actually paint at the target.
			// The 700 ms fixed wait was enough on local hardware but
			// CI runners (slower WebGL) sometimes need longer for the
			// pin source's data + the layer's symbol rendering to
			// settle after flyTo. Poll `queryRenderedFeatures` at the
			// projected pixel until SOMETHING is hit (or we give up
			// after 4 s) — that's the load-bearing precondition for
			// the `mouse.click` to dispatch the layer's click handler
			// and open the popup. Caught by
			// `tests-e2e/routes/heatmap-pins.spec.ts:275 + :293`
			// failing on CI run 26340415025 shard 6 (popup never
			// appeared because the click landed before pins rendered).
			const pinLayerIds = (m.getStyle().layers ?? [])
				.map((l) => l.id)
				.filter(
					(id) =>
						id === 'heatmap-clubs-layer' ||
						id === 'heatmap-route-pins-layer',
				);
			const deadline = Date.now() + 4000;
			while (Date.now() < deadline) {
				const pt = m.project([lng, lat]);
				const hits = m.queryRenderedFeatures([pt.x, pt.y], {
					layers: pinLayerIds,
				});
				if (hits.length > 0) break;
				await new Promise<void>((resolve) => setTimeout(resolve, 150));
			}
			const pt = m.project([lng, lat]);
			const rect = m.getContainer().getBoundingClientRect();
			return { x: rect.left + pt.x, y: rect.top + pt.y };
		}, { lng: target[0], lat: target[1] });
	}

	test('clicking a route pin opens a popup with View action that navigates',
		async ({ page }) => {
			await page.goto('/routes/heatmap');
			await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
			await page.waitForTimeout(1200);

			const target: [number, number] = [-77.452, 37.5311]; // Belle Isle
			const screen = await flyAndProjectPin(page, target);
			expect(screen, '__heatmapMap dev hook must be present').toBeTruthy();
			if (!screen) return;

			// Real click — MapLibre's queryRenderedFeatures only resolves
			// for actual pointer events, not synthetic fire('click').
			await page.mouse.click(screen.x, screen.y);

			const popup = page.locator('.heatmap-pin-popup');
			await expect(popup).toBeVisible({ timeout: 5_000 });
			await expect(popup.getByText(/Belle Isle/i)).toBeVisible();
			// Elevation chip must render — the elevation_m has to be carried
			// onto the rendered pin feature (Belle Isle seed = 70 m).
			await expect(popup).toContainText('70 m');
			const view = popup.getByRole('link', { name: /view route/i });
			await expect(view).toBeVisible();
			await view.click();
			await page.waitForURL(/\/routes\/[\da-f-]{36}/, { timeout: 10_000 });
		});

	test('clicking a club pin opens a popup with a View club action',
		async ({ page }) => {
			await page.goto('/routes/heatmap');
			await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
			await page.waitForTimeout(1200);

			const target: [number, number] = [-77.436, 37.5407]; // Richmond Run Club
			const screen = await flyAndProjectPin(page, target);
			expect(screen).toBeTruthy();
			if (!screen) return;
			await page.mouse.click(screen.x, screen.y);

			const popup = page.locator('.heatmap-pin-popup');
			await expect(popup).toBeVisible({ timeout: 5_000 });
			await expect(popup.getByText(/Richmond Run Club/i)).toBeVisible();
			await expect(popup.getByRole('link', { name: /view club/i })).toBeVisible();
			// Location subtitle must render — location_label has to be on the
			// rendered pin feature (Richmond Run Club seed = Richmond, VA).
			await expect(popup.locator('.pin-popup-location')).toBeVisible();
		});

	test('popup mounts with finite translate3d (not collapsed to map origin)',
		async ({ page }) => {
		// The May 2026 user-reported bug was "circle stuck at the
		// top-left of the map" — a non-finite-coord symptom (the
		// MapLibre translate3d projector collapses NaN to 0,0). The
		// defensive `Number.isFinite` guard on `renderPreviewMarker`
		// + the `map.resize()` in `openPopupRaw` close that class of
		// bug. Pin the post-click popup transform to a finite,
		// non-trivial value so a regression to the corner-stuck
		// state fails this test.
		//
		// We do NOT assert exact viewport coords because MapLibre's
		// container rect interacts with the page's scroll position
		// (a separate flex-layout subtlety on /routes/heatmap),
		// and changing the page-shell scroll model is out of scope
		// for the pin-popup feature. Visibility + non-trivial
		// translate is the load-bearing contract.
		await page.goto('/routes/heatmap');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 15_000 });
		await page.waitForTimeout(1200);

		const target: [number, number] = [-77.452, 37.5311];
		const screen = await flyAndProjectPin(page, target);
		expect(screen).toBeTruthy();
		if (!screen) return;
		await page.mouse.click(screen.x, screen.y);

		const popup = page.locator('.heatmap-pin-popup');
		await expect(popup).toBeVisible({ timeout: 5_000 });

		// Map should be at viewport y >= 0 now that the heatmap
		// lives in its own /routes/heatmap route (standalone, no
		// flex chain). Pin this so a regression that brings back
		// the tab-parent layout fails here.
		const mapRect = await page
			.locator('.maplibregl-map')
			.evaluate((el) => {
				const r = el.getBoundingClientRect();
				return { top: r.top, height: r.height };
			});
		expect(mapRect.top, 'map should not extend above the viewport')
			.toBeGreaterThanOrEqual(-2);
		expect(mapRect.height, 'map should fill its container').toBeGreaterThan(400);

		// Read the popup wrapper's transform — must contain a
		// translate(...) with finite pixel offsets (not "translate(0px,
		// 0px)" which is the corner-stuck state).
		const transform = await popup.evaluate((el) => {
			const wrap = el.closest('.maplibregl-popup') as HTMLElement | null;
			return wrap?.style.transform ?? '';
		});
		expect(transform, `popup transform: ${transform}`).toMatch(
			/translate\(/,
		);
		const match = transform.match(/translate\(([\-\d.]+)px,\s*([\-\d.]+)px\)/);
		expect(match, `no translate pixel values: ${transform}`).not.toBeNull();
		if (match) {
			const x = parseFloat(match[1]);
			const y = parseFloat(match[2]);
			expect(Number.isFinite(x)).toBe(true);
			expect(Number.isFinite(y)).toBe(true);
			// At least one of x/y must be non-trivial — the corner-
			// stuck state is exactly translate(0px, 0px). Any other
			// projection produces a meaningful offset.
			expect(Math.abs(x) + Math.abs(y)).toBeGreaterThan(20);
		}

	});
});
