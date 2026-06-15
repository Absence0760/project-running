// Unit tests for the route-geometry helpers. Run with `node --test`
// via tsx, matching the rest of the apps/web suite:
//   npx tsx --test src/lib/routes/route_geometry.test.ts
//
// Mirror of `apps/mobile_android/test/route_geometry_test.dart` —
// keep this file in lockstep with the Dart twin.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	interpolateAlongRoute,
	distanceAlongRoute,
	polylineLengthMetres,
	type RouteWaypoint,
} from './route_geometry';

const wp = (lat: number, lng: number, elev?: number): RouteWaypoint => ({
	lat,
	lng,
	elevation_m: elev,
});

test('interpolateAlongRoute — null on empty waypoints', () => {
	assert.equal(interpolateAlongRoute([], 0.5), null);
});

test('interpolateAlongRoute — null on single waypoint', () => {
	assert.equal(interpolateAlongRoute([wp(0, 0)], 0.5), null);
});

test('interpolateAlongRoute — all-coincident waypoints snap to start', () => {
	const out = interpolateAlongRoute(
		[wp(1, 1), wp(1, 1), wp(1, 1)],
		0.5,
	);
	assert.ok(out);
	assert.equal(out!.lat, 1);
	assert.equal(out!.lng, 1);
});

test('interpolateAlongRoute — fraction below 0 clamps to start', () => {
	const out = interpolateAlongRoute([wp(0, 0), wp(0, 0.001)], -1.0);
	assert.ok(out);
	assert.ok(Math.abs(out!.lng - 0) < 1e-9);
});

test('interpolateAlongRoute — fraction above 1 clamps to end', () => {
	const out = interpolateAlongRoute([wp(0, 0), wp(0, 0.001)], 2.0);
	assert.ok(out);
	assert.ok(Math.abs(out!.lng - 0.001) < 1e-9);
});

test('interpolateAlongRoute — fraction = 0 returns start exactly', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.005), wp(0, 0.010)],
		0.0,
	);
	assert.equal(out!.lat, 0);
	assert.ok(Math.abs(out!.lng - 0) < 1e-9);
});

test('interpolateAlongRoute — fraction = 1 returns end exactly', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.005), wp(0, 0.010)],
		1.0,
	);
	assert.equal(out!.lat, 0);
	assert.ok(Math.abs(out!.lng - 0.010) < 1e-9);
});

test('interpolateAlongRoute — fraction = 0.5 on even-spaced lands at midpoint', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.005), wp(0, 0.010)],
		0.5,
	);
	assert.ok(Math.abs(out!.lng - 0.005) < 1e-6);
});

test('interpolateAlongRoute — distance-weighted (long segment dominates)', () => {
	// Short (1 unit) + long (9 units). Fraction 0.5 of total
	// distance (5 units) lands INSIDE the long segment — not at
	// the corner. Catches a regression to naive index-weighted.
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.001), wp(0, 0.010)],
		0.5,
	);
	assert.ok(Math.abs(out!.lng - 0.005) < 1e-6);
});

test('interpolateAlongRoute — 4-equal-leg at 0.25 lands at first corner', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.001), wp(0, 0.002), wp(0, 0.003), wp(0, 0.004)],
		0.25,
	);
	assert.ok(Math.abs(out!.lng - 0.001) < 1e-6);
});

test('interpolateAlongRoute — out-and-back uses path distance, not chord', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.001), wp(0, 0)],
		0.5,
	);
	// At the turn-around, NOT at the chord midpoint.
	assert.ok(Math.abs(out!.lng - 0.001) < 1e-6);
});

test('interpolateAlongRoute — elevation lerps linearly', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0, 100), wp(0, 0.001, 200)],
		0.5,
	);
	assert.ok(Math.abs((out!.elevation_m ?? 0) - 150) < 0.01);
});

test('interpolateAlongRoute — lerp tolerates one-sided null', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0.001, 50)],
		0.5,
	);
	assert.equal(out!.elevation_m, 50);
});

test('interpolateAlongRoute — returns null elevation when both sides null', () => {
	const out = interpolateAlongRoute([wp(0, 0), wp(0, 0.001)], 0.5);
	assert.equal(out!.elevation_m, null);
});

test('polylineLengthMetres — empty / single → 0', () => {
	assert.equal(polylineLengthMetres([]), 0);
	assert.equal(polylineLengthMetres([wp(0, 0)]), 0);
});

test('polylineLengthMetres — 100 m segment at equator ≈ 100 m', () => {
	const metresPerDegLngAtEquator = 111320.0;
	const out = polylineLengthMetres([
		wp(0, 0),
		wp(0, 100 / metresPerDegLngAtEquator),
	]);
	assert.ok(Math.abs(out - 100) < 1);
});

test('polylineLengthMetres — multi-segment lengths sum', () => {
	const metresPerDegLngAtEquator = 111320.0;
	const step = 100 / metresPerDegLngAtEquator;
	const out = polylineLengthMetres([wp(0, 0), wp(0, step), wp(0, 2 * step)]);
	assert.ok(Math.abs(out - 200) < 1);
});

