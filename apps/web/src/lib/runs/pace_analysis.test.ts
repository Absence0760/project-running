import { test } from 'node:test';
import assert from 'node:assert/strict';
import { analysePacing, gradeAdjustedSplitPaces, EVEN_BAND_PCT } from './pace_analysis';
import { computeRealSplits } from './run_stats';
import type { TrackPoint } from '../types';

const METRES_PER_DEG_LNG = 111_320;
const START_TS = '2026-04-01T07:00:00Z';

/**
 * Equator-aligned synthetic track. `paces` is one seconds-per-km figure per
 * half; each half covers `halfM` metres in `stepM` steps, so the second
 * entry's pace applies from the halfway mark on. `elePerStep` shifts altitude
 * by a fixed amount per step within each half.
 */
function track(opts: {
	halfM: number;
	stepM: number;
	paces: [number, number];
	elePerStep?: [number, number];
	startEle?: number;
}): TrackPoint[] {
	const { halfM, stepM, paces } = opts;
	const stepsPerHalf = Math.round(halfM / stepM);
	const t0 = Date.parse(START_TS);
	const out: TrackPoint[] = [];
	let tMs = t0;
	let ele = opts.startEle;
	for (let half = 0; half < 2; half++) {
		const stepS = (paces[half] * stepM) / 1000;
		const eleStep = opts.elePerStep?.[half] ?? 0;
		for (let i = 0; i < stepsPerHalf; i++) {
			const idx = half * stepsPerHalf + i;
			const p: TrackPoint = {
				lat: 0,
				lng: (idx * stepM) / METRES_PER_DEG_LNG,
				ts: new Date(tMs).toISOString(),
			};
			if (ele != null) p.ele = ele;
			out.push(p);
			tMs += stepS * 1000;
			if (ele != null) ele += eleStep;
		}
	}
	// Closing point so the final step is covered.
	const last: TrackPoint = {
		lat: 0,
		lng: (2 * stepsPerHalf * stepM) / METRES_PER_DEG_LNG,
		ts: new Date(tMs).toISOString(),
	};
	if (ele != null) last.ele = ele;
	out.push(last);
	return out;
}

test('analysePacing returns null without a track, or with one point', () => {
	assert.equal(analysePacing(null), null);
	assert.equal(analysePacing(undefined), null);
	assert.equal(analysePacing([{ lat: 0, lng: 0, ts: START_TS }]), null);
});

test('analysePacing returns null when the track covers no distance', () => {
	const t: TrackPoint[] = [
		{ lat: 0, lng: 0, ts: START_TS },
		{ lat: 0, lng: 0, ts: '2026-04-01T07:05:00Z' },
	];
	assert.equal(analysePacing(t), null);
});

test('analysePacing returns null when the track carries no timestamps', () => {
	const t = track({ halfM: 1000, stepM: 100, paces: [300, 300] }).map(({ lat, lng }) => ({
		lat,
		lng,
	}));
	assert.equal(analysePacing(t), null);
});

test('analysePacing calls a steady run an even split', () => {
	const a = analysePacing(track({ halfM: 2000, stepM: 100, paces: [300, 300] }));
	assert.ok(a);
	assert.equal(a.raw.verdict, 'even');
	assert.equal(a.raw.deltaSecPerKm, 0);
	assert.equal(a.raw.first.paceSecPerKm, 300);
	assert.equal(a.raw.second.paceSecPerKm, 300);
	// No elevation on the track, so GAP carries no information.
	assert.equal(a.gradeAdjusted, null);
});

test('analysePacing splits the halves by distance, not by time', () => {
	// A fading run: if halves were cut by time the slower second half would be
	// short of the halfway mark and both halves would report the same distance
	// only by accident. Cut by distance, they are equal.
	const a = analysePacing(track({ halfM: 2000, stepM: 100, paces: [300, 400] }));
	assert.ok(a);
	assert.ok(Math.abs(a.raw.first.distanceM - a.raw.second.distanceM) < 1);
	assert.equal(a.raw.first.paceSecPerKm, 300);
	assert.equal(a.raw.second.paceSecPerKm, 400);
});

test('analysePacing flags a faster second half as a negative split', () => {
	const a = analysePacing(track({ halfM: 2000, stepM: 100, paces: [300, 270] }));
	assert.ok(a);
	assert.equal(a.raw.verdict, 'negative');
	assert.equal(a.raw.deltaSecPerKm, -30);
});

