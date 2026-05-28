import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { buildCanonicalLaps } from './garmin-fit';

test('buildCanonicalLaps — empty / null / single lap yields no laps', () => {
	// A single lap is the whole-activity lap (runner never pressed lap), so
	// a one-element array carries no information — drop it.
	assert.deepEqual(buildCanonicalLaps(undefined), []);
	assert.deepEqual(buildCanonicalLaps(null), []);
	assert.deepEqual(buildCanonicalLaps([]), []);
	assert.deepEqual(buildCanonicalLaps([{ total_distance: 5000, total_timer_time: 1500 }]), []);
});

test('buildCanonicalLaps — multi-lap produces 1-based index + cumulative-before offsets', () => {
	const laps = buildCanonicalLaps([
		{ total_distance: 1000, total_timer_time: 300 },
		{ total_distance: 1000, total_timer_time: 310 },
		{ total_distance: 800, total_timer_time: 250 },
	]);
	assert.equal(laps.length, 3);
	assert.deepEqual(
		laps.map((l) => l.index),
		[1, 2, 3],
	);
	// start_offset_s == cumulative duration of prior laps; first lap = 0.
	assert.deepEqual(
		laps.map((l) => l.start_offset_s),
		[0, 300, 610],
	);
	assert.deepEqual(
		laps.map((l) => l.distance_m),
		[1000, 1000, 800],
	);
	assert.deepEqual(
		laps.map((l) => l.duration_s),
		[300, 310, 250],
	);
});

test('buildCanonicalLaps — falls back to total_elapsed_time when timer time is absent', () => {
	const laps = buildCanonicalLaps([
		{ total_distance: 1000, total_elapsed_time: 300 },
		{ total_distance: 1000, total_elapsed_time: 305 },
	]);
	assert.deepEqual(
		laps.map((l) => l.duration_s),
		[300, 305],
	);
	assert.deepEqual(
		laps.map((l) => l.start_offset_s),
		[0, 300],
	);
});

test('buildCanonicalLaps — clamps missing/negative distance + rounds fractional duration', () => {
	const laps = buildCanonicalLaps([
		{ total_timer_time: 300.4 },
		{ total_distance: -50, total_timer_time: 299.6 },
	]);
	assert.equal(laps[0].distance_m, 0);
	assert.equal(laps[1].distance_m, 0);
	assert.equal(laps[0].duration_s, 300);
	assert.equal(laps[1].duration_s, 300);
	assert.deepEqual(
		laps.map((l) => l.start_offset_s),
		[0, 300],
	);
});
