import assert from 'node:assert/strict';
import { test } from 'node:test';

import { buildOsrmLoopUrl, generatePolygonLoop, parseOsrmLoop } from './loop_generate';
import { handleGenerate } from './handler';
import type { Fetcher } from './graphhopper';

const OSRM = 'http://osrm.local';
const GH = 'http://gh.local';

/// A square loop centred at (cx,cy) with half-side `half` degrees — encloses
/// real area, so it clears the spur floor.
function squareLoop(cx: number, cy: number, half: number): [number, number][] {
	return [
		[cx - half, cy - half],
		[cx + half, cy - half],
		[cx + half, cy + half],
		[cx - half, cy + half],
		[cx - half, cy - half],
	];
}

/// A collinear out-and-back — zero enclosed area, the loop-poor failure mode the
/// spur floor must reject.
function spurLoop(cx: number, cy: number, len: number): [number, number][] {
	return [
		[cx, cy],
		[cx + len, cy],
		[cx + 2 * len, cy],
		[cx + len, cy],
		[cx, cy],
	];
}

function osrmResponse(
	coords: [number, number][],
	distanceM: number,
	snaps: number[],
): Response {
	return new Response(
		JSON.stringify({
			code: 'Ok',
			waypoints: snaps.map((d) => ({ distance: d })),
			routes: [{ distance: distanceM, geometry: { type: 'LineString', coordinates: coords } }],
		}),
		{ status: 200, headers: { 'content-type': 'application/json' } },
	);
}

function ghResponse(coords: [number, number][], distanceM: number): Response {
	return new Response(
		JSON.stringify({ paths: [{ distance: distanceM, points: { coordinates: coords } }] }),
		{ status: 200, headers: { 'content-type': 'application/json' } },
	);
}

// A square whose perimeter ≈ 5000 m at the equator: side 1250 m → half-side
// 625 m → 625/111320 ≈ 0.005614°.
const SQ_HALF = 625 / 111320;

// --- parse + url ---

