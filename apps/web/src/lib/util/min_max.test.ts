import { test } from 'node:test';
import assert from 'node:assert/strict';
import { minMax } from './min_max.js';

test('minMax: empty array returns null', () => {
	assert.equal(minMax([]), null);
});

test('minMax: single element is both min and max', () => {
	assert.deepEqual(minMax([42]), { min: 42, max: 42 });
});

test('minMax: typical elevation series', () => {
	assert.deepEqual(minMax([120, 95, 200, 150, 80]), { min: 80, max: 200 });
});

test('minMax: handles negatives (below-sea-level elevations / longitudes)', () => {
	assert.deepEqual(minMax([-3.2, -118.4, -0.1, -120.0]), { min: -120.0, max: -0.1 });
});

test('minMax: does not overflow the call stack on a 180k-point ultra track', () => {
	// Math.min(...arr) / Math.max(...arr) throw RangeError past ~110k args in
	// V8. A 50-hour ultra at 1 Hz is ~180k samples — the exact case that
	// crashed the elevation chart and the map bounds computation.
	const n = 180_000;
	const values = new Array<number>(n);
	for (let i = 0; i < n; i++) values[i] = Math.sin(i) * 1000;
	// The lowest/highest sin values land deterministically inside the range.
	values[12345] = -9999;
	values[67890] = 9999;

	const result = minMax(values);
	assert.deepEqual(result, { min: -9999, max: 9999 });
});

test('minMax: spread baseline actually overflows (documents why this helper exists)', () => {
	const values = new Array<number>(200_000).fill(1);
	assert.throws(() => Math.min(...values), RangeError);
});
