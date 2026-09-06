import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	MINETTI_FLAT_COST,
	MAX_GRADE,
	minettiCostAtGrade,
	gradeFactor,
	gradeAdjustedPaceSecPerKm,
	MIN_SEGMENT_M,
} from './grade_adjusted_pace';
import { ELEVATION_GAIN_MIN_DELTA_M } from '../routes/route_simplify';
import type { TrackPoint } from '../types';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { stripComments } from '../core/strip_comments';

/// Mirror of `apps/mobile_android/test/grade_adjusted_pace_test.dart`. Keep in
/// lockstep — the GAP figure shown on web run detail and on mobile run detail
/// (and the on-watch Connect IQ field) all derive from this Minetti model.

/// Build a straight east-west track at a constant horizontal speed and a
/// constant grade. `gradePct` is rise/run as a percentage; `eleStart` is the
/// first point's elevation.
function gradedTrack(opts: {
	points: number;
	stepM: number;
	stepS: number;
	gradePct: number;
	eleStart?: number;
	withEle?: boolean;
	withTs?: boolean;
}): TrackPoint[] {
	const lat = 40;
	const t0 = Date.parse('2026-01-01T00:00:00Z');
	const degPerM = 1 / (111_320 * Math.cos((lat * Math.PI) / 180));
	const withEle = opts.withEle ?? true;
	const withTs = opts.withTs ?? true;
	const out: TrackPoint[] = [];
	let ele = opts.eleStart ?? 100;
	for (let i = 0; i < opts.points; i++) {
		const p: TrackPoint = { lat, lng: -100 + i * opts.stepM * degPerM };
		if (withEle) p.ele = ele;
		if (withTs) p.ts = new Date(t0 + i * opts.stepS * 1000).toISOString();
		out.push(p);
		ele += (opts.gradePct / 100) * opts.stepM;
	}
	return out;
}

test('Minetti cost at flat is the cached flat constant', () => {
	assert.equal(minettiCostAtGrade(0), MINETTI_FLAT_COST);
	assert.equal(gradeFactor(0), 1);
});

test('uphill costs more than flat, downhill (gentle) costs less', () => {
	assert.ok(gradeFactor(0.1) > 1, 'a 10% climb should cost more than flat');
	assert.ok(gradeFactor(-0.1) < 1, 'a gentle 10% descent should cost less than flat');
});

test('grade is clamped to Minetti valid range', () => {
	assert.equal(gradeFactor(0.9), gradeFactor(MAX_GRADE));
	assert.equal(gradeFactor(-0.9), gradeFactor(-MAX_GRADE));
});

test('flat run: GAP equals raw pace', () => {
	// 5 m/s flat = 200 s/km raw. With zero grade every factor is 1.
	const track = gradedTrack({ points: 60, stepM: 5, stepS: 1, gradePct: 0 });
	const gap = gradeAdjustedPaceSecPerKm(track);
	assert.ok(gap != null);
	assert.equal(gap, 200);
});

test('uphill run: GAP is faster than raw pace (less effort would be needed on flat)', () => {
	// Climbing at 10% — same raw speed costs more effort, so the
	// effort-equivalent flat pace is FASTER (smaller s/km) than raw.
	const track = gradedTrack({ points: 60, stepM: 5, stepS: 1, gradePct: 10 });
	const rawPace = 200; // 5 m/s
	const gap = gradeAdjustedPaceSecPerKm(track);
	assert.ok(gap != null);
	assert.ok(gap < rawPace, `expected GAP ${gap} to be faster than raw ${rawPace}`);
});

test('descent run: GAP is slower than raw pace (downhill is easy)', () => {
	const track = gradedTrack({ points: 60, stepM: 5, stepS: 1, gradePct: -10 });
	const rawPace = 200;
	const gap = gradeAdjustedPaceSecPerKm(track);
	assert.ok(gap != null);
	assert.ok(gap > rawPace, `expected GAP ${gap} to be slower than raw ${rawPace}`);
});

test('no elevation data: GAP is null (would just equal raw pace)', () => {
	const track = gradedTrack({ points: 60, stepM: 5, stepS: 1, gradePct: 10, withEle: false });
	assert.equal(gradeAdjustedPaceSecPerKm(track), null);
});

test('no timestamps: GAP is null (no segment durations)', () => {
	const track = gradedTrack({ points: 60, stepM: 5, stepS: 1, gradePct: 10, withTs: false });
	assert.equal(gradeAdjustedPaceSecPerKm(track), null);
});

