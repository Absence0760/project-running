import { test } from 'node:test';
import assert from 'node:assert/strict';
import { projectRunner, CUTOFF_TIGHT_S, type ProjectionCheckpoint } from './checkpoint_projection';

const cps: ProjectionCheckpoint[] = [
	{ id: 'a', positionM: 10_000, cutoffElapsedS: null },
	{ id: 'b', positionM: 20_000, cutoffElapsedS: 7_200 }, // 2h cutoff at 20k
	{ id: 'c', positionM: 40_000, cutoffElapsedS: 18_000 } // 5h cutoff at finish
];

test('no crossings → racing, no pace, nothing reached', () => {
	const p = projectRunner(cps, []);
	assert.equal(p.status, 'racing');
	assert.equal(p.paceSPerM, null);
	assert.equal(p.lastCheckpointId, null);
	assert.equal(p.coveredM, 0);
	assert.ok(p.legs.every((l) => !l.reached));
	assert.ok(p.legs.every((l) => l.projectedElapsedS === null));
});

test('one crossing sets pace and last checkpoint', () => {
	const p = projectRunner(cps, [{ checkpointId: 'a', elapsedS: 3_600 }]);
	assert.equal(p.lastCheckpointId, 'a');
	assert.equal(p.lastElapsedS, 3_600);
	assert.equal(p.coveredM, 10_000);
	assert.equal(p.paceSPerM, 3_600 / 10_000); // 0.36 s/m == 6:00/km
	assert.equal(p.status, 'racing');
});

test('future checkpoints are linearly projected from pace', () => {
	const p = projectRunner(cps, [{ checkpointId: 'a', elapsedS: 3_600 }]);
	const b = p.legs.find((l) => l.checkpointId === 'b')!;
	const c = p.legs.find((l) => l.checkpointId === 'c')!;
	assert.equal(b.projectedElapsedS, 0.36 * 20_000); // 7200
	assert.equal(c.projectedElapsedS, 0.36 * 40_000); // 14400
});

test('projected arrival exactly on the cutoff is tight, not miss', () => {
	// pace 0.36 → projected b = 7200 == cutoff 7200 → margin 0 → tight
	const p = projectRunner(cps, [{ checkpointId: 'a', elapsedS: 3_600 }]);
	const b = p.legs.find((l) => l.checkpointId === 'b')!;
	assert.equal(b.cutoff!.marginS, 0);
	assert.equal(b.cutoff!.status, 'tight');
});

test('comfortable projection is safe', () => {
	// faster: 30 min to 10k → 0.18 s/m → b projected 3600, margin 3600 > tight
	const p = projectRunner(cps, [{ checkpointId: 'a', elapsedS: 1_800 }]);
	const b = p.legs.find((l) => l.checkpointId === 'b')!;
	assert.equal(b.cutoff!.status, 'safe');
	assert.ok(b.cutoff!.marginS > CUTOFF_TIGHT_S);
});

test('slow projection blows a future cutoff (miss), still racing until reached', () => {
	// 90 min to 10k → 0.54 s/m → b projected 10800 > 7200 cutoff → miss
	const p = projectRunner(cps, [{ checkpointId: 'a', elapsedS: 5_400 }]);
	const b = p.legs.find((l) => l.checkpointId === 'b')!;
	assert.equal(b.cutoff!.status, 'miss');
	assert.ok(b.cutoff!.marginS < 0);
	assert.equal(p.status, 'racing'); // projected miss is a warning, not a DNF
});

test('a reached checkpoint past its cutoff is a DNF', () => {
	const p = projectRunner(cps, [
		{ checkpointId: 'a', elapsedS: 3_600 },
		{ checkpointId: 'b', elapsedS: 7_500 } // arrived after the 7200 cutoff
	]);
	const b = p.legs.find((l) => l.checkpointId === 'b')!;
	assert.equal(b.reached, true);
	assert.equal(b.cutoff!.status, 'miss');
	assert.equal(p.status, 'dnf');
});

test('reaching the last checkpoint within cutoff is finished', () => {
	const p = projectRunner(cps, [
		{ checkpointId: 'a', elapsedS: 3_600 },
		{ checkpointId: 'b', elapsedS: 7_000 },
		{ checkpointId: 'c', elapsedS: 16_000 }
	]);
	assert.equal(p.status, 'finished');
	assert.equal(p.lastCheckpointId, 'c');
});

test('checkpoints are sorted by position before projecting', () => {
	const unsorted: ProjectionCheckpoint[] = [cps[2], cps[0], cps[1]];
	const p = projectRunner(unsorted, [{ checkpointId: 'a', elapsedS: 3_600 }]);
	assert.deepEqual(
		p.legs.map((l) => l.checkpointId),
		['a', 'b', 'c']
	);
});

test('a reached checkpoint has no projection, only an actual', () => {
	const p = projectRunner(cps, [{ checkpointId: 'a', elapsedS: 3_600 }]);
	const a = p.legs.find((l) => l.checkpointId === 'a')!;
	assert.equal(a.reached, true);
	assert.equal(a.actualElapsedS, 3_600);
	assert.equal(a.projectedElapsedS, null);
});

