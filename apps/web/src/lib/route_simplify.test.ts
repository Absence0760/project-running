import { test } from 'node:test';
import assert from 'node:assert/strict';
import { simplifyTrack, computeElevationGain, type LatLng } from './route_simplify';

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