test('buildOsrmLoopUrl closes the loop in lng,lat order on the foot profile', () => {
	const url = buildOsrmLoopUrl(`${OSRM}/`, { lat: 38.88, lng: -77.09 }, [
		{ lat: 38.89, lng: -77.08 },
	]);
	assert.match(url, /\/route\/v1\/foot\//);
	const coordsPart = url.split('/foot/')[1].split('?')[0];
	const pts = coordsPart.split(';');
	assert.equal(pts.length, 3, 'start + 1 via + start');
	assert.equal(pts[0], '-77.09,38.88');
	assert.equal(pts[2], '-77.09,38.88', 'closed: last == first');
	assert.match(url, /geometries=geojson/);
	assert.match(url, /overview=full/);
});

test('parseOsrmLoop extracts geometry, distance, and the farthest snap', () => {
	const c = parseOsrmLoop({
		code: 'Ok',
		waypoints: [{ distance: 3 }, { distance: 41 }, { distance: 12 }],
		routes: [{ distance: 4982, geometry: { coordinates: squareLoop(0, 0, 0.005) } }],
	});
	assert.ok(c);
	assert.equal(c.distanceM, 4982);
	assert.equal(c.coordinates.length, 5);
	assert.equal(c.maxSnapM, 41);
});

test('parseOsrmLoop returns null on a non-Ok / empty response', () => {
	assert.equal(parseOsrmLoop({ code: 'NoRoute', routes: [] }), null);
	assert.equal(parseOsrmLoop({ code: 'Ok', routes: [] }), null);
	assert.equal(parseOsrmLoop(null), null);
	assert.equal(
		parseOsrmLoop({ code: 'Ok', routes: [{ distance: 1, geometry: { coordinates: [] } }] }),
		null,
	);
});

// --- generatePolygonLoop ---

test('generatePolygonLoop returns null when OSRM is unconfigured', async () => {
	const fetcher: Fetcher = async () => {
		throw new Error('should not be called');
	};
	const got = await generatePolygonLoop({ lat: 0, lng: 0 }, 5000, fetcher, { osrmUrl: undefined });
	assert.equal(got, null);
});

test('generatePolygonLoop returns a real loop when one clears the bar', async () => {
	const fetcher: Fetcher = async () => osrmResponse(squareLoop(0, 0, SQ_HALF), 5000, [5, 5, 5, 5]);
	const got = await generatePolygonLoop({ lat: 0, lng: 0 }, 5000, fetcher, { osrmUrl: OSRM });
	assert.ok(got);
	assert.equal(got.distanceM, 5000);
	assert.ok(got.coordinates.length >= 4);
});

test('generatePolygonLoop returns null at a loop-poor start (all spurs)', async () => {
	const fetcher: Fetcher = async () => osrmResponse(spurLoop(0, 0, 0.02), 5000, [5, 5, 5, 5]);
	const got = await generatePolygonLoop({ lat: 0, lng: 0 }, 5000, fetcher, { osrmUrl: OSRM });
	assert.equal(got, null);
});

test('generatePolygonLoop rejects loops whose via-points snapped too far', async () => {
	// A perfect square shape, but every waypoint snapped 400 m > the 250 m bar.
	const fetcher: Fetcher = async () =>
		osrmResponse(squareLoop(0, 0, SQ_HALF), 5000, [400, 400, 400, 400]);
	const got = await generatePolygonLoop({ lat: 0, lng: 0 }, 5000, fetcher, { osrmUrl: OSRM });
	assert.equal(got, null);
});

test('generatePolygonLoop tolerates individual placement failures', async () => {
	let n = 0;
	const fetcher: Fetcher = async () => {
		n++;
		// Every other call fails outright; survivors are clean squares.
		if (n % 2 === 0) return new Response('down', { status: 503 });
		return osrmResponse(squareLoop(0, 0, SQ_HALF), 5000, [5, 5, 5, 5]);
	};
	const got = await generatePolygonLoop({ lat: 0, lng: 0 }, 5000, fetcher, { osrmUrl: OSRM });
	assert.ok(got, 'a usable loop survives partial failures');
});

// --- handler integration: polygon-first, round_trip fallback ---

const OSRM_AND_GH = { graphhopperUrl: GH, osrmUrl: OSRM };

function routeByEngine(onOsrm: () => Response, onGh: () => Response): Fetcher {
	return async (url) => (url.includes('/route/v1/foot/') ? onOsrm() : onGh());
}

test('handleGenerate prefers the polygon loop when OSRM yields a real one', async () => {
	let ghCalled = false;
	const fetcher = routeByEngine(
		() => osrmResponse(squareLoop(0, 0, SQ_HALF), 5000, [5, 5, 5, 5]),
		() => {
			ghCalled = true;
			return ghResponse(spurLoop(0, 0, 0.01), 5000);
		},
	);
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 },
		OSRM_AND_GH,
		{ fetcher },
	);
	assert.equal(res.status, 200);
	assert.equal(ghCalled, false, 'round_trip is not consulted once the polygon wins');
});

test('handleGenerate falls back to round_trip when the polygon path is loop-poor', async () => {
	let ghCalled = false;
	const fetcher = routeByEngine(
		// Polygon path: every placement is a zero-area spur → loop-poor → null.
		() => osrmResponse(spurLoop(0, 0, 0.02), 5000, [5, 5, 5, 5]),
		() => {
			ghCalled = true;
			return ghResponse(squareLoop(0, 0, SQ_HALF), 5000);
		},
	);
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 },
		OSRM_AND_GH,
		{ fetcher },
	);
	assert.equal(res.status, 200);
	assert.equal(ghCalled, true, 'round_trip is consulted when the polygon is loop-poor');
});

test('handleGenerate returns 502 when polygon is loop-poor and no round_trip engine exists', async () => {
	const fetcher: Fetcher = async () => osrmResponse(spurLoop(0, 0, 0.02), 5000, [5, 5, 5, 5]);
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 },
		{ graphhopperUrl: undefined, osrmUrl: OSRM },
		{ fetcher },
	);
	assert.equal(res.status, 502);
});

test('handleGenerate uses round_trip directly when only GraphHopper is configured', async () => {
	let osrmCalled = false;
	const fetcher = routeByEngine(
		() => {
			osrmCalled = true;
			return osrmResponse(squareLoop(0, 0, SQ_HALF), 5000, [5, 5, 5, 5]);
		},
		() => ghResponse(squareLoop(0, 0, SQ_HALF), 5000),
	);
	const res = await handleGenerate(
		{ start: { lat: 0, lng: 0 }, targetDistanceM: 5000 },
		{ graphhopperUrl: GH },
		{ fetcher },
	);
	assert.equal(res.status, 200);
	assert.equal(osrmCalled, false, 'OSRM is untouched when osrmUrl is unset');
});
