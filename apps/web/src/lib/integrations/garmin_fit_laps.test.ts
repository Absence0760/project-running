import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	buildCanonicalLaps,
	garminExternalId,
	fitCadenceToSpm,
	normalizeSubSport,
	buildRunningDynamics,
	buildHrZonesFromFit,
} from './garmin-fit';

test('fitCadenceToSpm — doubles per-foot RPM for foot sports', () => {
	// FIT reports running cadence per foot; the runner-facing spm is ×2.
	assert.equal(fitCadenceToSpm(85, true), 170);
	assert.equal(fitCadenceToSpm(90.5, true), 181); // rounds
});

test('fitCadenceToSpm — null for cycling (crank RPM, not a step rate)', () => {
	assert.equal(fitCadenceToSpm(90, false), null);
});

test('fitCadenceToSpm — null for missing / non-positive / non-finite', () => {
	assert.equal(fitCadenceToSpm(undefined, true), null);
	assert.equal(fitCadenceToSpm(0, true), null);
	assert.equal(fitCadenceToSpm(-5, true), null);
	assert.equal(fitCadenceToSpm(Number.NaN, true), null);
	assert.equal(fitCadenceToSpm('85', true), null);
});

test('garminExternalId — prefixes the file id, or null when absent', () => {
	assert.equal(garminExternalId('1700000000-12345'), 'garmin:1700000000-12345');
	assert.equal(garminExternalId(null), null);
	assert.equal(garminExternalId(''), null);
});

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

test('normalizeSubSport — preserves a trail run discipline', () => {
	// F1: a trail run collapses to a generic activity_type='run'; the
	// sub_sport datum is what tells the runner it was a trail.
	assert.equal(normalizeSubSport('trail'), 'trail');
	assert.equal(normalizeSubSport('Trail'), 'trail');
	assert.equal(normalizeSubSport('  TREADMILL '), 'treadmill');
	assert.equal(normalizeSubSport('track'), 'track');
});

test('normalizeSubSport — drops uninformative / missing placeholders to null', () => {
	assert.equal(normalizeSubSport('generic'), null);
	assert.equal(normalizeSubSport('all'), null);
	assert.equal(normalizeSubSport('invalid'), null);
	assert.equal(normalizeSubSport(''), null);
	assert.equal(normalizeSubSport('   '), null);
	assert.equal(normalizeSubSport(undefined), null);
	assert.equal(normalizeSubSport(null), null);
	assert.equal(normalizeSubSport(42), null);
});

test('buildRunningDynamics — projects the fields a Running pod recorded', () => {
	// F2: avg_* off the session; step length mm → m; rest pass through.
	const rd = buildRunningDynamics({
		avg_vertical_oscillation: 8.42,
		avg_stance_time: 245.6,
		avg_step_length: 1180,
		avg_power: 312,
	});
	assert.deepEqual(rd, {
		vertical_oscillation_mm: 8.4,
		gct_ms: 246,
		stride_length_m: 1.18,
		power_w: 312,
	});
});

test('buildRunningDynamics — only populates fields the file actually carried', () => {
	const rd = buildRunningDynamics({ avg_power: 280 });
	assert.deepEqual(rd, { power_w: 280 });
	// No sentinel zeros / nulls for the fields the watch never recorded.
	assert.equal('vertical_oscillation_mm' in rd!, false);
	assert.equal('power_w' in rd!, true);
});

test('buildRunningDynamics — falls back to per-record field names', () => {
	const rd = buildRunningDynamics({ vertical_oscillation: 9, stance_time: 250 });
	assert.deepEqual(rd, { vertical_oscillation_mm: 9, gct_ms: 250 });
});

test('buildRunningDynamics — drops out-of-range / non-finite values', () => {
	// A base watch with no Running pod: nothing → null, not an empty object.
	assert.equal(buildRunningDynamics({}), null);
	assert.equal(buildRunningDynamics(null), null);
	assert.equal(buildRunningDynamics(undefined), null);
	// Non-positive / non-finite metrics are ignored.
	assert.equal(buildRunningDynamics({ avg_power: 0, avg_vertical_oscillation: -1 }), null);
	assert.equal(buildRunningDynamics({ avg_power: Number.NaN }), null);
});

test('buildHrZonesFromFit — maps a 5-zone high_bpm set to z1..z5', () => {
	const zones = [
		{ high_bpm: 120 },
		{ high_bpm: 140 },
		{ high_bpm: 160 },
		{ high_bpm: 175 },
		{ high_bpm: 190 },
	];
	assert.deepEqual(buildHrZonesFromFit(zones), {
		z1: 120,
		z2: 140,
		z3: 160,
		z4: 175,
		z5: 190,
	});
});

test('buildHrZonesFromFit — drops a leading resting-zone-0 entry (6 zones)', () => {
	const zones = [
		{ high_bpm: 90 }, // resting zone 0
		{ high_bpm: 120 },
		{ high_bpm: 140 },
		{ high_bpm: 160 },
		{ high_bpm: 175 },
		{ high_bpm: 190 },
	];
	assert.deepEqual(buildHrZonesFromFit(zones), {
		z1: 120,
		z2: 140,
		z3: 160,
		z4: 175,
		z5: 190,
	});
});

test('buildHrZonesFromFit — null when fewer than five usable boundaries', () => {
	assert.equal(buildHrZonesFromFit([{ high_bpm: 120 }, { high_bpm: 140 }]), null);
	assert.equal(buildHrZonesFromFit([]), null);
	assert.equal(buildHrZonesFromFit(null), null);
});

test('buildHrZonesFromFit — ignores out-of-range / non-numeric boundaries', () => {
	const zones = [
		{ high_bpm: 0 },
		{ high_bpm: 300 },
		{ high_bpm: 'x' },
		{ high_bpm: 120 },
		{ high_bpm: 140 },
		{ high_bpm: 160 },
		{ high_bpm: 175 },
		{ high_bpm: 190 },
	];
	assert.deepEqual(buildHrZonesFromFit(zones), {
		z1: 120,
		z2: 140,
		z3: 160,
		z4: 175,
		z5: 190,
	});
});
