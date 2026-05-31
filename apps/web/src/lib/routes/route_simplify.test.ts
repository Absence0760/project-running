import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	simplifyTrack,
	computeElevationGain,
	summarizeRouteFromTrack,
	type LatLng,
} from './route_simplify';

test('simplifyTrack — fewer than 3 points returns the input unchanged', () => {
	assert.deepEqual(simplifyTrack([]), []);
	const one: LatLng[] = [{ lat: 0, lng: 0 }];
	assert.deepEqual(simplifyTrack(one), one);
	const two: LatLng[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0, lng: 1 },
	];
	assert.deepEqual(simplifyTrack(two), two);
});

test('simplifyTrack — keeps a clean straight line as just its endpoints', () => {
	const pts: LatLng[] = [];
	for (let i = 0; i <= 10; i++) {
		pts.push({ lat: 0, lng: i * 0.001 });
	}
	const out = simplifyTrack(pts, 1);
	assert.equal(out.length, 2);
	assert.deepEqual(out[0], pts[0]);
	assert.deepEqual(out[out.length - 1], pts[pts.length - 1]);
});

test('simplifyTrack — preserves a sharp corner above epsilon', () => {
	const pts: LatLng[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0, lng: 0.001 },
		{ lat: 0.001, lng: 0.001 },
		{ lat: 0.001, lng: 0.002 },
	];
	const out = simplifyTrack(pts, 5);
	// The corner sits about 100 m off any straight chord through the
	// other points — far more than the 5 m epsilon, so it must survive.
	assert.ok(out.length >= 3);
	const hasCorner = out.some((p) => p.lat === 0.001 && p.lng === 0.001);
	assert.ok(hasCorner, 'corner waypoint should survive simplification');
});

test('simplifyTrack — collapses sub-epsilon jitter on a straight line', () => {
	const pts: LatLng[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0.0000001, lng: 0.0005 }, // ~1 cm offset, far below 10 m epsilon
		{ lat: -0.0000002, lng: 0.001 },
		{ lat: 0, lng: 0.0015 },
		{ lat: 0, lng: 0.002 },
	];
	const out = simplifyTrack(pts, 10);
	assert.equal(out.length, 2, 'sub-cm jitter on a 200 m straight line collapses');
});

test('simplifyTrack — first and last points always retained', () => {
	const pts: LatLng[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0.0001, lng: 0.0001 },
		{ lat: 0, lng: 0.0002 },
	];
	const out = simplifyTrack(pts, 1000);
	assert.equal(out[0].lat, 0);
	assert.equal(out[0].lng, 0);
	assert.equal(out[out.length - 1].lng, 0.0002);
});

test('simplifyTrack — does not mutate the input array', () => {
	const pts: LatLng[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0, lng: 0.001 },
		{ lat: 0, lng: 0.002 },
	];
	const before = pts.map((p) => ({ ...p }));
	simplifyTrack(pts, 1);
	assert.deepEqual(pts, before);
});

test('computeElevationGain — accumulates only positive deltas', () => {
	const track: LatLng[] = [
		{ lat: 0, lng: 0, ele: 100 },
		{ lat: 0, lng: 0.001, ele: 110 },
		{ lat: 0, lng: 0.002, ele: 105 },
		{ lat: 0, lng: 0.003, ele: 120 },
	];
	// +10 then -5 (ignored) then +15 = 25
	assert.equal(computeElevationGain(track), 25);
});

test('computeElevationGain — tracks without elevation return 0', () => {
	const track: LatLng[] = [
		{ lat: 0, lng: 0 },
		{ lat: 0, lng: 0.001 },
		{ lat: 0, lng: 0.002 },
	];
	assert.equal(computeElevationGain(track), 0);
});

test('computeElevationGain — null elevations are skipped', () => {
	const track: LatLng[] = [
		{ lat: 0, lng: 0, ele: 100 },
		{ lat: 0, lng: 0.001, ele: null },
		{ lat: 0, lng: 0.002, ele: 110 },
	];
	// The middle null breaks the chain — neither pair (100→null, null→110)
	// contributes, so gain stays 0.
	assert.equal(computeElevationGain(track), 0);
});

test('computeElevationGain — empty / single-point track returns 0', () => {
	assert.equal(computeElevationGain([]), 0);
	assert.equal(computeElevationGain([{ lat: 0, lng: 0, ele: 100 }]), 0);
});

// ─────────── summarizeRouteFromTrack ───────────

