import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	computeStress,
	aggregateDailyStress,
	computeTrainingLoadSeries,
	localDateKey,
	hasTrimpSignal,
	type RunForLoad,
} from './training_load';

const easy5k: RunForLoad = {
	started_at: '2026-04-01T07:00:00Z',
	duration_s: 1800,
	distance_m: 5000,
};

test('computeStress — distance fallback gives 50 for an easy 5k', () => {
	assert.equal(computeStress(easy5k), 50);
});

test('computeStress — TRIMP path lights up when avg_bpm + rest + max are all set', () => {
	const run: RunForLoad = {
		started_at: '2026-04-01T07:00:00Z',
		duration_s: 3600,
		distance_m: 10000,
		metadata: { avg_bpm: 150 },
	};
	const trimp = computeStress(run, { resting_hr_bpm: 50, max_hr_bpm: 190 });
	const distance = computeStress(run);
	// They should differ — the whole point of TRIMP is intensity weighting.
	assert.notEqual(trimp, distance);
	assert.ok(trimp > 0);
});

test('computeStress — zero distance + zero duration gives 0', () => {
	assert.equal(computeStress({ started_at: '2026-04-01T00:00:00Z', distance_m: 0, duration_s: 0 }), 0);
});

test('aggregateDailyStress — sums same-day runs', () => {
	const a: RunForLoad = { started_at: '2026-04-01T07:00:00Z', distance_m: 5000, duration_s: 1500 };
	const b: RunForLoad = { started_at: '2026-04-01T18:00:00Z', distance_m: 3000, duration_s: 900 };
	const m = aggregateDailyStress([a, b]);
	const key = localDateKey(new Date(a.started_at));
	assert.equal(m.get(key), 80);
});

test('computeTrainingLoadSeries — emits exactly windowDays entries', () => {
	const series = computeTrainingLoadSeries([], {}, 30, new Date('2026-04-30T12:00:00Z'));
	assert.equal(series.length, 30);
});

test('computeTrainingLoadSeries — TSB rises during taper (no runs after a build)', () => {
	const runs: RunForLoad[] = [];
	// Two weeks of daily 5k runs ending two weeks before the end date,
	// then nothing — TSB should swing positive by the end.
	const ref = new Date('2026-04-30T12:00:00Z');
	for (let i = 28; i >= 14; i--) {
		const d = new Date(ref);
		d.setDate(d.getDate() - i);
		runs.push({ started_at: d.toISOString(), distance_m: 5000, duration_s: 1500 });
	}
	const series = computeTrainingLoadSeries(runs, {}, 60, ref);
	const last = series[series.length - 1];
	assert.ok(last.tsb > 0, 'TSB should be positive after a 14-day taper');
});

test('computeTrainingLoadSeries — series is 0 with no runs', () => {
	const series = computeTrainingLoadSeries([], {}, 30, new Date('2026-04-30T12:00:00Z'));
	assert.ok(series.every((p) => p.atl === 0 && p.ctl === 0 && p.tsb === 0));
});

test('hasTrimpSignal — false when no avg_bpm', () => {
	assert.equal(hasTrimpSignal([easy5k], { resting_hr_bpm: 50, max_hr_bpm: 190 }), false);
});

test('hasTrimpSignal — true when at least one run has avg_bpm and prefs are set', () => {
	const withHr: RunForLoad = { ...easy5k, metadata: { avg_bpm: 150 } };
	assert.equal(hasTrimpSignal([withHr], { resting_hr_bpm: 50, max_hr_bpm: 190 }), true);
});

test('hasTrimpSignal — false when prefs missing', () => {
	const withHr: RunForLoad = { ...easy5k, metadata: { avg_bpm: 150 } };
	assert.equal(hasTrimpSignal([withHr]), false);
});