test('interpolateAlongRoute — southern-hemisphere is symmetric', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(-0.005, 0), wp(-0.010, 0)],
		0.5,
	);
	assert.ok(Math.abs(out!.lat - -0.005) < 1e-6);
	assert.equal(out!.lng, 0);
});

test('interpolateAlongRoute — negative longitude (Americas) is safe', () => {
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, -0.005), wp(0, -0.010)],
		0.5,
	);
	assert.ok(Math.abs(out!.lng - -0.005) < 1e-6);
});

test('interpolateAlongRoute — 2-waypoint polyline at fraction=0.5 → midpoint', () => {
	// Minimum valid input — pin the smallest case the scrubber must
	// support.
	const out = interpolateAlongRoute([wp(0, 0), wp(0, 0.010)], 0.5);
	assert.ok(Math.abs(out!.lng - 0.005) < 1e-6);
});

test('interpolateAlongRoute — skips zero-length segments (no poison from duplicate waypoints)', () => {
	// Defence-in-depth: the route builder\'s 5-m dedupe should
	// guarantee no exact duplicates, but if they leak through the
	// helper must skip and land in the next real segment.
	const out = interpolateAlongRoute(
		[wp(0, 0), wp(0, 0), wp(0, 0.010)],
		0.5,
	);
	assert.ok(Math.abs(out!.lng - 0.005) < 1e-6);
});

test('interpolateAlongRoute — 200-point polyline runs under 50 ms (O(n) guard)', () => {
	const wps: RouteWaypoint[] = [];
	for (let i = 0; i <= 200; i++) wps.push(wp(0, i * 0.0001));
	const start = performance.now();
	const out = interpolateAlongRoute(wps, 0.5);
	const elapsed = performance.now() - start;
	assert.ok(out !== null);
	assert.ok(
		elapsed < 50,
		`Expected <50ms, got ${elapsed.toFixed(1)}ms — quadratic regression?`,
	);
});

const metresPerDegLng = 111320.0;
const distWp = (lng: number): RouteWaypoint => wp(0, lng / metresPerDegLng);

test('distanceAlongRoute — null on < 2 waypoints', () => {
	assert.equal(distanceAlongRoute({ lat: 0, lng: 0 }, []), null);
	assert.equal(distanceAlongRoute({ lat: 0, lng: 0 }, [wp(0, 0)]), null);
});

test('distanceAlongRoute — point on a vertex returns its cumulative distance', () => {
	// Three 100-m legs along the equator. The 2nd vertex is at 200 m.
	const wps = [distWp(0), distWp(100), distWp(200), distWp(300)];
	const d = distanceAlongRoute(wps[2], wps);
	assert.ok(d !== null);
	assert.ok(Math.abs(d! - 200) < 1, `got ${d}`);
});

test('distanceAlongRoute — point mid-segment returns the interpolated distance', () => {
	const wps = [distWp(0), distWp(100), distWp(200)];
	const d = distanceAlongRoute(distWp(150), wps);
	assert.ok(d !== null);
	assert.ok(Math.abs(d! - 150) < 1, `got ${d}`);
});

test('distanceAlongRoute — perpendicular offset still maps to the right along-distance', () => {
	// 50 m north of the 150-m mark — projects back down to 150 m.
	const wps = [distWp(0), distWp(100), distWp(200)];
	const offset = { lat: 50 / metresPerDegLng, lng: 150 / metresPerDegLng };
	const d = distanceAlongRoute(offset, wps);
	assert.ok(d !== null);
	assert.ok(Math.abs(d! - 150) < 1, `got ${d}`);
});

test('distanceAlongRoute — point near the end maps near totalLength', () => {
	const wps = [distWp(0), distWp(100), distWp(200)];
	const total = polylineLengthMetres(wps);
	const d = distanceAlongRoute(distWp(199), wps);
	assert.ok(d !== null);
	assert.ok(Math.abs(d! - 199) < 1, `got ${d}`);
	assert.ok(d! <= total + 1e-6);
});

test('distanceAlongRoute — picks the nearest of two close segments', () => {
	// An L: east 100 m then north 100 m. A point just east of the
	// corner, slightly north, is nearest the FIRST (horizontal) leg,
	// so it maps to ~100 m, not into the vertical leg.
	const corner = distWp(100);
	const up = wp(100 / metresPerDegLng, 100 / metresPerDegLng);
	const wps = [distWp(0), corner, up];
	// Just south of the 50-m mark on the first (horizontal) leg —
	// unambiguously nearest it, far from the vertical leg.
	const probe = { lat: -2 / metresPerDegLng, lng: 50 / metresPerDegLng };
	const d = distanceAlongRoute(probe, wps);
	assert.ok(d !== null);
	assert.ok(d! < 100, `expected on the first leg (<100 m), got ${d}`);
	assert.ok(Math.abs(d! - 50) < 2, `got ${d}`);
});

test('distanceAlongRoute — clamps to [0, totalLength]', () => {
	const wps = [distWp(0), distWp(100), distWp(200)];
	const total = polylineLengthMetres(wps);
	// Way past the end, off to the side.
	const far = distWp(10_000);
	const d = distanceAlongRoute(far, wps);
	assert.ok(d !== null);
	assert.ok(d! >= 0 && d! <= total + 1e-6, `got ${d} (total ${total})`);
});
