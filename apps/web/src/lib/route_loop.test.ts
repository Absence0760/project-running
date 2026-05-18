import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	ACCEPT_BAND,
	DEFAULT_SCALE_FACTOR,
	MAX_TARGET_DISTANCE_M,
	NEAR_POINT_M,
	RATIO_CLAMP,
	SCALE_FACTOR_BOUNDS,
	generateLoopWaypoints,
	isValidTargetDistance,
	isWithinAcceptBand,
	nextScaleFactor,
} from './route_loop';
import { haversineM } from './routing_quality';

// Richmond, VA area — matches the field-bug screenshot.
const START = { lat: 37.652, lng: -77.3612 };

test('loop branch — no end provided returns radial waypoints around start', () => {
	const wps = generateLoopWaypoints({
		start: START,
		targetDistanceM: 5000,
		radialSeedRad: 0,
	});
	// numPoints (default 6) + start + closing
	assert.equal(wps.length, 8);
	assert.equal(wps[0].lat, START.lat);
	assert.equal(wps[0].lng, START.lng);
	assert.equal(wps[wps.length - 1].lat, START.lat);
	assert.equal(wps[wps.length - 1].lng, START.lng);

	// Interior waypoints lie roughly on a circle of expected radius.
	const expectedRadiusM =
		(5000 * DEFAULT_SCALE_FACTOR) / (2 * Math.PI);
	for (let i = 1; i <= 6; i++) {
		const d = haversineM(START, wps[i]);
		// 5% tolerance for the cos(lat) longitude scaling.
		assert.ok(
			Math.abs(d - expectedRadiusM) < expectedRadiusM * 0.05,
			`waypoint ${i} expected ~${expectedRadiusM}m, got ${d}m`,
		);
	}
});

test('loop branch — explicit null end is treated as a loop', () => {
	const wps = generateLoopWaypoints({
		start: START,
		end: null,
		targetDistanceM: 5000,
		radialSeedRad: 0,
	});
	assert.equal(wps[wps.length - 1].lat, START.lat);
	assert.equal(wps[wps.length - 1].lng, START.lng);
});

test('loop branch — end within NEAR_POINT_M of start is treated as a loop', () => {
	// 11m apart — the field-bug coordinates.
	const end = { lat: 37.6519, lng: -77.3612 };
	assert.ok(
		haversineM(START, end) < NEAR_POINT_M,
		'precondition: the test inputs are within the near-point threshold',
	);
	const wps = generateLoopWaypoints({
		start: START,
		end,
		targetDistanceM: 5000,
		radialSeedRad: 0,
	});
	// Closing waypoint snaps back to start, not the near-equal end —
	// proves the loop branch was taken.
	assert.equal(wps[wps.length - 1].lat, START.lat);
	assert.equal(wps[wps.length - 1].lng, START.lng);

	// Interior points fan out at the expected radius from start.
	const expectedRadiusM = (5000 * DEFAULT_SCALE_FACTOR) / (2 * Math.PI);
	for (let i = 1; i <= 6; i++) {
		const d = haversineM(START, wps[i]);
		assert.ok(
			Math.abs(d - expectedRadiusM) < expectedRadiusM * 0.05,
			`waypoint ${i} expected ~${expectedRadiusM}m, got ${d}m`,
		);
	}
});

test('point-to-point — start and end are honoured exactly at the endpoints', () => {
	const end = { lat: 37.66, lng: -77.36 }; // ~890m from start
	const wps = generateLoopWaypoints({
		start: START,
		end,
		targetDistanceM: 3000,
	});
	assert.equal(wps[0].lat, START.lat);
	assert.equal(wps[0].lng, START.lng);
	assert.equal(wps[wps.length - 1].lat, end.lat);
	assert.equal(wps[wps.length - 1].lng, end.lng);
});

test('point-to-point — distinct end > NEAR_POINT_M gets a curved interior', () => {
	const end = { lat: 37.66, lng: -77.36 };
	const wps = generateLoopWaypoints({
		start: START,
		end,
		targetDistanceM: 3000,
	});
	// Pick the middle interior waypoint; it must lie off the straight
	// line from start to end, otherwise the curve isn't being applied.
	const mid = wps[Math.floor(wps.length / 2)];
	// Cross-product check: ((end - start) × (mid - start)).z != 0.
	const a = { lat: end.lat - START.lat, lng: end.lng - START.lng };
	const b = { lat: mid.lat - START.lat, lng: mid.lng - START.lng };
	const cross = a.lat * b.lng - a.lng * b.lat;
	assert.notEqual(cross, 0);
});

test('nextScaleFactor — degenerate actualDistance (0) does not produce NaN or runaway', () => {
	const next = nextScaleFactor(DEFAULT_SCALE_FACTOR, 5000, 0);
	assert.ok(Number.isFinite(next));
	assert.ok(next <= SCALE_FACTOR_BOUNDS.max);
	assert.ok(next >= SCALE_FACTOR_BOUNDS.min);
});