test('too few points: GAP is null', () => {
	assert.equal(gradeAdjustedPaceSecPerKm(null), null);
	assert.equal(gradeAdjustedPaceSecPerKm([]), null);
	assert.equal(gradeAdjustedPaceSecPerKm([{ lat: 40, lng: -100, ele: 100, ts: '2026-01-01T00:00:00Z' }]), null);
});

test('mixed track with some missing elevation still computes from graded segments', () => {
	const track = gradedTrack({ points: 60, stepM: 5, stepS: 1, gradePct: 10 });
	// Drop elevation on a handful of mid-run points — segments around them
	// fall back to factor 1, but the run as a whole still has grade signal.
	for (let i = 20; i < 25; i++) delete track[i].ele;
	const gap = gradeAdjustedPaceSecPerKm(track);
	assert.ok(gap != null);
	assert.ok(gap < 200, 'still adjusted for the climb on the graded segments');
});

test('the grade window is longer than the noise floor the gain path discards', () => {
	// The finding this window's value exists to answer, stated as the
	// relationship rather than as the number: the largest altitude change
	// `computeElevationGain` throws away as noise, taken over the shortest run
	// a grade is measured across, must not read as a wall.
	//
	// At the 5 m this shipped with, 3 m of noise was a 0.60 grade — past
	// MAX_GRADE, so it clamped, and the factor was 5.396. A rise nothing else
	// in the app is willing to call climb reported an effort-pace 5.4x faster
	// than raw. Nothing gates the rise and nothing can: a threshold big enough
	// to suppress that noise suppresses every real grade below
	// `threshold / window` with it.
	const noiseFloorGrade = ELEVATION_GAIN_MIN_DELTA_M / MIN_SEGMENT_M;
	assert.ok(
		noiseFloorGrade < MAX_GRADE,
		`a window of ${MIN_SEGMENT_M} m makes the ${ELEVATION_GAIN_MIN_DELTA_M} m noise floor a ${noiseFloorGrade} grade, past the steepest the Minetti fit is defined at`,
	);
	assert.ok(
		gradeFactor(noiseFloorGrade) < 2.1,
		`the noise floor alone must not more than double the reported effort; it multiplies it by ${gradeFactor(noiseFloorGrade)}`,
	);
});

/// The GAP reference track: a clean, noise-free 6% climb switchbacking
/// +/-8 m every 150 m, walked at 5 m every 3 s for 3 km — the 30-minute
/// power-hike-paced staircase decisions § 992 measured the window's cost on,
/// and the profile that binds its UPPER end. Points sit on a line of constant
/// latitude, where the haversine collapses exactly to R * dLambda, so the
/// per-pair horizontal step below is a closed form rather than a second copy
/// of the module's own distance function.
///
/// Frozen on three rails — this file, `grade_adjusted_pace_test.dart` and the
/// firmware's `grade_adjusted_pace.rs` — and compared between them by
/// `scripts/check_watch_wire_vectors.mjs`, which reads all eight constants out
/// of each. A fixture that drifts on one rail makes its golden meaningless
/// rather than wrong, which is the failure nothing would otherwise report
/// (decisions § 641).
const GAP_REFERENCE_POINTS = 601;
const GAP_REFERENCE_STEP_M = 5.0;
const GAP_REFERENCE_STEP_S = 3;
const GAP_REFERENCE_BASE_GRADE = 0.06;
const GAP_REFERENCE_AMPLITUDE_M = 8.0;
const GAP_REFERENCE_PERIOD_M = 150.0;
const GAP_REFERENCE_S_PER_KM = 311;
const GAP_REFERENCE_MAX_COST = 0.03;

const GAP_REFERENCE_HORIZ_STEP_M = (6_371_000 * ((GAP_REFERENCE_STEP_M / 111_320) * Math.PI)) / 180;

function gapReferenceTrack(amplitudeM = GAP_REFERENCE_AMPLITUDE_M): TrackPoint[] {
	const t0 = Date.parse('2026-01-01T00:00:00Z');
	const out: TrackPoint[] = [];
	for (let i = 0; i < GAP_REFERENCE_POINTS; i++) {
		const x = i * GAP_REFERENCE_STEP_M;
		out.push({
			lat: 0,
			lng: x / 111_320,
			ele:
				100 +
				GAP_REFERENCE_BASE_GRADE * x +
				amplitudeM * Math.sin((2 * Math.PI * x) / GAP_REFERENCE_PERIOD_M),
			ts: new Date(t0 + i * GAP_REFERENCE_STEP_S * 1000).toISOString()
		});
	}
	return out;
}

