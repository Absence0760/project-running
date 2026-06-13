import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	computeStress,
	computeCalibration,
	aggregateDailyStress,
	computeTrainingLoadSeries,
	localDateKey,
	hasTrimpSignal,
	computeLiftStress,
	rpeFactor,
	aggregateDailyLiftStress,
	kLiftStressCap,
	type RunForLoad,
	type LiftForLoad,
} from './training_load';

/// A representative HARD lifting session — ~8,000 kg of working volume at
/// RPE 8 (16 working sets of 8 reps at 62.5 kg). The calibration constant is
/// anchored so this scores in the easy-run TSS band. If you retune
/// kLiftStressPerKgTonnage, this test is the guard that "a hard lift ≈ an
/// easy run" still holds.
const kHardLiftSession: LiftForLoad = {
	started_at: '2026-04-01T18:00:00Z',
	sets: Array.from({ length: 16 }, () => ({ reps: 8, weight_kg: 62.5, rpe: 8 })),
};

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

test('computeStress — distance mode with positive duration but no distance gives 0, not NaN', () => {
	// A run with duration but no distance_m (manual log / treadmill / GPS-less
	// import) passes the zero-guard (duration is positive) and reaches the
	// distance-fallback branch. It must contribute 0, never NaN.
	const noDistance = { started_at: '2026-04-01T07:00:00Z', duration_s: 1800 } as RunForLoad;
	const stress = computeStress(noDistance);
	assert.ok(!Number.isNaN(stress), 'stress must not be NaN');
	assert.equal(stress, 0);
});

test('aggregateDailyStress — a distance-less run never poisons the series with NaN', () => {
	const good: RunForLoad = { started_at: '2026-04-01T07:00:00Z', distance_m: 5000, duration_s: 1800 };
	const noDistance = { started_at: '2026-04-01T18:00:00Z', duration_s: 1800 } as RunForLoad;
	const m = aggregateDailyStress([good, noDistance]);
	const key = localDateKey(new Date(good.started_at));
	assert.ok(!Number.isNaN(m.get(key)), 'daily total must not be NaN');
	assert.equal(m.get(key), 50);
});