test('summarizeRouteFromTrack: produces waypoints + distance + elevation', () => {
	// A straight 1 km eastward track at lat 0 — 1 km east is roughly
	// 360/40_000 = 0.009° of longitude. Equirectangular at the equator
	// is exact for east-west, so the sum should land at ~1000 m.
	const degPerKm = 360 / 40_000;
	const track: LatLng[] = [];
	for (let i = 0; i <= 100; i++) {
		track.push({ lat: 0, lng: i * degPerKm * 0.01, ele: i * 0.5 });
	}
	const out = summarizeRouteFromTrack(track, 10);
	assert.ok(out.waypoints.length <= track.length, 'should simplify');
	assert.ok(out.waypoints.length >= 2, 'must keep endpoints');
	// 1 km eastward, equirectangular at the equator, allow 1 % slop
	// because R=6_371_000 is a sphere approximation.
	assert.ok(
		Math.abs(out.distance_m - 1000) < 10,
		`expected ~1000 m, got ${out.distance_m}`,
	);
	// Monotonic gain of 0.5 m per sample × 100 samples = 50 m, but
	// simplification keeps only endpoints + a few intermediates. The
	// rising endpoint pair (whichever points survive) must sum to the
	// full delta because the simplifier preserves the polyline shape
	// from end to end, and elevation gain is computed over kept points.
	assert.ok(
		out.elevation_m >= 40 && out.elevation_m <= 50,
		`expected ~50 m gain, got ${out.elevation_m}`,
	);
});

test('summarizeRouteFromTrack: passes ele through when present, drops when absent', () => {
	const track: LatLng[] = [
		{ lat: 0, lng: 0, ele: 10 },
		{ lat: 0, lng: 0.01 },
		{ lat: 0, lng: 0.02, ele: 20 },
	];
	const out = summarizeRouteFromTrack(track, 5);
	const eles = out.waypoints.map((w) => w.ele ?? null);
	// First + last kept; middle absent. The exact set depends on
	// simplification, but the kept endpoints must carry their ele.
	assert.equal(eles[0], 10);
	assert.equal(eles[eles.length - 1], 20);
});

test('summarizeRouteFromTrack: single-point track returns the point with zero distance', () => {
	const out = summarizeRouteFromTrack([{ lat: 0, lng: 0 }], 10);
	assert.equal(out.waypoints.length, 1);
	assert.equal(out.distance_m, 0);
	assert.equal(out.elevation_m, 0);
});

test('summarizeRouteFromTrack: empty track returns zeros', () => {
	const out = summarizeRouteFromTrack([], 10);
	assert.deepEqual(out.waypoints, []);
	assert.equal(out.distance_m, 0);
	assert.equal(out.elevation_m, 0);
});

test('summarizeRouteFromTrack: distance is symmetric under reversal', () => {
	const track: LatLng[] = [
		{ lat: 47.0, lng: 8.5 },
		{ lat: 47.001, lng: 8.501 },
		{ lat: 47.002, lng: 8.502 },
		{ lat: 47.003, lng: 8.503 },
		{ lat: 47.004, lng: 8.504 },
	];
	const forward = summarizeRouteFromTrack(track, 5);
	const backward = summarizeRouteFromTrack(track.slice().reverse(), 5);
	// Equirectangular cumulative distance must be reversal-invariant.
	assert.ok(Math.abs(forward.distance_m - backward.distance_m) < 0.001);
});

test('summarizeRouteFromTrack: cos(midLat) correction kicks in at high latitudes', () => {
	// Equirectangular without the cos(midLat) correction would
	// overstate east-west distance at high latitudes. At lat 60°N,
	// one degree of longitude is half as wide as at the equator —
	// so a 0.01° east step at lat 60 should be ~half the distance
	// of the same step at lat 0.
	const stepLng = 0.01;
	const atEquator = summarizeRouteFromTrack(
		[
			{ lat: 0, lng: 0 },
			{ lat: 0, lng: stepLng },
		],
		1,
	);
	const at60N = summarizeRouteFromTrack(
		[
			{ lat: 60, lng: 0 },
			{ lat: 60, lng: stepLng },
		],
		1,
	);
	// cos(60°) = 0.5, so at60N.distance should be ~half of equator's.
	const ratio = at60N.distance_m / atEquator.distance_m;
	assert.ok(
		Math.abs(ratio - 0.5) < 0.001,
		`expected cos(60°) ≈ 0.5 ratio, got ${ratio}`,
	);
});