/// The same walk with no window at all: every point pair graded on its own
/// rise over its own run. This is what the runner actually spent, and what a
/// window can only approximate — a window wider than the terrain averages the
/// climbs and the drops together and hands back a flatter course than the one
/// underfoot.
function gapReferenceTruthSecPerKm(track: TrackPoint[]): number {
	let adjDistM = 0;
	for (let i = 1; i < track.length; i++) {
		const rise = (track[i].ele ?? 0) - (track[i - 1].ele ?? 0);
		adjDistM += GAP_REFERENCE_HORIZ_STEP_M * gradeFactor(rise / GAP_REFERENCE_HORIZ_STEP_M);
	}
	const timeS = (track.length - 1) * GAP_REFERENCE_STEP_S;
	return timeS / (adjDistM / 1000);
}

test('the reference geometry measures the horizontal step the module does', () => {
	// Ties the closed form above to the module's own haversine: with no
	// oscillation and no base grade every factor is exactly 1, so the reported
	// GAP is the raw pace that step implies. Without this the truth below would
	// be graded against a distance nothing had checked.
	const flat = gapReferenceTrack(0).map((p) => ({ ...p, ele: 100 }));
	const timeS = (GAP_REFERENCE_POINTS - 1) * GAP_REFERENCE_STEP_S;
	const horizM = GAP_REFERENCE_HORIZ_STEP_M * (GAP_REFERENCE_POINTS - 1);
	assert.equal(gradeAdjustedPaceSecPerKm(flat), Math.round(timeS / (horizM / 1000)));
});

test('the grade window is short enough to keep the reference track', () => {
	// The other end of the bracket. The noise-floor test above states the FLOOR
	// — it admits nothing under 19.40 m — and would pass at 200 m, a window
	// long enough to erase the terrain outright. This states the CEILING, as
	// decisions § 992 stated it: on the most oscillating realistic profile
	// measured, the window may not cost more than 3% against the truth.
	//
	// Measured on this fixture, reported against truth 302.611 s/km:
	//   5 m -> 304 (-0.46%)   15 m -> 308 (-1.78%)   20 m -> 311 (-2.77%)
	//   25 m -> 316 (-4.42%)  30 m -> 322 (-6.41%)   200 m -> 426 (-40.78%)
	// so the pair of tests together admits only [19.40 m, 24.97 m]. The 5 m
	// point spacing is what makes the ceiling 24.97 rather than 25: the walk
	// closes a segment on the first pair that clears the window, so what is
	// really bounded is the EFFECTIVE segment, which is the honest bound.
	const track = gapReferenceTrack();
	const truth = gapReferenceTruthSecPerKm(track);
	const reported = gradeAdjustedPaceSecPerKm(track);
	assert.ok(reported != null);
	const cost = Math.abs(reported - truth) / truth;
	assert.ok(
		cost < GAP_REFERENCE_MAX_COST,
		`a ${MIN_SEGMENT_M} m window reports ${reported} s/km against a true ${truth.toFixed(3)} s/km on the reference switchback — ${(cost * 100).toFixed(2)}% of the climb averaged away`
	);
	assert.equal(
		reported,
		GAP_REFERENCE_S_PER_KM,
		'the reference track no longer grades to its frozen value: the window, the fixture or the Minetti fit moved. Re-measure the cost against truth before updating this number, and update the Dart and firmware rails with it'
	);
});

test('a track shorter than one window yields no grade-adjusted pace', () => {
	// Proof that the walk reads the constant rather than a literal: four
	// quarter-window steps carry elevation and a duration, and still never
	// complete a segment, so there is no grade anyone can vouch for and the
	// helper says so instead of grading the jitter.
	const track = gradedTrack({ points: 4, stepM: MIN_SEGMENT_M / 4, stepS: 1, gradePct: 10 });
	assert.equal(gradeAdjustedPaceSecPerKm(track), null);
});

test('a near-antipodal fix pair does not erase the whole run\'s grade-adjusted pace', () => {
	// The walk used a PRIVATE copy of `haversineMetres` that never got the
	// clamp `run_stats.ts` grew: on (-87.5, 0) -> (87.5, 180) the haversine `a`
	// rounds to 1.0000000000000002, `Math.sqrt(1 - a)` is NaN, and the distance
	// came back NaN. Every downstream guard is NaN-permissive — `NaN <
	// MIN_SEGMENT_M` is false so the anchor walk never resets again, and `NaN
	// <= 0` is false so the null return is skipped — so ONE corrupt fix pair
	// returned NaN out of a `number | null` signature, and the run-detail
	// page's GAP cell, GAP split column and grade-adjusted pacing verdict all
	// vanished together (each is gated on `Math.abs(gap - raw) >= 2`, which NaN
	// fails). The Dart twin imports the clamped helper from `run_stats.dart`
	// and was never affected; this side now does too.
	const track: TrackPoint[] = [
		{ lat: -87.5, lng: 0, ele: 100, ts: '2026-01-01T00:00:00Z' },
		{ lat: 87.5, lng: 180, ele: 110, ts: '2026-01-01T01:00:00Z' },
		{ lat: 87.5, lng: 180.001, ele: 120, ts: '2026-01-01T02:00:00Z' },
	];
	const gap = gradeAdjustedPaceSecPerKm(track);
	assert.ok(gap != null, 'the pair grades to a real distance, so GAP is stateable');
	assert.ok(Number.isFinite(gap), `GAP must be a number, got ${gap}`);
});

