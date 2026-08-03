import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { lonDeltaDeg, unwrapLonDeg, wrapLonDeg } from './geo';

/// Mirror of `apps/mobile_android/test/geo_test.dart`, itself mirroring the
/// firmware's `watch_core::geo` tests (decisions §463). Keep all three in
/// lockstep — every planar frame on both platforms takes its longitude
/// deltas through here.

test('a delta within a hemisphere is the plain subtraction, bit for bit', () => {
	for (const [a, b] of [
		[-105.2705, -105.269445],
		[51.5, 51.51],
		[0, 0],
		[-179, 179 - 360],
		[12.34567, -98.7654321],
	]) {
		assert.equal(lonDeltaDeg(a, b), b - a, `${a} -> ${b}`);
	}
});

test('a delta across the antimeridian takes the short way', () => {
	assert.ok(Math.abs(lonDeltaDeg(179.99, -179.97) - 0.04) < 1e-9);
	assert.ok(Math.abs(lonDeltaDeg(-179.97, 179.99) + 0.04) < 1e-9);
	assert.ok(Math.abs(lonDeltaDeg(179.9, -179.9) - 0.2) < 1e-9);
	// The plain subtraction is wrong by a whole turn, which is the bug.
	assert.ok(Math.abs(-179.97 - 179.99 + 359.96) < 1e-9);
});

test('opposite meridians resolve consistently rather than flapping', () => {
	assert.equal(lonDeltaDeg(0, 180), -180);
	assert.equal(lonDeltaDeg(0, -180), -180);
	assert.equal(wrapLonDeg(wrapLonDeg(180)), wrapLonDeg(180));
	assert.equal(wrapLonDeg(-180), -180);
});

test('unwrapping leaves a longitude already near the reference untouched', () => {
	for (const [r, lon] of [
		[-105.27, -105.26],
		[0, 179.9],
		[0, -179.9],
		[60, 60],
	]) {
		assert.equal(unwrapLonDeg(r, lon), lon, `${r} ${lon}`);
	}
});

test('unwrapping carries a course past the line instead of jumping it', () => {
	// A course anchored at 179.98 whose far end is at -179.96: the box
	// spans 0.06°, not 359.94.
	const a = 179.98;
	const b = unwrapLonDeg(a, -179.96);
	assert.ok(Math.abs(b - 180.04) < 1e-9, `unwrapped to ${b}`);
	assert.ok(Math.abs(b - a - 0.06) < 1e-9);
	assert.ok(Math.abs(wrapLonDeg(b) - -179.96) < 1e-9);
});

test('a non-finite longitude stays non-finite rather than becoming a number', () => {
	assert.ok(Number.isNaN(lonDeltaDeg(NaN, 0)));
	assert.ok(Number.isNaN(lonDeltaDeg(0, NaN)));
	assert.ok(!Number.isFinite(wrapLonDeg(Infinity)));
	assert.ok(!Number.isFinite(unwrapLonDeg(0, Infinity)));
});
