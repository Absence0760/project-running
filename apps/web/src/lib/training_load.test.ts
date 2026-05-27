import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	computeStress,
	computeCalibration,
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

// Persona-hunt Pro #2: per-window calibration so a strap-less day
// doesn't fake a 3× spike in the daily series.

test('computeCalibration — mode=distance when no HR prefs', () => {
	const cal = computeCalibration([easy5k]);
	assert.equal(cal.mode, 'distance');
	assert.equal(cal.trimpPerKmFallback, null);
});

test('computeCalibration — mode=distance when prefs set but no HR-eligible run', () => {
	const cal = computeCalibration([easy5k], {
		resting_hr_bpm: 50,
		max_hr_bpm: 190,
	});
	assert.equal(cal.mode, 'distance');
});

test('computeCalibration — mode=trimp when at least one run has HR', () => {
	const withHr: RunForLoad = { ...easy5k, metadata: { avg_bpm: 140 } };
	const cal = computeCalibration([withHr], {
		resting_hr_bpm: 50,
		max_hr_bpm: 190,
	});
	assert.equal(cal.mode, 'trimp');
	assert.ok((cal.trimpPerKmFallback ?? 0) > 0,
		'TRIMP-per-km fallback rate must be positive');
});

test('aggregateDailyStress — strap-less day uses calibrated fallback, not legacy 10/km', () => {
	// The pre-fix bug: same effort got TRIMP score on a strap day,
	// distance-fallback (10 pts/km) on a no-strap day → 3× spike.
	// With the fix, both days should land on the same scale.
	const stravaWithHr: RunForLoad = {
		started_at: '2026-04-01T07:00:00Z',
		duration_s: 3600,
		distance_m: 12000,
		metadata: { avg_bpm: 140 },
	};
	const stravaNoHr: RunForLoad = {
		started_at: '2026-04-02T07:00:00Z',
		duration_s: 3600,
		distance_m: 12000,
	};
	const prefs = { resting_hr_bpm: 50, max_hr_bpm: 190 };
	const daily = aggregateDailyStress([stravaWithHr, stravaNoHr], prefs);
	const day1 = daily.get(localDateKey(new Date(stravaWithHr.started_at))) ?? 0;
	const day2 = daily.get(localDateKey(new Date(stravaNoHr.started_at))) ?? 0;
	// Calibrated fallback should land the no-HR day within 50% of the
	// HR day (pre-fix: ~3× off). Both runs are similar duration +
	// distance + effort proxy.
	assert.ok(day1 > 0 && day2 > 0, 'both days produce stress');
	const ratio = day2 / day1;
	assert.ok(
		ratio > 0.5 && ratio < 1.5,
		`Strap-less day (${day2}) should be within 50% of strap day (${day1}); ` +
			`got ratio ${ratio.toFixed(2)} — pre-fix this was ~3×`,
	);
});

test('aggregateDailyStress — pure-distance window (no HR runs) keeps legacy 10/km', () => {
	// A user with no HR data at all stays on the original behaviour
	// so existing dashboards don't shift. easy 5k → 50 stress.
	const daily = aggregateDailyStress([easy5k]);
	const key = localDateKey(new Date(easy5k.started_at));
	assert.equal(daily.get(key), 50);
});

// Persona-hunt Round 2 finding Pro #2: pre-fix, CTL started at 0
// every render and ramped over the first ~6 weeks of the displayed
// window. A pro who's been at CTL ≈ 80 for years saw TSB wrong by
// tens of points for the early-window days. Fix: walk a 126-day
// warm-up window before the displayed window so EWMAs reach steady
// state by day 1 of the chart.
test('computeTrainingLoadSeries — CTL is at steady state on day 1 for an established pro', () => {
	// 6 months of daily 12 km runs ending at the chart's start. This
	// represents a pro whose baseline ramped up before the displayed
	// window. Pre-fix, day 1 of the chart would show ctl ≈ 0; post-
	// fix, day 1 must be near the long-run mean (~120 stress / day at
	// 12 km × 10 = 120, EWMA → 120).
	const ref = new Date('2026-05-01T12:00:00Z');
	const runs: RunForLoad[] = [];
	// 300 days backward from ref so the helper's 126-day warm-up
	// window is fully populated AND has runs trailing back into ages
	// (≫ 3× ATL halflife) for full equilibrium.
	for (let i = 1; i <= 300; i++) {
		const d = new Date(ref);
		d.setDate(d.getDate() - i);
		runs.push({ started_at: d.toISOString(), distance_m: 12000, duration_s: 3600 });
	}
	const series = computeTrainingLoadSeries(runs, {}, 90, ref);
	// Day 1 of the chart (last 90 days starting at ref-89) — should
	// already be at steady state because the warm-up walked
	// 126 days of pre-window runs.
	const day1 = series[0];
	assert.ok(
		day1.ctl > 100,
		`day 1 CTL should be ≈ 120 (steady-state for 12 km/day), got ${day1.ctl}. ` +
			`Pre-fix this was ≈ 0 because the loop ignored pre-window runs.`,
	);
	// TSB at the displayed window's day 1 should be close to 0 (CTL
	// ≈ ATL at steady state). 3× CTL halflife (126 days) gets us to
	// ~95% of the long-run mean; the remaining gap is a small
	// negative TSB. Pre-fix, CTL was 0 and TSB was -120 — the
	// looseness here is about the 5% residual, not the bug.
	assert.ok(
		Math.abs(day1.tsb) < 10,
		`day 1 TSB should be within 10 of 0 at steady state, got ${day1.tsb}. ` +
			`Pre-fix this was -120 (CTL=0). Post-fix the residual is from 3×CTL ` +
			`halflife warm-up not reaching full equilibrium.`,
	);
});

test('computeTrainingLoadSeries — new user with no pre-window history still ramps from 0', () => {
	// Genuine new user: their first run is in week 1 of the chart.
	// Warm-up walk is all zeros, so EWMAs start at 0 — same shape as
	// pre-fix for this case (no regression on truly-new users).
	const ref = new Date('2026-05-01T12:00:00Z');
	const startInWindow = new Date(ref);
	startInWindow.setDate(startInWindow.getDate() - 10);
	const series = computeTrainingLoadSeries(
		[{ started_at: startInWindow.toISOString(), distance_m: 5000, duration_s: 1500 }],
		{},
		90,
		ref,
	);
	// Day 1 of the chart is well before the runner's first run; CTL
	// must still be ~0 there.
	assert.ok(series[0].ctl < 1, `new user day-1 CTL should be ~0, got ${series[0].ctl}`);
});