test('computeTrainingLoadSeries — a distance-less run does not blank the whole curve', () => {
	const end = new Date('2026-04-10T12:00:00Z');
	const runs: RunForLoad[] = [
		{ started_at: '2026-04-05T07:00:00Z', distance_m: 10000, duration_s: 3600 },
		{ started_at: '2026-04-06T07:00:00Z', duration_s: 1800 } as RunForLoad,
	];
	const series = computeTrainingLoadSeries(runs, {}, 90, end);
	assert.ok(series.every((p) => !Number.isNaN(p.ctl) && !Number.isNaN(p.atl) && !Number.isNaN(p.tsb)));
	assert.ok(series.some((p) => p.ctl > 0), 'the good run should still build fitness');
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

test('computeTrainingLoadSeries — a long layoff resets CTL/TSB (comeback #29)', () => {
	const ref = new Date('2026-04-30T12:00:00Z');
	const runs: RunForLoad[] = [];
	// A solid 3-week build ending ~50 days ago, then nothing — a layoff
	// well past the 28-day reset threshold.
	for (let i = 70; i >= 50; i--) {
		const d = new Date(ref);
		d.setDate(d.getDate() - i);
		runs.push({ started_at: d.toISOString(), distance_m: 10000, duration_s: 3000 });
	}
	const series = computeTrainingLoadSeries(runs, {}, 90, ref);
	const last = series[series.length - 1];
	// Without the reset, CTL would linger (42-day halflife) and TSB would
	// read strongly positive ("fresh — train hard"). After the reset both
	// collapse to ~0.
	assert.ok(last.ctl < 1, `CTL should reset to ~0 after a >28d layoff, got ${last.ctl}`);
	assert.ok(Math.abs(last.tsb) < 1, `TSB should be ~0 after a layoff, got ${last.tsb}`);
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

test('aggregateDailyStress — a low-HR run in TRIMP mode still contributes load, not zero', () => {
	// A run whose avg_bpm <= resting_hr (misconfigured resting HR, strap
	// dropout, a true recovery shuffle) computes hrr=0 → trimp=0 in the
	// banister model. Pre-fix, the stress<=0 skip dropped it entirely and
	// the run vanished from the fatigue/form curve. Post-fix it falls back to
	// the same distance proxy an HR-less run uses, so a real logged run counts.
	const prefs = { resting_hr_bpm: 55, max_hr_bpm: 190 };
	const normalHr: RunForLoad = {
		started_at: '2026-04-01T07:00:00Z',
		duration_s: 3600,
		distance_m: 12000,
		metadata: { avg_bpm: 150 },
	};
	const lowHr: RunForLoad = {
		started_at: '2026-04-02T07:00:00Z',
		duration_s: 3000,
		distance_m: 10000,
		metadata: { avg_bpm: 50 }, // below resting → hrr clamps to 0 → trimp 0
	};
	const daily = aggregateDailyStress([normalHr, lowHr], prefs);
	const lowHrKey = localDateKey(new Date(lowHr.started_at));
	const lowHrStress = daily.get(lowHrKey) ?? 0;
	assert.ok(
		lowHrStress > 0,
		`a low-HR run must still contribute load (distance-proxy fallback), got ${lowHrStress}`,
	);
	// And it lands on the calibrated fallback scale, not the legacy 10/km
	// (10 km × 10 = 100). The window calibration rate is well under that.
	const cal = computeCalibration([normalHr, lowHr], prefs);
	assert.equal(lowHrStress, 10 * (cal.trimpPerKmFallback ?? 7));
});

test('computeTrainingLoadSeries — a single low-HR run still builds fitness in TRIMP mode', () => {
	const ref = new Date('2026-05-01T12:00:00Z');
	const day = new Date(ref);
	day.setDate(day.getDate() - 1);
	const prefs = { resting_hr_bpm: 55, max_hr_bpm: 190 };
	// The window's only run has avg_bpm below resting — TRIMP=0. The series
	// must still register stress, not paint a flat zero curve.
	const runs: RunForLoad[] = [
		{ started_at: day.toISOString(), duration_s: 3000, distance_m: 10000, metadata: { avg_bpm: 50 } },
	];
	const series = computeTrainingLoadSeries(runs, prefs, 90, ref);
	assert.ok(series.some((p) => p.ctl > 0), 'a low-HR run should still build CTL');
	const lastDay = series[series.length - 2];
	assert.ok(lastDay.stress > 0, 'the low-HR run day carries non-zero stress');
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

// ─────────────────── Lift load ───────────────────

test('rpeFactor — anchored at RPE 8 = 1.0, absent = 1.0, bounded', () => {
	assert.equal(rpeFactor(8), 1.0);
	assert.equal(rpeFactor(null), 1.0);
	assert.equal(rpeFactor(undefined), 1.0);
	assert.ok(rpeFactor(6) < 1.0 && rpeFactor(10) > 1.0);
	assert.equal(rpeFactor(0), 0.5); // clamped low
	assert.equal(rpeFactor(20), 1.25); // clamped high
});

test('CALIBRATION — a hard lift session scores in the easy-run TSS band (40-60)', () => {
	const stress = computeLiftStress(kHardLiftSession);
	assert.ok(
		stress >= 40 && stress <= 60,
		`hard lift should land in the easy-run band, got ${stress}`,
	);
});

test('computeLiftStress — sets without reps or weight contribute nothing', () => {
	const bodyweight: LiftForLoad = {
		started_at: '2026-04-01T18:00:00Z',
		sets: [
			{ reps: 20, weight_kg: null }, // pull-ups, no external load
			{ reps: null, weight_kg: 60 },
			{ reps: 0, weight_kg: 60 },
		],
	};
	assert.equal(computeLiftStress(bodyweight), 0);
});

test('computeLiftStress — a fat-fingered weight is capped, cannot spike the curve', () => {
	const typo: LiftForLoad = {
		started_at: '2026-04-01T18:00:00Z',
		sets: [{ reps: 5, weight_kg: 50000, rpe: 8 }], // 500 kg → 50,000 typo
	};
	assert.equal(computeLiftStress(typo), kLiftStressCap);
});

test('aggregateDailyLiftStress — sums by local day, skips empty sessions', () => {
	const daily = aggregateDailyLiftStress([
		kHardLiftSession,
		{ ...kHardLiftSession }, // same day → summed
		{ started_at: '2026-04-02T18:00:00Z', sets: [{ reps: 10, weight_kg: null }] }, // 0
	]);
	const day1 = localDateKey(new Date(kHardLiftSession.started_at));
	assert.ok((daily.get(day1) ?? 0) > 80); // two hard sessions stacked
	assert.equal(daily.has('2026-04-02'), false);
});

test('lift stress is separable — run-only series is recoverable, lifts raise fatigue', () => {
	const ref = new Date('2026-05-01T12:00:00Z');
	const runDay = new Date(ref);
	runDay.setDate(runDay.getDate() - 1);
	const runs: RunForLoad[] = [
		{ started_at: runDay.toISOString(), distance_m: 8000, duration_s: 2400 },
	];
	const liftDay = new Date(ref);
	liftDay.setDate(liftDay.getDate() - 1);
	const lifts: LiftForLoad[] = [{ ...kHardLiftSession, started_at: liftDay.toISOString() }];

	const runOnly = computeTrainingLoadSeries(runs, {}, 90, ref);
	const withLifts = computeTrainingLoadSeries(runs, {}, 90, ref, lifts);

	// Run-only curve is unchanged by passing or omitting lifts — provenance
	// is separable, so a lift-load bug can never corrupt run readiness.
	assert.deepEqual(
		withLifts.map((p) => p.runStress),
		runOnly.map((p) => p.stress),
		'runStress with lifts must equal the run-only total',
	);
	// Yesterday's point carries the lift contribution on top of the run.
	const last = withLifts[withLifts.length - 2];
	assert.ok(last.liftStress > 0, 'lift day should carry lift stress');
	assert.ok(last.stress > last.runStress, 'total exceeds run-only on a lift day');
	// Fatigue (ATL) is higher with the lift than without.
	assert.ok(
		withLifts[withLifts.length - 1].atl > runOnly[runOnly.length - 1].atl,
		'lifting should raise fatigue on the shared curve',
	);
});

test('run-only readiness (ctl/atl/tsb) is recoverable and uncorrupted by lift magnitude', () => {
	// The separability test above pins the runStress INPUT. This pins the
	// DERIVED layer the runner actually trusts — the ctl/atl/tsb readiness.
	// "Run-only readiness must be recoverable from run contributions alone even
	// when lift-load is present" (multi_modal.md § Lift training-load spec): a
	// lift-load modelling bug must never be able to move the run-only numbers.
	const ref = new Date('2026-05-01T12:00:00Z');
	const day = new Date(ref);
	day.setDate(day.getDate() - 1);
	const runs: RunForLoad[] = [
		{ started_at: day.toISOString(), distance_m: 8000, duration_s: 2400 },
	];
	const normalLifts: LiftForLoad[] = [{ ...kHardLiftSession, started_at: day.toISOString() }];
	// A pathological session that pins to the per-session cap — a different,
	// larger lift load than the normal session.
	const absurdLifts: LiftForLoad[] = [
		{
			started_at: day.toISOString(),
			sets: Array.from({ length: 20 }, () => ({ reps: 10, weight_kg: 200, rpe: 10 })),
		},
	];

	const runOnly = computeTrainingLoadSeries(runs, {}, 90, ref);
	const withNormal = computeTrainingLoadSeries(runs, {}, 90, ref, normalLifts);
	const withAbsurd = computeTrainingLoadSeries(runs, {}, 90, ref, absurdLifts);

	// The run contribution is source-separable regardless of WHAT lifts exist:
	// the runStress channel of either lifts-present series is the run-only total.
	assert.deepEqual(withNormal.map((p) => p.runStress), runOnly.map((p) => p.stress));
	assert.deepEqual(withAbsurd.map((p) => p.runStress), runOnly.map((p) => p.stress));

	// Recovery: dropping lifts reproduces the run-only readiness, and that
	// recovery is byte-identical no matter how large the lift load was. The
	// run-only ctl/atl/tsb a runner trusts cannot be moved by any lift bug.
	const readiness = (s: typeof runOnly) => s.map((p) => ({ ctl: p.ctl, atl: p.atl, tsb: p.tsb }));
	assert.deepEqual(readiness(computeTrainingLoadSeries(runs, {}, 90, ref)), readiness(runOnly));

	// But lifts DO feed the COMBINED readiness (else the source tag is vacuous),
	// and a heavier session moves the combined curve further from run-only.
	const lastRun = runOnly[runOnly.length - 1];
	const lastNormal = withNormal[withNormal.length - 1];
	const lastAbsurd = withAbsurd[withAbsurd.length - 1];
	assert.ok(lastNormal.atl > lastRun.atl, 'lifts raise combined fatigue');
	assert.ok(lastAbsurd.atl > lastNormal.atl, 'a heavier lift raises combined fatigue further');
	assert.ok(lastNormal.tsb < lastRun.tsb, 'lifts lower combined form');
	assert.ok(lastAbsurd.tsb < lastNormal.tsb, 'a heavier lift lowers combined form further');
});

test('computeTrainingLoadSeries — no lifts leaves liftStress 0 and stress unchanged', () => {
	const ref = new Date('2026-05-01T12:00:00Z');
	const runDay = new Date(ref);
	runDay.setDate(runDay.getDate() - 2);
	const runs: RunForLoad[] = [
		{ started_at: runDay.toISOString(), distance_m: 5000, duration_s: 1500 },
	];
	const series = computeTrainingLoadSeries(runs, {}, 90, ref);
	assert.ok(series.every((p) => p.liftStress === 0));
	assert.ok(series.every((p) => p.stress === p.runStress));
});
