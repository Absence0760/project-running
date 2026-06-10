import { expect, test, type Page, type Route } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /routes/new — Generate-by-distance feature.
 *
 * The full feature: pick a start, set a target distance, click Generate,
 * watch the bisection iteration converge through 4 attempts, see the
 * scaffolding collapse to 4 anchors, end up with a routed loop the user
 * can Save. Driving every step from canvas pixel clicks is too brittle
 * (MapTiler projection depends on style + zoom + viewport), so these
 * specs invoke the public API via the dev-only `window.__routeBuilder`
 * hook that /routes/new+page.svelte exposes in import.meta.env.DEV.
 *
 * Loop generation (no distinct end pin) goes server-side: the builder POSTs
 * to /api/routes/generate, which tries the graph_cycle sidecar FIRST (the v3
 * graph-cycle generator) and falls back to GraphHopper round_trip, then renders
 * the returned polyline directly. The client sees one {coordinates, distanceM}
 * shape regardless of which engine served it, so we mock that endpoint per test
 * with the shape the engine-under-test would emit. When the endpoint is
 * unavailable (501 unconfigured / 5xx down) the builder falls back to the
 * in-browser OSRM heuristic — exercised by its own test and still used for the
 * point-to-point case (distinct end), which neither loop engine covers.
 *
 * Every OSRM call is mocked to return a deterministic straight-line
 * polyline between the requested coords with the haversine distance.
 * The assertions pin: total polyline length is near the target, the
 * first/last point matches the user's start (loop closure), the
 * post-collapse waypoint count is ≤ 4, and the parent's `routed` flag
 * flips true so Save enables.
 */

// Richmond, VA suburb — the coordinate the user actually exercises.
const FIELD_START = { lat: 37.6519, lng: -77.3611 };

// Match the client OSRM heuristic's calls by PATH, not host: the demo
// (router.project-osrm.org) in CI, but localhost:5000 locally when
// PUBLIC_OSRM_URL is set + the dev server is reused. A host-pinned mock misses
// the latter and the client hits the real engine.
const OSRM_ROUTE = /\/route\/v1\/foot\//;

const TARGETS = [
	{ label: '3.1 mi (5 km)', m: 5000, toleranceM: 1500 },
	{ label: '5 km', m: 5000, toleranceM: 1500 },
	{ label: '10 km', m: 10000, toleranceM: 2500 },
	{ label: 'half marathon', m: 21100, toleranceM: 4500 },
];

/**
 * Mock every OSRM /route/v1/foot call with a straight-line GeoJSON
 * polyline between the requested coords. Returns `code: 'Ok'` so the
 * route builder treats every segment as a successful snap.
 */
async function mockOsrmStraightLines(page: Page) {
	await page.route(OSRM_ROUTE, async (route: Route) => {
		const url = route.request().url();
		const match = url.match(/\/foot\/([^?]+)/);
		if (!match) {
			await route.fulfill({ status: 400, contentType: 'application/json', body: '{}' });
			return;
		}
		const coords = match[1]
			.split(';')
			.map((p) => p.split(',').map(Number) as [number, number]);
		let distance = 0;
		for (let i = 1; i < coords.length; i++) {
			distance += haversineM(
				{ lng: coords[i - 1][0], lat: coords[i - 1][1] },
				{ lng: coords[i][0], lat: coords[i][1] },
			);
		}
		await route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify({
				code: 'Ok',
				routes: [
					{
						geometry: { type: 'LineString', coordinates: coords },
						distance,
					},
				],
				waypoints: coords.map((c) => ({ location: c })),
			}),
		});
	});
}

/**
 * Mock the Open-Meteo elevation API that `recalculateRoute` hits
 * once per successful generation. The runtime call has no client-
 * side timeout, so in a network-isolated CI runner the fetch can
 * hang and pin generateLoop's promise — that's how the route-builder
 * audit landed this in the page-stuck-on-"Calculating route…" state.
 * Returns the right number of zero elevations for the requested
 * coords so the post-call interpolation step doesn't crash on a
 * length mismatch.
 */
async function mockOpenMeteoElevation(page: Page) {
	await page.route('https://api.open-meteo.com/v1/elevation**', async (route: Route) => {
		const url = new URL(route.request().url());
		// `latitude` is a comma-joined list; count by comma + 1, with
		// a sane minimum so an unexpectedly-empty param doesn't return
		// `elevation: []` and crash the interpolation.
		const lat = url.searchParams.get('latitude') ?? '';
		const n = Math.max(1, lat.split(',').filter(Boolean).length);
		await route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify({ elevation: new Array(n).fill(0) }),
		});
	});
}

/**
 * A closed circular loop of perimeter ≈ targetM, starting and ending exactly
 * at `start` — the shape GraphHopper round_trip returns (loop anchored at the
 * start point). Centre is offset north by the radius so `start` is the
 * southernmost point on the circle.
 */
function loopPolyline(
	start: { lat: number; lng: number },
	targetM: number,
	n = 24,
): [number, number][] {
	const r = targetM / (2 * Math.PI);
	const rDeg = r / 111320;
	const cosLat = Math.cos((start.lat * Math.PI) / 180);
	const centerLat = start.lat + rDeg;
	const pts: [number, number][] = [];
	for (let i = 0; i <= n; i++) {
		const a = -Math.PI / 2 + (i / n) * 2 * Math.PI;
		pts.push([start.lng + (Math.cos(a) * rDeg) / cosLat, centerLat + Math.sin(a) * rDeg]);
	}
	// Pin the seam exactly to the start (round_trip starts + ends there).
	pts[0] = [start.lng, start.lat];
	pts[pts.length - 1] = [start.lng, start.lat];
	return pts;
}

