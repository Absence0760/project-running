// Unit tests for the multi-distance race predictor. Run with:
//   npx tsx --test src/lib/training/race_predictor.test.ts
//
// Mirrors race_predictor.dart — keep the case set + count in lockstep.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	predictRaceLadder,
	RACE_LADDER_M,
	ANCHOR_RECENCY_HALFLIFE_DAYS,
	type EffortForPrediction,
} from './race_predictor';
import { riegelPredict } from './training';

test('empty pool returns null', () => {
	assert.equal(predictRaceLadder([]), null);
});

test('non-finite / non-positive efforts are filtered out, empty -> null', () => {
	const bad: EffortForPrediction[] = [
		{ distanceM: 0, durationS: 1200, ageDays: 1 },
		{ distanceM: 5000, durationS: 0, ageDays: 1 },
		{ distanceM: 5000, durationS: 1200, ageDays: Number.NaN },
	];
	assert.equal(predictRaceLadder(bad), null);
});

test('one effort produces a full ladder with all four rungs', () => {
	const out = predictRaceLadder([{ distanceM: 5000, durationS: 1200, ageDays: 3 }]);
	assert.ok(out);
	assert.equal(out.rungs.length, RACE_LADDER_M.length);
	assert.deepEqual(
		out.rungs.map((r) => r.distanceM),
		[...RACE_LADDER_M],
	);
});

test('rungs project from the chosen anchor via Riegel (numbers match the engine)', () => {
	const out = predictRaceLadder([{ distanceM: 5000, durationS: 1200, ageDays: 0 }]);
	assert.ok(out);
	for (const r of out.rungs) {
		const expected = riegelPredict(5000, 1200, r.distanceM);
		assert.ok(Math.abs(r.predictedSec - expected) < 1e-6);
	}
});

test('pace is finish-time over distance in km', () => {
	const out = predictRaceLadder([{ distanceM: 10_000, durationS: 2400, ageDays: 1 }]);
	assert.ok(out);
	const tenK = out.rungs.find((r) => r.distanceM === 10_000)!;
	// 2400 s over 10 km = 240 s/km.
	assert.ok(Math.abs(tenK.paceSecPerKm - 240) < 1e-6);
});

test('a recent effort out-anchors a faster-but-stale PR', () => {
	// The stale PR is genuinely faster (4:00/km 10K vs 4:30/km 10K) but two
	// half-lives old; the fresh effort should win the anchor on recency.
	const stalePr: EffortForPrediction = {
		distanceM: 10_000,
		durationS: 2400,
		ageDays: 2 * ANCHOR_RECENCY_HALFLIFE_DAYS,
	};
	const fresh: EffortForPrediction = { distanceM: 10_000, durationS: 2700, ageDays: 0 };
	const out = predictRaceLadder([stalePr, fresh]);
	assert.ok(out);
	assert.equal(out.anchor.durationS, 2700);
	assert.equal(out.anchor.ageDays, 0);
});

test('a recent PR still wins when it is also the fastest', () => {
	const recentPr: EffortForPrediction = { distanceM: 10_000, durationS: 2400, ageDays: 1 };
	const slower: EffortForPrediction = { distanceM: 10_000, durationS: 3000, ageDays: 1 };
	const out = predictRaceLadder([slower, recentPr]);
	assert.ok(out);
	assert.equal(out.anchor.durationS, 2400);
});

test('qualifyingCount reflects the filtered pool size', () => {
	const out = predictRaceLadder([
		{ distanceM: 5000, durationS: 1200, ageDays: 1 },
		{ distanceM: 10_000, durationS: 2700, ageDays: 5 },
		{ distanceM: 0, durationS: 999, ageDays: 1 }, // dropped
	]);
	assert.ok(out);
	assert.equal(out.qualifyingCount, 2);
});

test('a 10K anchor grades the marathon rung lower than the 10K rung', () => {
	// 10K -> Marathon is a 4.2x extrapolation (past the RIEGEL_FAR_FACTOR cap)
	// so it must be low; the 10K rung itself (same distance, recent, but only
	// one effort) is moderate-or-better, never below the marathon.
	const out = predictRaceLadder([{ distanceM: 10_000, durationS: 2400, ageDays: 1 }]);
	assert.ok(out);
	const tenK = out.rungs.find((r) => r.distanceM === 10_000)!;
	const marathon = out.rungs.find((r) => r.distanceM === 42_195)!;
	assert.equal(marathon.quality.confidence, 'low');
	assert.notEqual(tenK.quality.confidence, 'low');
});

test('a stale-only pool still produces a prediction (no null-out)', () => {
	const out = predictRaceLadder([
		{ distanceM: 10_000, durationS: 2700, ageDays: 5000 },
	]);
	assert.ok(out);
	assert.equal(out.rungs.length, RACE_LADDER_M.length);
	// And the staleness shows up in the confidence grade.
	const tenK = out.rungs.find((r) => r.distanceM === 10_000)!;
	assert.equal(tenK.quality.confidence, 'low');
	assert.equal(tenK.quality.reason, 'stale');
});

test('future-dated effort (clock skew) is treated as weight 1, not amplified', () => {
	// A negative ageDays must not produce a >1 weight that lets it beat a
	// genuinely-recent effort of the same raw quality on something other than
	// raw speed. Same raw time + same effective recency -> the tie resolves to
	// the first scanned, and neither is inflated. We just assert it anchors and
	// the ageDays is carried through unchanged.
	const out = predictRaceLadder([{ distanceM: 5000, durationS: 1200, ageDays: -3 }]);
	assert.ok(out);
	assert.equal(out.anchor.ageDays, -3);
});
