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

test('a track shorter than one window yields no grade-adjusted pace', () => {
	// Proof that the walk reads the constant rather than a literal: four
	// quarter-window steps carry elevation and a duration, and still never
	// complete a segment, so there is no grade anyone can vouch for and the
	// helper says so instead of grading the jitter.
	const track = gradedTrack({ points: 4, stepM: MIN_SEGMENT_M / 4, stepS: 1, gradePct: 10 });
	assert.equal(gradeAdjustedPaceSecPerKm(track), null);
});