/**
 * A real polygonal loop — the shape the graph_cycle sidecar (the v3 generator)
 * returns: a clean cycle traced on the actual foot graph, anchored at the start,
 * NOT a smooth circle. Built as a regular K-gon (default triangle) whose
 * perimeter ≈ targetM, with the first vertex pinned to `start`. Distinct from
 * `loopPolyline` (a 24-gon ≈ circle = the round_trip fallback shape) so the two
 * server paths render visibly different geometry.
 */
function graphCycleLoopPolyline(
	start: { lat: number; lng: number },
	targetM: number,
	k = 3,
): [number, number][] {
	// Regular K-gon side s has perimeter k·s; its circumradius is
	// s / (2·sin(π/k)). Solve for the circumradius that gives perimeter targetM.
	const side = targetM / k;
	const circumradiusM = side / (2 * Math.sin(Math.PI / k));
	const rDeg = circumradiusM / 111320;
	const cosLat = Math.cos((start.lat * Math.PI) / 180);
	// Centre offset so the first vertex lands exactly on `start` (the generator
	// anchors the loop at the start). First vertex due north of centre.
	const centerLat = start.lat - rDeg;
	const pts: [number, number][] = [];
	for (let i = 0; i <= k; i++) {
		const a = -Math.PI / 2 + (i / k) * 2 * Math.PI;
		pts.push([start.lng + (Math.cos(a) * rDeg) / cosLat, centerLat + Math.sin(a) * rDeg]);
	}
	pts[0] = [start.lng, start.lat];
	pts[pts.length - 1] = [start.lng, start.lat];
	return pts;
}

/**
 * Mock the server-side generate endpoint with a real polygonal loop — what the
 * client sees when the graph_cycle sidecar finds a clean cycle on the foot graph
 * (the dense/medium-start happy path). The traced loop has non-trivial enclosed
 * area, unlike the round_trip out-and-back.
 */
async function mockGenerateGraphCycleLoop(page: Page) {
	await page.route('**/api/routes/generate', async (route: Route) => {
		const body = route.request().postDataJSON() as {
			start: { lat: number; lng: number };
			targetDistanceM: number;
		};
		const coordinates = graphCycleLoopPolyline(body.start, body.targetDistanceM);
		let distanceM = 0;
		for (let i = 1; i < coordinates.length; i++) {
			distanceM += haversineM(
				{ lng: coordinates[i - 1][0], lat: coordinates[i - 1][1] },
				{ lng: coordinates[i][0], lat: coordinates[i][1] },
			);
		}
		await route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify({ coordinates, distanceM }),
		});
	});
}

/**
 * Twice-mounted enclosed-area metric (shoelace on a local equirectangular
 * projection, m²) — the same isoperimetric primitive `select.ts#enclosedAreaM2`
 * scores candidates with server-side. Used here to assert the graph-cycle path
 * yields a real loop (non-zero area) and the degenerate fallback yields a
 * near-collinear spur (≈ zero area), without importing server code into the
 * browser context.
 */
function enclosedAreaM2(coords: [number, number][]): number {
	if (coords.length < 4) return 0;
	const lat0 = coords[0][1];
	const mPerDegLat = 111320;
	const mPerDegLng = 111320 * Math.cos((lat0 * Math.PI) / 180);
	let area = 0;
	for (let i = 0; i < coords.length; i++) {
		const [lng1, lat1] = coords[i];
		const [lng2, lat2] = coords[(i + 1) % coords.length];
		area += lng1 * mPerDegLng * (lat2 * mPerDegLat) - lng2 * mPerDegLng * (lat1 * mPerDegLat);
	}
	return Math.abs(area) / 2;
}

/**
 * Mock the server-side generate endpoint with a round_trip-shaped loop near
 * the requested target. Intercepts the POST before it reaches the dev server,
 * so the test is independent of whether GraphHopper is configured.
 */
async function mockGenerateLoop(page: Page) {
	await page.route('**/api/routes/generate', async (route: Route) => {
		const body = route.request().postDataJSON() as {
			start: { lat: number; lng: number };
			targetDistanceM: number;
		};
		const coordinates = loopPolyline(body.start, body.targetDistanceM);
		let distanceM = 0;
		for (let i = 1; i < coordinates.length; i++) {
			distanceM += haversineM(
				{ lng: coordinates[i - 1][0], lat: coordinates[i - 1][1] },
				{ lng: coordinates[i][0], lat: coordinates[i][1] },
			);
		}
		await route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify({ coordinates, distanceM }),
		});
	});
}