test('analysePacing flags a slower second half as a positive split', () => {
	const a = analysePacing(track({ halfM: 2000, stepM: 100, paces: [300, 330] }));
	assert.ok(a);
	assert.equal(a.raw.verdict, 'positive');
	assert.equal(a.raw.deltaSecPerKm, 30);
});

test('a drift inside the even band still reads as even, just outside it does not', () => {
	// 2 % of a 300 s/km first half is 6 s/km.
	assert.equal(300 * EVEN_BAND_PCT, 6);
	const inside = analysePacing(track({ halfM: 2000, stepM: 100, paces: [300, 305] }));
	assert.equal(inside?.raw.verdict, 'even');
	const outside = analysePacing(track({ halfM: 2000, stepM: 100, paces: [300, 307] }));
	assert.equal(outside?.raw.verdict, 'positive');
});

test('a second half that climbs reads as a fade raw but even on effort', () => {
	// Same 2 km halves; the second half slows by 24 % while climbing 4 m per
	// 100 m step (a sustained 4 % grade, whose Minetti cost factor is 1.2365 —
	// so 300 s/km of effort is run at 371 s/km). Raw pace fades, effort holds.
	const a = analysePacing(
		track({
			halfM: 2000,
			stepM: 100,
			paces: [300, 371],
			startEle: 100,
			elePerStep: [0, 4],
		})
	);
	assert.ok(a);
	assert.equal(a.raw.verdict, 'positive');
	assert.ok(a.gradeAdjusted);
	assert.equal(a.gradeAdjusted.verdict, 'even');
	assert.equal(a.gradeAdjusted.firstSecPerKm, 300);
	assert.equal(a.gradeAdjusted.secondSecPerKm, 300);
});

test('gradeAdjustedSplitPaces returns one aligned entry per split', () => {
	const t = track({ halfM: 2000, stepM: 100, paces: [300, 371], startEle: 100, elePerStep: [0, 4] });
	const splits = computeRealSplits(t, 1000);
	const gap = gradeAdjustedSplitPaces(t, splits);
	assert.equal(gap.length, splits.length);
	assert.equal(splits.length, 4);
	// Splits 1-2 are flat: GAP is the pace they were run at.
	assert.equal(gap[0], splits[0].pace_s);
	assert.equal(gap[1], splits[1].pace_s);
	// Splits 3-4 climb: GAP is faster than the raw pace they were run at.
	assert.ok(gap[2] != null && gap[2] < splits[2].pace_s);
	assert.ok(gap[3] != null && gap[3] < splits[3].pace_s);
});

test('gradeAdjustedSplitPaces is null for a split with no elevation', () => {
	const t = track({ halfM: 2000, stepM: 100, paces: [300, 300] });
	const splits = computeRealSplits(t, 1000);
	assert.equal(splits.length, 4);
	assert.deepEqual(
		gradeAdjustedSplitPaces(t, splits),
		splits.map(() => null)
	);
});

test('gradeAdjustedSplitPaces degenerates safely', () => {
	assert.deepEqual(gradeAdjustedSplitPaces(null, []), []);
	const splits = computeRealSplits(track({ halfM: 1000, stepM: 100, paces: [300, 300] }), 1000);
	assert.ok(splits.length > 0);
	assert.deepEqual(
		gradeAdjustedSplitPaces(null, splits),
		splits.map(() => null)
	);
	assert.deepEqual(
		gradeAdjustedSplitPaces([{ lat: 0, lng: 0 }], splits),
		splits.map(() => null)
	);
});

test('halves stay sane across the antimeridian', () => {
	// Four points straddling 180°: a plain longitude subtraction at the cut
	// would place the interpolated boundary point most of a turn away and
	// blow the two halves' distances apart.
	const t: TrackPoint[] = [
		{ lat: 0, lng: 179.98, ts: '2026-04-01T07:00:00Z' },
		{ lat: 0, lng: 179.99, ts: '2026-04-01T07:03:00Z' },
		{ lat: 0, lng: -179.99, ts: '2026-04-01T07:09:00Z' },
		{ lat: 0, lng: -179.98, ts: '2026-04-01T07:12:00Z' },
	];
	const a = analysePacing(t);
	assert.ok(a);
	assert.ok(Math.abs(a.raw.first.distanceM - a.raw.second.distanceM) < 1);
	assert.ok(a.raw.first.distanceM < 3000);
});
