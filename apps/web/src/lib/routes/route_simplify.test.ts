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

test('computeElevationGain — a dropout carries the last reading across the gap', () => {
	const track: LatLng[] = [
		{ lat: 0, lng: 0, ele: 100 },
		{ lat: 0, lng: 0.001, ele: null },
		{ lat: 0, lng: 0.002, ele: 110 },
	];
	// A missing sample is a dropout, not a plateau. Breaking the chain on it
	// erased the climb that spans the gap — on a tree-covered or tunnelled
	// section of a long run, most of the real vert.
	assert.equal(computeElevationGain(track), 10);
	// Multiple consecutive dropouts behave the same.
	assert.equal(
		computeElevationGain([
			{ lat: 0, lng: 0, ele: 100 },
			{ lat: 0, lng: 0.001, ele: null },
			{ lat: 0, lng: 0.002, ele: null },
			{ lat: 0, lng: 0.003, ele: 130 },
			{ lat: 0, lng: 0.004, ele: 120 },
			{ lat: 0, lng: 0.005, ele: 125 },
		]),
		35,
	);
	// An ABSENT `ele` is the same dropout as an explicit null: the track type
	// makes the field optional, and the run-detail page feeds this raw
	// waypoints where a lost fix simply omits it.
	assert.equal(
		computeElevationGain([
			{ lat: 0, lng: 0, ele: 100 },
			{ lat: 0, lng: 0.001 },
			{ lat: 0, lng: 0.002, ele: 110 },
		]),
		10,
	);
});

test('computeElevationGain — jitter inside the noise band is not climb', () => {
	// A 1 Hz sawtooth of ±1 m around a flat road. Summing every positive pair
	// turned this into metres of phantom vert per minute; over a long run it
	// integrated into thousands.
	const track: LatLng[] = [];
	for (let i = 0; i < 200; i++) {
		track.push({ lat: 0, lng: i * 0.0001, ele: 100 + (i % 2) });
	}
	assert.equal(computeElevationGain(track), 0);
});

test('computeElevationGain — a real climb through jitter is counted in full', () => {
	// 100 m of climb delivered in 4 m steps with ±1 m noise on top.
	const track: LatLng[] = [];
	for (let i = 0; i <= 25; i++) {
		track.push({ lat: 0, lng: i * 0.0001, ele: 100 + i * 4 + (i % 2) });
	}
	const gain = computeElevationGain(track);
	assert.ok(gain >= 98 && gain <= 102, `expected ~100 m, got ${gain}`);
});

test('computeElevationGain — a descent resets the reference to the valley', () => {
	// Up 50, down 50, up 50 = 100 m of gain, not 50: the second climb must be
	// measured from the bottom, not from the first summit.
	assert.equal(
		computeElevationGain([
			{ lat: 0, lng: 0, ele: 100 },
			{ lat: 0, lng: 0.001, ele: 150 },
			{ lat: 0, lng: 0.002, ele: 100 },
			{ lat: 0, lng: 0.003, ele: 150 },
		]),
		100,
	);
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
	// Monotonic gain of 0.5 m per sample × 100 samples = 50 m of real climb.
	// Gain is taken over the RAW track, so simplification can't shrink it —
	// but the noise gate books climb in whole 3 m steps, so the final 2 m
	// sitting inside the band is not yet counted. 48, deterministically.
	assert.equal(out.elevation_m, 48);
});

test('summarizeRouteFromTrack: a hill that simplifies away still reports its climb', () => {
	// A dead-straight road over a summit. RDP measures perpendicular distance
	// in 2-D only, so every intermediate point collapses — and computing gain
	// over the simplified polyline reported this 50 m climb as 0.
	const track: LatLng[] = [];
	for (let i = 0; i <= 20; i++) {
		track.push({ lat: 0, lng: i * 0.0001, ele: 100 + (i <= 10 ? i * 5 : (20 - i) * 5) });
	}
	const out = summarizeRouteFromTrack(track, 10);
	assert.equal(out.waypoints.length, 2, 'a straight line collapses to its endpoints');
	assert.equal(out.elevation_m, 50);
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

test('simplifyTrack — a straight line across the antimeridian collapses to its endpoints', () => {
	const line: LatLng[] = [
		{ lat: 0, lng: 179.98 },
		{ lat: 0, lng: 179.99 },
		{ lat: 0, lng: -180 },
		{ lat: 0, lng: -179.99 },
		{ lat: 0, lng: -179.98 },
	];
	assert.deepEqual(simplifyTrack(line, 10), [line[0], line[4]]);
});

test('simplifyTrack — a real deviation across the antimeridian survives', () => {
	// 50 m north of the chord, well clear of the 10 m tolerance.
	const off = 50 / 111_194.93;
	const line: LatLng[] = [
		{ lat: 0, lng: 179.98 },
		{ lat: off, lng: -179.99 },
		{ lat: 0, lng: -179.96 },
	];
	assert.deepEqual(simplifyTrack(line, 10), line);
});

test('summarizeRouteFromTrack — a leg across the antimeridian measures 0.06°, not 359.94°', () => {
	const out = summarizeRouteFromTrack(
		[
			{ lat: 0, lng: 179.98 },
			{ lat: 0, lng: -179.96 },
		],
		10,
	);
	assert.ok(
		Math.abs(out.distance_m - 6671.7) < 1,
		`got ${out.distance_m}`,
	);
});
