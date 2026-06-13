import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { validLatLon } from './import';

test('validLatLon — accepts a real coordinate pair', () => {
	assert.deepEqual(validLatLon('40.7128', '-74.0060'), { lat: 40.7128, lng: -74.006 });
	assert.deepEqual(validLatLon('0', '0'), { lat: 0, lng: 0 }); // explicit (0,0) is honoured
});

test('validLatLon — rejects a missing lat or lon (no null-island point)', () => {
	// The bug: a missing attribute was coerced to 0, inserting a (0,0)
	// waypoint that added thousands of km of phantom distance.
	assert.equal(validLatLon(null, '-74.006'), null);
	assert.equal(validLatLon('40.7', null), null);
	assert.equal(validLatLon(undefined, undefined), null);
});

test('validLatLon — rejects a non-numeric attribute', () => {
	assert.equal(validLatLon('bad', '-74.006'), null);
	assert.equal(validLatLon('40.7', 'NaN'), null);
	assert.equal(validLatLon('', ''), null);
});