test('the walk measures distance with the shared clamped haversine, not a copy', () => {
	// The copy is how the divergence happened and how it stayed invisible: the
	// clamp landed in `run_stats.ts` (and in `run_stats.dart`, which the Dart
	// twin of THIS module imports) while this file kept its own unclamped
	// `Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))`. Nothing compares two
	// helpers on the same platform, so only the pair's own suites could have
	// caught it and neither had an antipodal case.
	const source = stripComments(
		readFileSync(resolve(import.meta.dirname, './grade_adjusted_pace.ts'), 'utf-8'),
	);
	assert.match(
		source,
		/import \{[^}]*\bhaversineMetres\b[^}]*\} from '\.\/run_stats'/,
		'grade_adjusted_pace must take its distances from the shared helper',
	);
	assert.doesNotMatch(
		source,
		/function haversineMetres\(/,
		'a second copy of the great-circle formula in this file is the defect itself',
	);
});

test('a non-finite coordinate never leaves NaN in the return type', () => {
	// The signature is `number | null`. `segHoriz` goes NaN on a bad fix,
	// `NaN < MIN_SEGMENT_M` is false so the walk enters the body, and the old
	// `adjDistM <= 0` guard is false for NaN — so `Math.round(NaN)` was
	// returned as a pace. The Dart twin THREW on the same input, from a widget
	// build, because `.round()` refuses a non-finite double.
	const track: TrackPoint[] = [
		{ lat: 51.5, lng: -0.1, ele: 10, ts: '2026-01-01T00:00:00Z' },
		{ lat: Number.NaN, lng: -0.1, ele: 20, ts: '2026-01-01T00:05:00Z' },
		{ lat: 51.5, lng: -0.09, ele: 30, ts: '2026-01-01T00:10:00Z' },
	];
	const gap = gradeAdjustedPaceSecPerKm(track);
	assert.ok(gap === null || Number.isFinite(gap), `GAP must be null or a number, got ${gap}`);
});

test('one bad fix does not erase the GAP of the run around it', () => {
	// The durable half. A single unusable segment is skipped the way a segment
	// with no timestamps already is, rather than poisoning the accumulator and
	// discarding every good segment in a three-hour ultra with it.
	const good: TrackPoint[] = [];
	for (let i = 0; i <= 40; i++) {
		good.push({
			lat: 46 + i * 0.0005,
			lng: 7,
			ele: 1800 + i * 2,
			ts: new Date(Date.UTC(2026, 0, 1, 0, i, 0)).toISOString(),
		});
	}
	const clean = gradeAdjustedPaceSecPerKm(good);
	assert.ok(clean != null && Number.isFinite(clean));

	const spoiled = good.slice();
	spoiled[20] = { ...spoiled[20], lat: Number.POSITIVE_INFINITY };
	const withBadFix = gradeAdjustedPaceSecPerKm(spoiled);
	assert.ok(withBadFix != null, 'one bad fix must not erase the whole run');
	assert.ok(Number.isFinite(withBadFix));
	assert.ok(
		Math.abs(withBadFix - clean) < clean * 0.1,
		`a single skipped segment should barely move GAP: ${clean} -> ${withBadFix}`,
	);
});

test('a non-finite altitude is not a measured grade', () => {
	// The other way in: `b.ele - a.ele` is NaN, `gradeFactor` clamps neither
	// bound of a NaN, and `minettiCostAtGrade(NaN)` is NaN. The segment is
	// skipped, so it also does not count as having SEEN elevation.
	const track: TrackPoint[] = [
		{ lat: 46, lng: 7, ele: Number.NaN, ts: '2026-01-01T00:00:00Z' },
		{ lat: 46.0005, lng: 7, ele: Number.NaN, ts: '2026-01-01T00:01:00Z' },
		{ lat: 46.001, lng: 7, ele: Number.NaN, ts: '2026-01-01T00:02:00Z' },
	];
	assert.equal(gradeAdjustedPaceSecPerKm(track), null);
});
