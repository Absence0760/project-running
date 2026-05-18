import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	closestPointDistanceM,
	haversineM,
	pointToSegmentDistanceM,
	qualityWarning,
	QUALITY_THRESHOLDS,
	validateRouteQuality,
	type RoutedSegment,
} from './routing_quality';

test('haversineM ballparks well-known intercity distances', () => {
	// DC ≈ (38.90, -77.04), Richmond ≈ (37.54, -77.43) — ~150km apart.
	const d = haversineM(
		{ lng: -77.04, lat: 38.9 },
		{ lng: -77.43, lat: 37.54 },
	);
	assert.ok(d > 140_000 && d < 170_000, `expected ~150km, got ${d}`);
});

test('pointToSegmentDistanceM is zero on the segment, increases off it', () => {
	const a = { lng: -77.0, lat: 38.9 };
	const b = { lng: -77.0, lat: 39.0 };
	// Point on the line at the midpoint:
	const onLine = { lng: -77.0, lat: 38.95 };
	assert.ok(pointToSegmentDistanceM(onLine, a, b) < 1);
	// Point 100m east of the midpoint:
	// 100m east at lat 38.95 ≈ 100 / (111320 * cos(38.95°)) degrees of lng
	const offsetDeg = 100 / (111320 * Math.cos((38.95 * Math.PI) / 180));
	const offLine = { lng: -77.0 + offsetDeg, lat: 38.95 };
	const d = pointToSegmentDistanceM(offLine, a, b);
	assert.ok(d > 90 && d < 110, `expected ~100m, got ${d.toFixed(1)}m`);
});

test('pointToSegmentDistanceM clamps to endpoints (no negative projection)', () => {
	const a = { lng: -77.0, lat: 38.9 };
	const b = { lng: -77.0, lat: 39.0 };
	// Point ~100m south of A — the perpendicular projection lands
	// before A, so the distance should equal haversine(point, A),
	// not the perpendicular distance to the infinite line (which
	// would be ~0 because the infinite line passes through south
	// too). 100m keeps us well inside the linear-projection
	// accuracy band.
	const south = { lng: -77.0, lat: 38.8991 };
	const d = pointToSegmentDistanceM(south, a, b);
	const expected = haversineM(south, a);
	assert.ok(d > 50, `clamp returned a near-zero (point projected onto infinite line): ${d}`);
	assert.ok(
		Math.abs(d - expected) < 1,
		`clamp distance disagrees with haversine: ${d} vs ${expected}`,
	);
});

test('closestPointDistanceM finds the nearest edge across a multi-segment polyline', () => {
	// Three-segment polyline forming an L shape.
	const polyline: [number, number][] = [
		[-77.0, 38.9],
		[-77.0, 39.0],
		[-76.9, 39.0],
	];
	// Point right next to the corner — should be very close.
	const nearCorner = { lng: -77.0, lat: 38.999 };
	assert.ok(closestPointDistanceM(nearCorner, polyline) < 200);
	// Point 100m east of the vertical leg, well below the corner.
	const offsetDeg = 100 / (111320 * Math.cos((38.95 * Math.PI) / 180));
	const offVertical = { lng: -77.0 + offsetDeg, lat: 38.95 };
	const d = closestPointDistanceM(offVertical, polyline);
	assert.ok(d > 90 && d < 110, `expected ~100m, got ${d}`);
});

test('validateRouteQuality returns happy defaults for empty input', () => {
	const q = validateRouteQuality([]);
	assert.equal(q.maxWaypointDeviationM, 0);
	assert.equal(q.worstSegmentDetourRatio, 1);
	assert.equal(qualityWarning(q), null);
});

test('validateRouteQuality returns ~0 deviation for a route that follows its waypoints', () => {
	// A 3-waypoint chain that goes A → B → C, with the polyline
	// exactly tracing the straight lines. No deviation, ~1.0 detour.
	const A = { lat: 38.9, lng: -77.0 };
	const B = { lat: 38.91, lng: -77.0 };
	const C = { lat: 38.91, lng: -76.99 };
	const segs: RoutedSegment[] = [
		{
			from: A,
			to: B,
			polyline: [
				[A.lng, A.lat],
				[B.lng, B.lat],
			],
			distanceM: haversineM(A, B),
		},
		{
			from: B,
			to: C,
			polyline: [
				[B.lng, B.lat],
				[C.lng, C.lat],
			],
			distanceM: haversineM(B, C),
		},
	];
	const q = validateRouteQuality(segs);
	assert.ok(q.maxWaypointDeviationM < 1, `expected ~0, got ${q.maxWaypointDeviationM}`);
	assert.ok(q.worstSegmentDetourRatio < 1.01);
	assert.equal(qualityWarning(q), null);
});

test('validateRouteQuality flags a waypoint that landed far from the snapped path', () => {
	// The user clicked at A_bad — somewhere a path doesn't exist —
	// and OSRM snapped its segment endpoint to A_snapped, ~300m away.
	// The returned polyline never touches A_bad.
	const A_bad = { lat: 38.9, lng: -77.0 };
	const A_snapped = { lat: 38.9, lng: -77.0035 }; // ~300m west of A_bad
	const B = { lat: 38.91, lng: -77.0 };
	const segs: RoutedSegment[] = [
		{
			from: A_bad,
			to: B,
			polyline: [
				[A_snapped.lng, A_snapped.lat],
				[B.lng, B.lat],
			],
			distanceM: haversineM(A_snapped, B),
		},
	];
	const q = validateRouteQuality(segs);
	assert.ok(q.maxWaypointDeviationM > 200, `expected > 200m, got ${q.maxWaypointDeviationM}`);
	assert.equal(q.worstDeviationWaypointIndex, 1);
	const msg = qualityWarning(q);
	assert.match(msg ?? '', /Waypoint 1/);
	assert.match(msg ?? '', /off the snapped path/);
});

test('validateRouteQuality flags a segment with a large detour ratio', () => {
	// Two waypoints 100m apart, but OSRM reports a 600m route between
	// them — 6x detour (e.g. routed around a closed gate).
	const A = { lat: 38.9, lng: -77.0 };
	const B = { lat: 38.9009, lng: -77.0 }; // ~100m north
	const segs: RoutedSegment[] = [
		{
			from: A,
			to: B,
			polyline: [
				[A.lng, A.lat],
				[B.lng, B.lat],
			],
			distanceM: 600,
		},
	];
	const q = validateRouteQuality(segs);
	assert.ok(q.worstSegmentDetourRatio > 5);
	const msg = qualityWarning(q);
	assert.match(msg ?? '', /Segment 1/);
	assert.match(msg ?? '', /detour/);
});

test('thresholds are exported and within sensible ranges (regression guard)', () => {
	// If someone tightens these, plenty of legitimate routes start
	// firing false-positive warnings. Pin a band.
	assert.ok(QUALITY_THRESHOLDS.deviationWarnM >= 30);
	assert.ok(QUALITY_THRESHOLDS.deviationWarnM <= 120);
	assert.ok(QUALITY_THRESHOLDS.detourWarnRatio >= 2);
	assert.ok(QUALITY_THRESHOLDS.detourWarnRatio <= 5);
});