function haversineM(
	a: { lng: number; lat: number },
	b: { lng: number; lat: number },
): number {
	const R = 6371000;
	const toRad = (d: number) => (d * Math.PI) / 180;
	const dLat = toRad(b.lat - a.lat);
	const dLng = toRad(b.lng - a.lng);
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const h =
		sinLat * sinLat +
		Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinLng * sinLng;
	return R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/**
 * Wait until /routes/new has mounted the builder + the test hook is
 * live on window. Re-evaluates on a short interval so we don't race
 * the $effect that exposes it.
 */
async function waitForBuilderHook(page: Page) {
	await page.waitForFunction(
		() => typeof (window as unknown as { __routeBuilder?: unknown }).__routeBuilder === 'object',
		null,
		{ timeout: 15_000 },
	);
}

async function generateLoopViaHook(
	page: Page,
	args: {
		targetDistanceM: number;
		start: { lat: number; lng: number };
		end?: { lat: number; lng: number };
	},
): Promise<{
	ok: boolean;
	coordinates: [number, number][];
	waypoints: { lat: number; lng: number }[];
	totalDistanceM: number;
}> {
	return page.evaluate(
		async ({ targetDistanceM, start, end }) => {
			const hook = (
				window as unknown as {
					__routeBuilder: {
						generateLoop: (
							t: number,
							s?: { lat: number; lng: number },
							e?: { lat: number; lng: number },
						) => Promise<boolean>;
						getRouteData: () => {
							waypoints: { lat: number; lng: number }[];
							coordinates: [number, number][];
							elevations: number[];
						};
					};
				}
			).__routeBuilder;
			const ok = await hook.generateLoop(targetDistanceM, start, end);
			const data = hook.getRouteData();
			// Inline haversine sum — keep the spec self-contained.
			let total = 0;
			const R = 6371000;
			const toRad = (d: number) => (d * Math.PI) / 180;
			for (let i = 1; i < data.coordinates.length; i++) {
				const a = data.coordinates[i - 1];
				const b = data.coordinates[i];
				const dLat = toRad(b[1] - a[1]);
				const dLng = toRad(b[0] - a[0]);
				const sl = Math.sin(dLat / 2);
				const sg = Math.sin(dLng / 2);
				const h =
					sl * sl + Math.cos(toRad(a[1])) * Math.cos(toRad(b[1])) * sg * sg;
				total += R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
			}
			return {
				ok,
				coordinates: data.coordinates,
				waypoints: data.waypoints,
				totalDistanceM: total,
			};
		},
		args,
	);
}

test.describe('/routes/new — generate-loop (mocked OSRM)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ page }) => {
		await mockGenerateLoop(page);
		await mockOsrmStraightLines(page);
		await mockOpenMeteoElevation(page);
		await page.goto('/routes/new');
		await expect(page.locator('.maplibregl-map')).toBeVisible({ timeout: 10_000 });
		await waitForBuilderHook(page);
	});

	for (const target of TARGETS) {
		test(`loop @ ${target.label} from (${FIELD_START.lat}, ${FIELD_START.lng}) — distance, closure, anchor count`, async ({
			page,
		}) => {
			const result = await generateLoopViaHook(page, {
				targetDistanceM: target.m,
				start: FIELD_START,
			});

			expect(result.ok).toBe(true);
			expect(result.coordinates.length).toBeGreaterThan(1);

			// Distance lands within tolerance. Wider than the production
			// ±15% acceptance band because the mock's straight-line
			// distance doesn't perfectly track the bisection's expected
			// curve — but a 20-30% spread is still a tight regression
			// guard against accidental scaleFactor / numPoints drift.
			expect(result.totalDistanceM).toBeGreaterThan(target.m - target.toleranceM);
			expect(result.totalDistanceM).toBeLessThan(target.m + target.toleranceM);

			// Polyline starts at the user's coord (selectLoopAnchors
			// pins waypoints[0] to the user-supplied start exactly,
			// and recalculateRoute's per-segment geometry preserves
			// the first point of the first segment).
			const first = result.coordinates[0];
			expect(first[1]).toBeCloseTo(FIELD_START.lat, 4);
			expect(first[0]).toBeCloseTo(FIELD_START.lng, 4);

			// Polyline ENDS at the user's coord too — a true loop.
			const last = result.coordinates[result.coordinates.length - 1];
			expect(last[1]).toBeCloseTo(FIELD_START.lat, 4);
			expect(last[0]).toBeCloseTo(FIELD_START.lng, 4);

			// Post-collapse: scaffolding is gone, ≤ 4 anchors remain.
			expect(result.waypoints.length).toBeLessThanOrEqual(4);
			expect(result.waypoints.length).toBeGreaterThanOrEqual(2);

			// First + last anchors are exactly the user's coord — the
			// collapse preserves the visible green pin location.
			expect(result.waypoints[0].lat).toBe(FIELD_START.lat);
			expect(result.waypoints[0].lng).toBe(FIELD_START.lng);
			expect(result.waypoints[result.waypoints.length - 1].lat).toBe(FIELD_START.lat);
			expect(result.waypoints[result.waypoints.length - 1].lng).toBe(FIELD_START.lng);
		});
	}

	test('falls back to the OSRM heuristic when the generate endpoint is unavailable', async ({
		page,
	}) => {
		// 501 = GraphHopper unconfigured (local dev / a degraded prod). The
		// builder must still produce a loop via the in-browser OSRM heuristic
		// rather than erroring — generate-by-distance survives an engine
		// outage. The OSRM straight-line mock from beforeEach is the fallback.
		await page.unroute('**/api/routes/generate');
		await page.route('**/api/routes/generate', (route) =>
			route.fulfill({
				status: 501,
				contentType: 'application/json',
				body: JSON.stringify({ error: 'route generation is not configured' }),
			}),
		);

		const result = await generateLoopViaHook(page, {
			targetDistanceM: 5000,
			start: FIELD_START,
		});

		expect(result.ok).toBe(true);
		expect(result.coordinates.length).toBeGreaterThan(1);
		expect(result.waypoints.length).toBeLessThanOrEqual(4);
		// Loop closure preserved by the fallback path too.
		const first = result.coordinates[0];
		expect(first[1]).toBeCloseTo(FIELD_START.lat, 4);
		expect(first[0]).toBeCloseTo(FIELD_START.lng, 4);
		const last = result.coordinates[result.coordinates.length - 1];
		expect(last[1]).toBeCloseTo(FIELD_START.lat, 4);
		expect(last[0]).toBeCloseTo(FIELD_START.lng, 4);
	});

	test('graph-cycle path: clean foot-graph loop renders as a real loop near target', async ({
		page,
	}) => {
		// When the graph_cycle sidecar is configured the server tries it FIRST and
		// returns the clean cycle it traced on the real foot graph. The builder must
		// render that as a closed loop near the target with the same post-collapse
		// anchor shape as the round_trip path — and it must be a REAL loop
		// (non-trivial enclosed area), not an out-and-back.
		await page.unroute('**/api/routes/generate');
		await mockGenerateGraphCycleLoop(page);

		const result = await generateLoopViaHook(page, {
			targetDistanceM: 5000,
			start: FIELD_START,
		});

		expect(result.ok).toBe(true);
		expect(result.coordinates.length).toBeGreaterThan(1);

		// Distance lands near target. Same ±1500 m band the circle-shaped TARGETS
		// tests use: the builder collapses the returned loop to ≤4 anchors and
		// re-routes them through the straight-line OSRM mock, so the rendered
		// chord total under-runs the K-gon perimeter — a band wider than the
		// production ±15% absorbs the mock's straight-line re-trace while still
		// pinning the loop to the requested 5 km.
		expect(result.totalDistanceM).toBeGreaterThan(5000 - 1500);
		expect(result.totalDistanceM).toBeLessThan(5000 + 1500);

		// Loop closure: first + last coordinate are the user's start.
		const first = result.coordinates[0];
		expect(first[1]).toBeCloseTo(FIELD_START.lat, 4);
		expect(first[0]).toBeCloseTo(FIELD_START.lng, 4);
		const last = result.coordinates[result.coordinates.length - 1];
		expect(last[1]).toBeCloseTo(FIELD_START.lat, 4);
		expect(last[0]).toBeCloseTo(FIELD_START.lng, 4);

		// Post-collapse anchor shape matches the round_trip path (≤ 4).
		expect(result.waypoints.length).toBeLessThanOrEqual(4);
		expect(result.waypoints.length).toBeGreaterThanOrEqual(2);

		// It is a genuine loop: the rendered polyline encloses real area, the
		// defining difference from an out-and-back. A ~3.6 km re-traced triangle
		// still encloses hundreds of thousands of m²; a spur encloses ~0. The
		// floor sits well below the loop area and well above spur noise.
		expect(enclosedAreaM2(result.coordinates)).toBeGreaterThan(300_000);
	});

	test('loop-poor: graph-cycle falls through to the round_trip loop', async ({
		page,
	}) => {
		// Server-side, a loop-poor start makes the graph_cycle sidecar return
		// found:false (no clean cycle on the foot graph), and the handler falls
		// through to the round_trip out-and-back. The client sees a single 200
		// either way — what changes is the SHAPE. Mock the endpoint to emit the
		// round_trip circle (the fall-through result) and assert the builder still
		// renders a closed loop near target. The server-side null→round_trip
		// decision itself is unit-pinned in graph_cycle.test.ts ("falls back to
		// round_trip when graph-cycle is loop-poor").
		await page.unroute('**/api/routes/generate');
		await mockGenerateLoop(page);

		const result = await generateLoopViaHook(page, {
			targetDistanceM: 5000,
			start: FIELD_START,
		});

		expect(result.ok).toBe(true);
		// Same ±1500 m re-trace band as the graph-cycle test above (and the TARGETS
		// circle tests) — the collapse + straight-line re-route shrinks the
		// rendered loop below the mocked perimeter.
		expect(result.totalDistanceM).toBeGreaterThan(5000 - 1500);
		expect(result.totalDistanceM).toBeLessThan(5000 + 1500);

		const first = result.coordinates[0];
		expect(first[1]).toBeCloseTo(FIELD_START.lat, 4);
		expect(first[0]).toBeCloseTo(FIELD_START.lng, 4);
		const last = result.coordinates[result.coordinates.length - 1];
		expect(last[1]).toBeCloseTo(FIELD_START.lat, 4);
		expect(last[0]).toBeCloseTo(FIELD_START.lng, 4);
		expect(result.waypoints.length).toBeLessThanOrEqual(4);
	});

	test('loop-poor shortfall: offers the achievable distance and applies it on click', async ({
		page,
	}) => {
		// Simulate a road network that can't form a loop at the target: return a
		// loop ~22% short, below the ±15% accept band. The warning must carry an
		// actionable "use the achievable distance" button (not a dead-end), and
		// clicking it aligns the target to the drawn route + clears the warning.
		await page.unroute('**/api/routes/generate');
		await page.route('**/api/routes/generate', async (route: Route) => {
			const body = route.request().postDataJSON() as {
				start: { lat: number; lng: number };
				targetDistanceM: number;
			};
			const coordinates = loopPolyline(body.start, body.targetDistanceM * 0.78);
			let distanceM = 0;
			for (let i = 1; i < coordinates.length; i++) {
				distanceM += haversineM(
					{ lng: coordinates[i - 1][0], lat: coordinates[i - 1][1] },
					{ lng: coordinates[i][0], lat: coordinates[i][1] },
				);
			}
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ coordinates, distanceM }),
			});
		});

		// Open the distance panel so the Generate button (its label carries the
		// current target) is visible to assert the applied change against.
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		const genBtn = page.getByRole('button', { name: /Generate .* loop/i });
		const targetBefore = ((await genBtn.textContent()) ?? '').trim();

		const result = await generateLoopViaHook(page, { targetDistanceM: 5000, start: FIELD_START });
		expect(result.ok).toBe(true);

		// Shortfall warning + the actionable button both appear.
		const banner = page.locator('.routing-error.routing-warning').first();
		await expect(banner).toBeVisible({ timeout: 5_000 });
		await expect(banner).toContainText(/shorter than/i);
		const useBtn = page.getByRole('button', { name: /instead/i });
		await expect(useBtn).toBeVisible();

		// Applying it clears the warning + action and re-targets to the
		// achievable distance (the Generate-button label changes).
		await useBtn.click();
		await expect(banner).toBeHidden();
		await expect(useBtn).toBeHidden();
		await expect(genBtn).not.toHaveText(targetBefore);
	});

	test('over-target shortfall: warns "longer than" + the action retargets upward', async ({
		page,
	}) => {
		// Mirror of the "shorter than" shortfall, for the opposite branch:
		// a road network that overshoots. Return a loop 40% LONGER than the
		// target (well outside the ±15% accept band). The warning must read
		// "longer than" and the actionable button must retarget UP to the
		// achievable distance.
		await page.unroute('**/api/routes/generate');
		await page.route('**/api/routes/generate', async (route: Route) => {
			const body = route.request().postDataJSON() as {
				start: { lat: number; lng: number };
				targetDistanceM: number;
			};
			const coordinates = loopPolyline(body.start, body.targetDistanceM * 1.4);
			let distanceM = 0;
			for (let i = 1; i < coordinates.length; i++) {
				distanceM += haversineM(
					{ lng: coordinates[i - 1][0], lat: coordinates[i - 1][1] },
					{ lng: coordinates[i][0], lat: coordinates[i][1] },
				);
			}
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ coordinates, distanceM }),
			});
		});

		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		const result = await generateLoopViaHook(page, { targetDistanceM: 5000, start: FIELD_START });
		expect(result.ok).toBe(true);
		// Sanity: the rendered loop really is over target so "longer" is correct.
		expect(result.totalDistanceM).toBeGreaterThan(5000 * 1.15);

		const banner = page.locator('.routing-error.routing-warning').first();
		await expect(banner).toBeVisible({ timeout: 5_000 });
		await expect(banner).toContainText(/longer than/i);

		const useBtn = page.getByRole('button', { name: /instead/i });
		await expect(useBtn).toBeVisible();
		await useBtn.click();
		await expect(banner).toBeHidden();
		await expect(useBtn).toBeHidden();
	});

	test('shortfall action retargets to the ACHIEVED distance (numeric, not just "changed")', async ({
		page,
	}) => {
		// The existing shortfall test only asserts the Generate label
		// changed. Pin the math: after "use X instead", the new target must
		// equal the drawn route's distance (the sidebar stat) — that's the
		// entire point of the affordance. A unit/rounding bug (km vs metres,
		// mi vs km) would surface as a large mismatch here.
		await page.unroute('**/api/routes/generate');
		await page.route('**/api/routes/generate', async (route: Route) => {
			const body = route.request().postDataJSON() as {
				start: { lat: number; lng: number };
				targetDistanceM: number;
			};
			const coordinates = loopPolyline(body.start, body.targetDistanceM * 0.72);
			let distanceM = 0;
			for (let i = 1; i < coordinates.length; i++) {
				distanceM += haversineM(
					{ lng: coordinates[i - 1][0], lat: coordinates[i - 1][1] },
					{ lng: coordinates[i][0], lat: coordinates[i][1] },
				);
			}
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ coordinates, distanceM }),
			});
		});

		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		await generateLoopViaHook(page, { targetDistanceM: 5000, start: FIELD_START });

		// The drawn-route distance shown in the sidebar stat (user's unit).
		const statValue = page.locator('.builder-stat-value').first();
		const statLabel = page.locator('.builder-stat-label').first();
		const drawn = parseFloat((await statValue.textContent()) ?? '0');
		const unit = ((await statLabel.textContent()) ?? '').trim();

		await page.getByRole('button', { name: /instead/i }).click();

		// The Generate button label now carries the retargeted distance.
		const genBtn = page.getByRole('button', { name: /Generate .* (loop|route)/i });
		const label = (await genBtn.textContent()) ?? '';
		const m = label.match(/([\d.]+)\s*(mi|km)/);
		expect(m, `Generate label "${label}" should carry a distance`).not.toBeNull();
		const retargeted = parseFloat(m![1]);
		expect(m![2]).toBe(unit);
		// New target == drawn distance, within the 100 m quantization +
		// 1-decimal display rounding of the retarget (≈ 0.15 of either unit).
		expect(Math.abs(retargeted - drawn)).toBeLessThan(0.15);
	});

	test('dismissing the shortfall banner clears it WITHOUT changing the target', async ({
		page,
	}) => {
		// The banner's X (dismiss) must drop both the warning and the
		// shortfall action, but — unlike "use X instead" — leave the
		// target untouched so the user can re-Generate at the same distance.
		await page.unroute('**/api/routes/generate');
		await page.route('**/api/routes/generate', async (route: Route) => {
			const body = route.request().postDataJSON() as {
				start: { lat: number; lng: number };
				targetDistanceM: number;
			};
			const coordinates = loopPolyline(body.start, body.targetDistanceM * 0.72);
			let distanceM = 0;
			for (let i = 1; i < coordinates.length; i++) {
				distanceM += haversineM(
					{ lng: coordinates[i - 1][0], lat: coordinates[i - 1][1] },
					{ lng: coordinates[i][0], lat: coordinates[i][1] },
				);
			}
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ coordinates, distanceM }),
			});
		});

		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		const genBtn = page.getByRole('button', { name: /Generate .* (loop|route)/i });
		const targetBefore = ((await genBtn.textContent()) ?? '').trim();

		await generateLoopViaHook(page, { targetDistanceM: 5000, start: FIELD_START });
		const banner = page.locator('.routing-error.routing-warning').first();
		await expect(banner).toBeVisible({ timeout: 5_000 });

		// Dismiss via the X — NOT the "use X instead" action.
		await page.getByRole('button', { name: /dismiss/i }).click();
		await expect(banner).toBeHidden();
		await expect(page.getByRole('button', { name: /instead/i })).toBeHidden();
		// Target is unchanged.
		await expect(genBtn).toHaveText(targetBefore);
	});

	test('Generate button label switches from "loop" to "route" once an end point is set', async ({
		page,
	}) => {
		// handleGenerateLoop passes the page's endPoint through to the
		// builder; the button copy must follow — "Generate X loop" with no
		// end (round-trip), "Generate X route" once a distinct end is set
		// (point-to-point). Drive page state via the dev hook.
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();
		await expect(page.getByRole('button', { name: /Generate .* loop/i })).toBeVisible();

		await page.evaluate(() => {
			(
				window as unknown as {
					__routeBuilderPage: {
						setEndPoint: (p: { lat: number; lng: number } | null) => void;
					};
				}
			).__routeBuilderPage.setEndPoint({ lat: 37.69, lng: -77.36 });
		});

		await expect(page.getByRole('button', { name: /Generate .* route/i })).toBeVisible();
		await expect(page.getByRole('button', { name: /Generate .* loop/i })).toHaveCount(0);
	});

	test('endAt within NEAR_POINT_M of start collapses to a true loop (close == start)', async ({
		page,
	}) => {
		// ~11m offset — well within the NEAR_POINT_M=50 shortcut.
		const nearEnd = { lat: FIELD_START.lat - 0.0001, lng: FIELD_START.lng };
		const result = await generateLoopViaHook(page, {
			targetDistanceM: 5000,
			start: FIELD_START,
			end: nearEnd,
		});

		expect(result.ok).toBe(true);
		const last = result.coordinates[result.coordinates.length - 1];
		// Pins exactly at start, NOT at the slightly-offset endAt.
		expect(last[1]).toBe(FIELD_START.lat);
		expect(last[0]).toBe(FIELD_START.lng);
	});

	test('sequential generates from the same start do not trample state', async ({ page }) => {
		// Reproducer for a class of bug the audit chased: a previous
		// run's waypoints/markers/polyline leaking into the next call.
		const a = await generateLoopViaHook(page, {
			targetDistanceM: 5000,
			start: FIELD_START,
		});
		expect(a.ok).toBe(true);
		const aDistance = a.totalDistanceM;
		const aWaypointCount = a.waypoints.length;

		const b = await generateLoopViaHook(page, {
			targetDistanceM: 10000,
			start: FIELD_START,
		});
		expect(b.ok).toBe(true);
		// Second generate produces a longer route (target doubled);
		// confirms it actually re-ran rather than returning stale.
		expect(b.totalDistanceM).toBeGreaterThan(aDistance);
		// Anchor count: same shape (≤ 4), not accumulated.
		expect(b.waypoints.length).toBeLessThanOrEqual(4);
		expect(b.waypoints.length).toBeGreaterThanOrEqual(aWaypointCount - 1); // tolerant
	});

	test('save button enables after a successful generate', async ({ page }) => {
		await generateLoopViaHook(page, { targetDistanceM: 5000, start: FIELD_START });
		// Provide a name so canSave's `routeName.trim().length > 0`
		// half of the gate is satisfied.
		await page.evaluate(() => {
			// The Save button is gated by both `routed` (from generate)
			// and `routeName`. Open the save modal to surface the name
			// field, fill it, then assert.
		});
		// Save button without name is disabled because the modal hasn't
		// been opened — but the in-toolbar Save Route button gates on
		// `routed` only via canSave's `routed &&`. Routed flipped true
		// when the generate awaited resolved with ok=true.
		await expect(page.getByRole('button', { name: /Save Route/ })).toBeEnabled({
			timeout: 5_000,
		});
	});

	test('sidebar distance stat reflects the generated route distance', async ({ page }) => {
		// The sidebar's "X.XX mi/km" stat reads from coordinates via
		// emitUpdate → onupdate callback. After generate, the value
		// should match the polyline's haversine sum in the user's
		// preferred unit. Read the unit label rather than assuming km
		// — USER_A's seed is mile-mode and the spec needs to work
		// across both preferences.
		const result = await generateLoopViaHook(page, {
			targetDistanceM: 5000,
			start: FIELD_START,
		});
		const statValue = page.locator('.builder-stat-value').first();
		const statLabel = page.locator('.builder-stat-label').first();
		const shown = parseFloat((await statValue.textContent()) ?? '0');
		const unit = ((await statLabel.textContent()) ?? '').trim();
		const expected =
			unit === 'mi' ? result.totalDistanceM / 1609.344 : result.totalDistanceM / 1000;
		// 5% tolerance absorbs the 2-decimal rounding in toFixed(2).
		expect(Math.abs(shown - expected)).toBeLessThan(expected * 0.05);
	});

	test('point-to-point: distant endAt keeps the polyline ending at endAt, not start', async ({
		page,
	}) => {
		// 5km north of start — well outside NEAR_POINT_M.
		const distantEnd = { lat: FIELD_START.lat + 0.045, lng: FIELD_START.lng };
		const result = await generateLoopViaHook(page, {
			targetDistanceM: 5000,
			start: FIELD_START,
			end: distantEnd,
		});

		expect(result.ok).toBe(true);
		// First point pinned to start, last point pinned to endAt.
		const first = result.coordinates[0];
		expect(first[1]).toBeCloseTo(FIELD_START.lat, 4);
		expect(first[0]).toBeCloseTo(FIELD_START.lng, 4);
		const last = result.coordinates[result.coordinates.length - 1];
		expect(last[1]).toBeCloseTo(distantEnd.lat, 4);
		expect(last[0]).toBeCloseTo(distantEnd.lng, 4);
	});

	test('undo after a generated loop pops the closing pin AND the last interior pin', async ({
		page,
	}) => {
		// undoWaypoint has a loop-aware branch: when the popped waypoint was
		// the closing pin (≈ the start), the remaining sequence is a half-
		// loop that wouldn't route sensibly, so it pops one more. Pin that
		// two-for-one behaviour (Ctrl+Z right after Generate).
		const r = await generateLoopViaHook(page, { targetDistanceM: 5000, start: FIELD_START });
		expect(r.ok).toBe(true);
		const n = r.waypoints.length;
		expect(n).toBeGreaterThanOrEqual(3);

		await page.locator('.toolbar-group .btn', { hasText: 'Undo' }).click();

		const wp = await page.evaluate(
			() =>
				(
					window as unknown as {
						__routeBuilder: { getRouteData: () => { waypoints: { lat: number; lng: number }[] } };
					}
				).__routeBuilder.getRouteData().waypoints,
		);
		// First pop removes the closing pin; because it sat on the start and
		// >= 2 waypoints remain, a second pop fires → n - 2.
		expect(wp.length).toBe(n - 2);
	});

	test('out & back on a generated LOOP reverses direction without doubling the pins', async ({
		page,
	}) => {
		// outAndBack has two branches. The non-loop branch appends the
		// reversed interior (point-to-point doubles); the LOOP branch (start
		// ≈ end, the generate-loop shape) instead reverses the interior in
		// place, so the pin count is UNCHANGED. The builder.spec covers the
		// doubling branch; this pins the loop branch.
		const r = await generateLoopViaHook(page, { targetDistanceM: 5000, start: FIELD_START });
		expect(r.ok).toBe(true);
		const n = r.waypoints.length;
		expect(n).toBeGreaterThanOrEqual(3);

		await page.locator('.toolbar-group .btn', { hasText: 'Out & back' }).click();

		const wp = await page.evaluate(
			() =>
				(
					window as unknown as {
						__routeBuilder: { getRouteData: () => { waypoints: { lat: number; lng: number }[] } };
					}
				).__routeBuilder.getRouteData().waypoints,
		);
		// Reversed in place — same count, still a closed loop.
		expect(wp.length).toBe(n);
		expect(wp[wp.length - 1].lat).toBeCloseTo(wp[0].lat, 9);
		expect(wp[wp.length - 1].lng).toBeCloseTo(wp[0].lng, 9);
	});

	test('rejects invalid targetDistanceM (NaN, 0, negative, absurd)', async ({ page }) => {
		// Drive the public API with each invalid input and assert
		// generateLoop returns false without mutating the route.
		const cases = [Number.NaN, 0, -1000, Number.POSITIVE_INFINITY, 1_000_001];
		for (const target of cases) {
			const result = await page.evaluate(
				async ({ t, s }) => {
					const hook = (
						window as unknown as {
							__routeBuilder: {
								generateLoop: (
									t: number,
									s?: { lat: number; lng: number },
								) => Promise<boolean>;
								getRouteData: () => { coordinates: [number, number][] };
							};
						}
					).__routeBuilder;
					const ok = await hook.generateLoop(t, s);
					return { ok, len: hook.getRouteData().coordinates.length };
				},
				{ t: target, s: FIELD_START },
			);
			expect(result.ok, `target ${target} should be rejected`).toBe(false);
		}
	});

	test('rejects pre-zoom call when no start is provided', async ({ page }) => {
		// generateLoop called with NO start AND zoom < 6 must refuse
		// with the pan-first message. Default map zoom on /routes/new
		// is 2 (geolocation denied in test) — well below 6.
		const result = await page.evaluate(async () => {
			const hook = (
				window as unknown as {
					__routeBuilder: { generateLoop: (t: number) => Promise<boolean> };
				}
			).__routeBuilder;
			return await hook.generateLoop(5000);
		});
		expect(result).toBe(false);
		const banner = page.locator('.routing-error').first();
		await expect(banner).toBeVisible({ timeout: 5_000 });
		await expect(banner).toContainText(/Pan to your area|pick a start/i);
	});

	test('Cancel mid-generation aborts the in-flight batch', async ({ page }) => {
		// Loop generation goes to the server endpoint first; make it slow so
		// the request is in flight long enough to cancel. The post-fetch
		// routeVersion guard in generateLoopFromServer bails the moment the
		// cancel lands.
		await page.unroute('**/api/routes/generate');
		await page.route('**/api/routes/generate', async (route) => {
			await new Promise((r) => setTimeout(r, 3000));
			await route.fulfill({ status: 503, body: '{}' });
		});

		// Kick off generate (don't await — we want to cancel mid-flight).
		const generatePromise = page.evaluate(({ s }) => {
			const hook = (
				window as unknown as {
					__routeBuilder: {
						generateLoop: (
							t: number,
							s?: { lat: number; lng: number },
						) => Promise<boolean>;
					};
				}
			).__routeBuilder;
			return hook.generateLoop(5000, s);
		}, { s: FIELD_START });

		// Give the iteration a moment to enter the first OSRM await.
		await page.waitForTimeout(500);

		// Bump routeVersion via cancelGeneration().
		await page.evaluate(() => {
			(
				window as unknown as {
					__routeBuilder: { cancelGeneration: () => void };
				}
			).__routeBuilder.cancelGeneration();
		});

		const ok = await generatePromise;
		expect(ok).toBe(false);
	});

	test('Cancel restores pre-generate waypoints (no scaffolding left behind)', async ({
		page,
	}) => {
		// Pre-state for this test: drop two manual waypoints first via
		// the test hook (calling addWaypoint), then generate. Cancel
		// mid-iteration. The restore in generateLoop's finally should
		// repopulate the two manual waypoints, NOT leave the 8
		// scaffolding pins (mostly invisible due to display:none).
		await page.unroute('**/api/routes/generate');
		await page.route('**/api/routes/generate', async (route) => {
			await new Promise((r) => setTimeout(r, 3000));
			await route.fulfill({ status: 503, body: '{}' });
		});

		// Drop two manual waypoints via the hook.
		await page.evaluate(({ a, b }) => {
			const hook = (
				window as unknown as {
					__routeBuilder: {
						addWaypoint: (p: { lat: number; lng: number }) => void;
					};
				}
			).__routeBuilder;
			hook.addWaypoint(a);
			hook.addWaypoint(b);
		}, {
			a: { lat: FIELD_START.lat, lng: FIELD_START.lng },
			b: { lat: FIELD_START.lat + 0.01, lng: FIELD_START.lng + 0.01 },
		});

		const before = await page.evaluate(() => {
			return (
				window as unknown as {
					__routeBuilder: { getRouteData: () => { waypoints: unknown[] } };
				}
			).__routeBuilder.getRouteData().waypoints.length;
		});
		expect(before).toBe(2);

		// Kick off generate (don't await — cancel mid-flight).
		const generatePromise = page.evaluate(({ s }) => {
			return (
				window as unknown as {
					__routeBuilder: {
						generateLoop: (
							t: number,
							s?: { lat: number; lng: number },
						) => Promise<boolean>;
					};
				}
			).__routeBuilder.generateLoop(5000, s);
		}, { s: FIELD_START });

		await page.waitForTimeout(500);

		// Cancel mid-batch.
		await page.evaluate(() => {
			(
				window as unknown as {
					__routeBuilder: { cancelGeneration: () => void };
				}
			).__routeBuilder.cancelGeneration();
		});

		const ok = await generatePromise;
		expect(ok).toBe(false);

		// Pre-state restored: still the two manual waypoints, not the
		// 8 scaffolding entries the iteration set.
		const after = await page.evaluate(() => {
			return (
				window as unknown as {
					__routeBuilder: { getRouteData: () => { waypoints: unknown[] } };
				}
			).__routeBuilder.getRouteData().waypoints.length;
		});
		expect(after).toBe(2);
	});

	test('Action buttons stay disabled mid-generation (Save / GPX / KML)', async ({
		page,
	}) => {
		// Audit follow-up: emitUpdate fires routed=true after iter 1
		// completes — before the bisection's restore-best step. The
		// parent must keep Save / GPX / KML disabled while builderBusy
		// so the user can't save a pre-converged polyline.
		await page.unroute('**/api/routes/generate');
		await page.route('**/api/routes/generate', async (route) => {
			await new Promise((r) => setTimeout(r, 2000));
			await route.fulfill({ status: 503, body: '{}' });
		});

		// Start generate, don't await.
		const generatePromise = page.evaluate(({ s }) => {
			return (
				window as unknown as {
					__routeBuilder: {
						generateLoop: (
							t: number,
							s?: { lat: number; lng: number },
						) => Promise<boolean>;
					};
				}
			).__routeBuilder.generateLoop(5000, s);
		}, { s: FIELD_START });

		// Wait for the busy state to land — the spinner is the most
		// reliable signal (Cancel button only lives inside the
		// distance-target panel which our hook-driven call never
		// opened).
		await expect(page.locator('.routing-indicator')).toBeVisible({ timeout: 5_000 });

		// All action buttons should be disabled while builderBusy=true.
		await expect(page.getByRole('button', { name: /Save Route/ })).toBeDisabled();
		await expect(page.getByRole('button', { name: 'GPX', exact: true })).toBeDisabled();
		await expect(page.getByRole('button', { name: 'KML', exact: true })).toBeDisabled();

		// Cancel via the hook (the button is hidden because the panel
		// isn't open in this flow).
		await page.evaluate(() => {
			(
				window as unknown as {
					__routeBuilder: { cancelGeneration: () => void };
				}
			).__routeBuilder.cancelGeneration();
		});
		await generatePromise;
	});

	test('hard failure: server + OSRM 503 → "Couldn\'t generate" error, no route, save disabled', async ({
		page,
	}) => {
		// Server generation down AND the OSRM fallback also failing — the
		// builder must surface its generation-specific error, not silently
		// ship an empty route.
		await page.unroute('**/api/routes/generate');
		await page.route('**/api/routes/generate', (route) => route.fulfill({ status: 503, body: '{}' }));
		await page.unroute(OSRM_ROUTE);
		await page.route(OSRM_ROUTE, (route) =>
			route.fulfill({ status: 503, body: '{}' }),
		);

		const result = await generateLoopViaHook(page, {
			targetDistanceM: 5000,
			start: FIELD_START,
		});

		expect(result.ok).toBe(false);
		expect(result.coordinates.length).toBe(0);

		const banner = page.locator('.routing-error').first();
		await expect(banner).toBeVisible({ timeout: 10_000 });
		await expect(banner).toContainText(/Couldn't generate/i);

		await expect(page.getByRole('button', { name: /Save Route/ })).toBeDisabled();
	});

	test('keyboard coordinate entry sets the start point without a map tap (WCAG 2.1.1)', async ({
		page
	}) => {
		// audit-findings 2026-05-30 High [accessibility]: picking a start
		// was pointer-only. A keyboard user types lat/lng + Set start.
		await page.getByRole('button', { name: /Generate a route by distance/ }).click();

		await page.getByLabel('Start latitude').fill(String(FIELD_START.lat));
		await page.getByLabel('Start longitude').fill(String(FIELD_START.lng));
		await page.getByRole('button', { name: 'Set start' }).click();

		// The start label now reflects the typed coordinate (no map click).
		await expect(page.locator('.point-set').first()).toContainText('37.6519, -77.3611');

		// Invalid input surfaces an accessible error instead of setting a point.
		await page.getByLabel('End latitude').fill('999');
		await page.getByLabel('End longitude').fill('0');
		await page.getByRole('button', { name: 'Set end' }).click();
		await expect(page.locator('.coord-error[role="alert"]')).toBeVisible();
	});
});
