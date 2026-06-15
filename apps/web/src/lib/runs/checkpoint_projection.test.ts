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
