import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { pickAutoEffortRoute } from './auto_segment_effort';

test('pickAutoEffortRoute — one strong end-to-end match returns its id', () => {
	const id = pickAutoEffortRoute(
		[{ id: 'r1', distanceM: 5000, startOffsetM: 20, endOffsetM: 30 }],
		5050,
	);
	assert.equal(id, 'r1');
});

test('pickAutoEffortRoute — length mismatch (>20%) is not a match', () => {
	const id = pickAutoEffortRoute(
		[{ id: 'r1', distanceM: 5000, startOffsetM: 20, endOffsetM: 30 }],
		8000,
	);
	assert.equal(id, null);
});

test('pickAutoEffortRoute — high offsets (run only crosses the route) is not a match', () => {
	const id = pickAutoEffortRoute(
		[{ id: 'r1', distanceM: 5000, startOffsetM: 1800, endOffsetM: 2200 }],
		5000,
	);
	assert.equal(id, null);
});

test('pickAutoEffortRoute — ambiguous (two strong matches) returns null', () => {
	const id = pickAutoEffortRoute(
		[
			{ id: 'r1', distanceM: 5000, startOffsetM: 20, endOffsetM: 30 },
			{ id: 'r2', distanceM: 5020, startOffsetM: 15, endOffsetM: 25 },
		],
		5000,
	);
	assert.equal(id, null);
});

test('pickAutoEffortRoute — empty candidates / zero length return null', () => {
	assert.equal(pickAutoEffortRoute([], 5000), null);
	assert.equal(
		pickAutoEffortRoute([{ id: 'r1', distanceM: 5000, startOffsetM: 0, endOffsetM: 0 }], 0),
		null,
	);
});
