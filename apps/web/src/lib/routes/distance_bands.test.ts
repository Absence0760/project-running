import assert from 'node:assert/strict';
import { test } from 'node:test';

import { bandForDistance, bandsToRanges, DISTANCE_BANDS } from './distance_bands';

test('bandForDistance maps nominal race distances to their band', () => {
	assert.equal(bandForDistance(5000)?.key, '5k');
	assert.equal(bandForDistance(10000)?.key, '10k');
	assert.equal(bandForDistance(21097)?.key, 'half'); // half marathon
	assert.equal(bandForDistance(42195)?.key, 'marathon'); // marathon
	assert.equal(bandForDistance(50000)?.key, 'ultra');
	assert.equal(bandForDistance(160934)?.key, 'ultra'); // 100 miles
});

test('bandForDistance tolerates real-world wobble around the nominal', () => {
	assert.equal(bandForDistance(4200)?.key, '5k');
	assert.equal(bandForDistance(5900)?.key, '5k');
	assert.equal(bandForDistance(11500)?.key, '10k');
});

test('bandForDistance returns null in the gaps between race distances', () => {
	assert.equal(bandForDistance(3000), null); // below 5k floor
	assert.equal(bandForDistance(7000), null); // between 5k and 10k
	assert.equal(bandForDistance(15000), null); // between 10k and half
	assert.equal(bandForDistance(30000), null); // between half and marathon
});

test('band edges are half-open [min, max)', () => {
	// 6000 is the exclusive upper edge of 5k — it is NOT a 5k.
	assert.equal(bandForDistance(6000), null);
	// 44500 is the marathon upper edge and the ultra lower edge.
	assert.equal(bandForDistance(44499)?.key, 'marathon');
	assert.equal(bandForDistance(44500)?.key, 'ultra');
});

test('bandsToRanges returns nulls when nothing is selected', () => {
	assert.deepEqual(bandsToRanges([]), { min: null, max: null });
});

test('bandsToRanges builds parallel arrays for a single band', () => {
	assert.deepEqual(bandsToRanges(['5k']), { min: [4000], max: [6000] });
});

test('bandsToRanges carries an open-ended upper bound for ultra', () => {
	assert.deepEqual(bandsToRanges(['ultra']), { min: [44500], max: [null] });
});

test('bandsToRanges output order follows DISTANCE_BANDS, not input order', () => {
	const r = bandsToRanges(['ultra', '5k', 'half']);
	assert.deepEqual(r.min, [4000, 19000, 44500]);
	assert.deepEqual(r.max, [6000, 23000, null]);
});

test('every band key in DISTANCE_BANDS round-trips through bandsToRanges', () => {
	const keys = DISTANCE_BANDS.map((b) => b.key);
	const r = bandsToRanges(keys);
	assert.equal(r.min?.length, DISTANCE_BANDS.length);
	assert.equal(r.max?.length, DISTANCE_BANDS.length);
});
