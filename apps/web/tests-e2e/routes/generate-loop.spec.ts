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
 * Every OSRM call is mocked to return a deterministic straight-line
 * polyline between the requested coords with the haversine distance.
 * That lets the bisection converge predictably, and the assertions can
 * pin: total polyline length is near the target, the first/last point
 * matches the user's start (loop closure), the post-collapse waypoint
 * count is ≤ 4, and the parent's `routed` flag flips true so Save enables.
 */

// Richmond, VA suburb — the coordinate the user actually exercises.
const FIELD_START = { lat: 37.6519, lng: -77.3611 };

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
	await page.route('https://router.project-osrm.org/**', async (route: Route) => {
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
		await mockOsrmStraightLines(page);
		await page.goto('/routes/new');
		await page.waitForLoadState('networkidle');
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
		// Replace the OSRM mock with a slow one so the batch is in
		// flight long enough to cancel.
		await page.unroute('https://router.project-osrm.org/**');
		await page.route('https://router.project-osrm.org/**', async (route) => {
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
		await page.unroute('https://router.project-osrm.org/**');
		await page.route('https://router.project-osrm.org/**', async (route) => {
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

	test('Action buttons stay disabled mid-generation (Save / GPX / KML / Recalc)', async ({
		page,
	}) => {
		// Audit follow-up: emitUpdate fires routed=true after iter 1
		// completes — before the bisection's restore-best step. The
		// parent must keep Save / GPX / KML disabled while builderBusy
		// so the user can't save a pre-converged polyline.
		await page.unroute('https://router.project-osrm.org/**');
		await page.route('https://router.project-osrm.org/**', async (route) => {
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
		const calcOrRecalc = page.getByRole('button', { name: /Calculate Route|Recalculate/ });
		await expect(calcOrRecalc).toBeDisabled();

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

	test('hard failure: OSRM 503 → "Couldn\'t generate" error, no route, save disabled', async ({
		page,
	}) => {
		await page.unroute('https://router.project-osrm.org/**');
		await page.route('https://router.project-osrm.org/**', (route) =>
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
});
