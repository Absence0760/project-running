import { test } from 'node:test';
import assert from 'node:assert/strict';
import { clipPointsToZones, isInAnyZone, type PrivacyZone, type LatLng } from './privacy';

const home: PrivacyZone = { lat: 40.7128, lng: -74.006, radius_m: 200 };

// Tiny offset that crosses outside a 200m radius — about 350m east.
const offset = (lat: number, lng: number, dLng: number): LatLng => ({
	lat,
	lng: lng + dLng,
});

test('isInAnyZone — empty zones', () => {
	assert.equal(isInAnyZone({ lat: 0, lng: 0 }, []), false);
});

test('isInAnyZone — center is in zone', () => {
	assert.equal(isInAnyZone({ lat: home.lat, lng: home.lng }, [home]), true);
});

test('isInAnyZone — far point is not', () => {
	assert.equal(isInAnyZone(offset(home.lat, home.lng, 0.01), [home]), false);
});

test('clipPointsToZones — empty zones returns input', () => {
	const pts: LatLng[] = [{ lat: 1, lng: 1 }, { lat: 2, lng: 2 }];
	assert.deepEqual(clipPointsToZones(pts, []), pts);
});

test('clipPointsToZones — drops leading + trailing in-zone', () => {
	const pts: LatLng[] = [
		{ lat: home.lat, lng: home.lng }, // in
		{ lat: home.lat, lng: home.lng }, // in
		offset(home.lat, home.lng, 0.01), // out (mid)
		offset(home.lat, home.lng, 0.02), // out (mid)
		{ lat: home.lat, lng: home.lng }, // in (trailing)
	];
	const out = clipPointsToZones(pts, [home]);
	assert.equal(out.length, 2);
	assert.equal(out[0], pts[2]);
	assert.equal(out[1], pts[3]);
});

test('clipPointsToZones — keeps interior in-zone segments (only ends are clipped)', () => {
	const pts: LatLng[] = [
		offset(home.lat, home.lng, 0.01), // out
		{ lat: home.lat, lng: home.lng }, // in (interior — kept)
		offset(home.lat, home.lng, 0.02), // out
	];
	assert.deepEqual(clipPointsToZones(pts, [home]), pts);
});

test('clipPointsToZones — every point in zone returns empty', () => {
	const pts: LatLng[] = [
		{ lat: home.lat, lng: home.lng },
		{ lat: home.lat + 0.0001, lng: home.lng + 0.0001 },
	];
	assert.deepEqual(clipPointsToZones(pts, [home]), []);
});

test('clipPointsToZones — multiple zones', () => {
	const work: PrivacyZone = { lat: 40.75, lng: -73.99, radius_m: 200 };
	const pts: LatLng[] = [
		{ lat: home.lat, lng: home.lng }, // in home
		offset(home.lat, home.lng, 0.01), // out (mid)
		{ lat: work.lat, lng: work.lng }, // in work (trailing)
	];
	const out = clipPointsToZones(pts, [home, work]);
	assert.equal(out.length, 1);
	assert.equal(out[0], pts[1]);
});