test('a cutoff co-located with the last-reached checkpoint is graded on the exact arrival', () => {
	// An aid station and a cutoff gate share the same distance (separate rows).
	// The runner crosses the aid station at 7000s; the co-located cutoff is not
	// individually logged, but arrival there is known exactly (== the crossing).
	const coLocated: ProjectionCheckpoint[] = [
		{ id: 'aid', positionM: 20_000, cutoffElapsedS: null },
		{ id: 'gate', positionM: 20_000, cutoffElapsedS: 7_200 }
	];
	const p = projectRunner(coLocated, [{ checkpointId: 'aid', elapsedS: 7_000 }]);
	const gate = p.legs.find((l) => l.checkpointId === 'gate')!;
	assert.equal(gate.reached, false);
	assert.equal(gate.projectedElapsedS, 7_000); // paceSPerM * coveredM === lastElapsedS
	assert.notEqual(gate.cutoff, null);
	assert.equal(gate.cutoff!.marginS, 200);
	assert.equal(gate.cutoff!.status, 'tight');
});

test('a crossing stamped at elapsed 0 leaves future cutoffs ungraded, not "safe"', () => {
	// A volunteer's tablet running a minute fast (or the RD firing Go after a
	// start-area checkpoint already scanned) clamps to elapsed 0 upstream. Pace
	// then computed as 0 s/m — finite, so every remaining checkpoint projected
	// an arrival of 0 and graded "safe" with the full cutoff as its margin: the
	// board told the race director a runner was clear of every gate ahead.
	const p = projectRunner(cps, [{ checkpointId: 'a', elapsedS: 0 }]);
	assert.equal(p.paceSPerM, null, 'a zero-elapsed sample yields no usable pace');
	for (const leg of p.legs.filter((l) => !l.reached)) {
		assert.equal(leg.projectedElapsedS, null, `${leg.checkpointId} must not project`);
		assert.equal(leg.cutoff, null, `${leg.checkpointId} must stay ungraded`);
	}
});

test('a negative elapsed crossing is equally unusable', () => {
	const p = projectRunner(cps, [{ checkpointId: 'a', elapsedS: -120 }]);
	assert.equal(p.paceSPerM, null);
	assert.equal(p.legs.filter((l) => l.cutoff !== null).length, 0);
});

test('the smallest genuinely-positive elapsed still projects', () => {
	// The guard must reject only the unusable sample, not clamp real early data:
	// a fast runner through a near-start checkpoint is legitimate.
	const p = projectRunner(cps, [{ checkpointId: 'a', elapsedS: 1 }]);
	assert.notEqual(p.paceSPerM, null);
	const b = p.legs.find((l) => l.checkpointId === 'b')!;
	assert.notEqual(b.projectedElapsedS, null);
	assert.notEqual(b.cutoff, null);
});

test('a zero-elapsed crossing does not mask a later usable one', () => {
	// Two stamps: the bogus start-area one and a real mid-course crossing. The
	// later checkpoint is the one that sets pace, so the board still works.
	const p = projectRunner(cps, [
		{ checkpointId: 'a', elapsedS: 0 },
		{ checkpointId: 'b', elapsedS: 7_200 }
	]);
	assert.notEqual(p.paceSPerM, null);
	assert.equal(p.lastElapsedS, 7_200);
});

test('a crossing with a non-finite elapsed time is not a crossing', () => {
	// The board derives elapsed from `new Date(in_time).getTime() - start`, so
	// an unparseable stamp arrives here as NaN. It used to be admitted: the
	// runner read as REACHED at that checkpoint, `NaN < 0` and
	// `NaN < CUTOFF_TIGHT_S` both answered false, and the ladder's terminal
	// branch told a race director `safe` about a crossing nothing could time.
	const p = projectRunner(cps, [{ checkpointId: 'b', elapsedS: NaN }]);
	const b = p.legs.find((l) => l.checkpointId === 'b');
	assert.equal(b?.reached, false);
	assert.equal(b?.cutoff, null);
	assert.equal(p.lastCheckpointId, null);
	assert.equal(p.lastElapsedS, null);
	assert.equal(p.paceSPerM, null);
	assert.equal(p.status, 'racing');
});

test('an unusable stamp on the last checkpoint does not read as finished', () => {
	// The status ladder is `blownCutoff ? dnf : reachedLast ? finished`, so an
	// admitted NaN at the final checkpoint promoted the runner to `finished`
	// with every cutoff on the board graded safe.
	const p = projectRunner(cps, [{ checkpointId: 'c', elapsedS: Infinity }]);
	assert.equal(p.status, 'racing');
	assert.ok(p.legs.every((l) => !l.reached));
	assert.ok(p.legs.every((l) => l.cutoff === null));
});

test('an unusable stamp does not mask a usable one at the same checkpoint', () => {
	const p = projectRunner(cps, [
		{ checkpointId: 'b', elapsedS: NaN },
		{ checkpointId: 'b', elapsedS: 6_000 }
	]);
	assert.equal(p.lastElapsedS, 6_000);
	assert.equal(p.legs.find((l) => l.checkpointId === 'b')?.cutoff?.status, 'tight');
});

test('a cutoff that is not a number leaves the leg ungraded', () => {
	const bad: ProjectionCheckpoint[] = [
		{ id: 'a', positionM: 10_000, cutoffElapsedS: NaN }
	];
	const p = projectRunner(bad, [{ checkpointId: 'a', elapsedS: 3_600 }]);
	assert.equal(p.legs[0].reached, true);
	assert.equal(p.legs[0].cutoff, null);
});