test('nextScaleFactor — huge raw ratio is clamped to RATIO_CLAMP.max', () => {
	// Target 5000m, actual 50m → raw ratio = 100. Without the clamp,
	// scaleFactor would jump to 30 and the next attempt would push
	// waypoints kilometres away.
	const next = nextScaleFactor(DEFAULT_SCALE_FACTOR, 5000, 50);
	// Clamped: 0.3 * 3 = 0.9 (under SCALE_FACTOR_BOUNDS.max of 2).
	assert.equal(next, DEFAULT_SCALE_FACTOR * RATIO_CLAMP.max);
});

test('nextScaleFactor — overlong route shrinks scaleFactor', () => {
	// actual > target → ratio < 1 → scaleFactor decreases.
	const next = nextScaleFactor(DEFAULT_SCALE_FACTOR, 5000, 8000);
	assert.ok(next < DEFAULT_SCALE_FACTOR);
});

test('nextScaleFactor — extreme shrink is clamped to RATIO_CLAMP.min', () => {
	// Target 100m, actual 50000m → ratio = 0.002. Without the clamp
	// the next attempt would barely move at all.
	const next = nextScaleFactor(DEFAULT_SCALE_FACTOR, 100, 50000);
	assert.equal(next, DEFAULT_SCALE_FACTOR * RATIO_CLAMP.min);
});

test('nextScaleFactor — cumulative bound respected even after several steps', () => {
	let s = DEFAULT_SCALE_FACTOR;
	for (let i = 0; i < 10; i++) s = nextScaleFactor(s, 5000, 50);
	assert.ok(s <= SCALE_FACTOR_BOUNDS.max);
});

test('isWithinAcceptBand — within tolerance', () => {
	assert.equal(isWithinAcceptBand(5000, 5000), true);
	assert.equal(isWithinAcceptBand(5000, 4500), true); // ratio 1.111
	assert.equal(isWithinAcceptBand(5000, 5500), true); // ratio 0.909
});

test('isWithinAcceptBand — outside tolerance', () => {
	assert.equal(isWithinAcceptBand(5000, 1000), false);
	assert.equal(isWithinAcceptBand(5000, 50000), false);
	assert.equal(isWithinAcceptBand(5000, 0), false);
});

test('isWithinAcceptBand — band edges match the documented thresholds', () => {
	// Exactly on the threshold returns false (strict <, >).
	const justInsideLow = 5000 / (ACCEPT_BAND.max - 0.001);
	const justInsideHigh = 5000 / (ACCEPT_BAND.min + 0.001);
	assert.equal(isWithinAcceptBand(5000, justInsideLow), true);
	assert.equal(isWithinAcceptBand(5000, justInsideHigh), true);
});

test('isValidTargetDistance — accepts realistic values', () => {
	assert.equal(isValidTargetDistance(1), true);
	assert.equal(isValidTargetDistance(5000), true);
	assert.equal(isValidTargetDistance(42_195), true); // marathon in metres
	assert.equal(isValidTargetDistance(MAX_TARGET_DISTANCE_M), true);
});

test('isValidTargetDistance — rejects non-positive', () => {
	assert.equal(isValidTargetDistance(0), false);
	assert.equal(isValidTargetDistance(-1), false);
	assert.equal(isValidTargetDistance(-5000), false);
});

test('isValidTargetDistance — rejects non-finite', () => {
	assert.equal(isValidTargetDistance(Number.NaN), false);
	assert.equal(isValidTargetDistance(Number.POSITIVE_INFINITY), false);
	assert.equal(isValidTargetDistance(Number.NEGATIVE_INFINITY), false);
});

test('isValidTargetDistance — rejects absurd large values', () => {
	// 1,000,000 km — almost certainly a unit-conversion bug.
	assert.equal(isValidTargetDistance(MAX_TARGET_DISTANCE_M + 1), false);
	assert.equal(isValidTargetDistance(1e12), false);
});

test('isValidTargetDistance — rejects non-numbers', () => {
	assert.equal(isValidTargetDistance('5000' as unknown as number), false);
	assert.equal(isValidTargetDistance(null as unknown as number), false);
	assert.equal(isValidTargetDistance(undefined as unknown as number), false);
	assert.equal(isValidTargetDistance({} as unknown as number), false);
});

test('regression — field bug coords (start ≈ end, target 5km) produce on-pin waypoints', () => {
	// The exact coordinates from the user's bug screenshot.
	const start = { lat: 37.652, lng: -77.3612 };
	const end = { lat: 37.6519, lng: -77.3612 };
	const wps = generateLoopWaypoints({
		start,
		end,
		targetDistanceM: 5000,
		radialSeedRad: 0,
	});
	const expectedRadiusM = (5000 * DEFAULT_SCALE_FACTOR) / (2 * Math.PI);
	// Interior waypoints stay within ~1.2x the expected radius from
	// start. Without the near-point detection they could be hundreds
	// of km away after the scaleFactor explosion.
	for (let i = 1; i < wps.length - 1; i++) {
		const d = haversineM(start, wps[i]);
		assert.ok(
			d < expectedRadiusM * 1.2,
			`regression: waypoint ${i} is ${d}m from start, expected < ${expectedRadiusM * 1.2}m`,
		);
	}
});
