import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	pickAutoEffortRoute,
	buildSegmentEffortRows,
	type SegmentForEffort,
} from './auto_segment_effort';
import type { TrackPoint } from '../types';

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

/// A straight constant-pace track ~stepM per sample, ~stepS per sample.
function straightTrack(samples: number, stepM = 10, stepS = 5): TrackPoint[] {
	const out: TrackPoint[] = [];
	const dLat = stepM / 111_320; // metres per degree latitude
	let t = Date.UTC(2026, 0, 1, 0, 0, 0);
	for (let i = 0; i < samples; i++) {
		out.push({ lat: 40 + i * dLat, lng: -105, ts: new Date(t).toISOString() } as TrackPoint);
		t += stepS * 1000;
	}
	return out;
}

test('buildSegmentEffortRows — one row per matched segment, unmatched skipped', () => {
	const track = straightTrack(200); // ~2 km, dense
	const segments: SegmentForEffort[] = [
		{ id: 'seg-1', start_distance_m: 100, end_distance_m: 600 },
		{ id: 'seg-2', start_distance_m: 800, end_distance_m: 1400 },
		{ id: 'seg-off-track', start_distance_m: 5000, end_distance_m: 6000 }, // beyond track → skipped
	];
	const rows = buildSegmentEffortRows(segments, track, { run_id: 'run-1', user_id: 'user-1' });
	assert.equal(rows.length, 2);
	assert.deepEqual(
		rows.map((r) => r.segment_id),
		['seg-1', 'seg-2'],
	);
	for (const r of rows) {
		assert.equal(r.run_id, 'run-1');
		assert.equal(r.user_id, 'user-1');
		assert.ok(r.time_seconds > 0);
		assert.equal(typeof r.started_at, 'string');
	}
});

test('buildSegmentEffortRows — accepts string-typed distance columns', () => {
	const rows = buildSegmentEffortRows(
		[{ id: 'seg-1', start_distance_m: '100', end_distance_m: '600' }],
		straightTrack(200),
		{ run_id: 'r', user_id: 'u' },
	);
	assert.equal(rows.length, 1);
});

test('buildSegmentEffortRows — empty segment set returns []', () => {
	assert.deepEqual(
		buildSegmentEffortRows([], straightTrack(50), { run_id: 'r', user_id: 'u' }),
		[],
	);
});
