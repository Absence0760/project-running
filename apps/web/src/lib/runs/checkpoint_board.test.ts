import assert from 'node:assert/strict';
import { test } from 'node:test';

import { buildBoard, crossingKey, type BoardCheckpoint } from './checkpoint_board';

const START = Date.parse('2026-06-14T08:00:00Z');

function atElapsed(seconds: number): string {
	return new Date(START + seconds * 1000).toISOString();
}

const checkpoints: BoardCheckpoint[] = [
	{ id: 'cp1', name: 'Aid 1', ordinal: 1, positionM: 10_000, cutoffElapsedS: 3600 },
	{ id: 'cp2', name: 'Aid 2', ordinal: 2, positionM: 20_000, cutoffElapsedS: 7200 },
	{ id: 'cp3', name: 'Finish', ordinal: 3, positionM: 30_000, cutoffElapsedS: 11_400 }
];

test('crossingKey prefers user_id, falls back to bib', () => {
	assert.equal(crossingKey({ userId: 'u1', bib: '42' }), 'u1');
	assert.equal(crossingKey({ userId: null, bib: '42' }), 'bib:42');
});

test('groups crossings by runner identity', () => {
	const board = buildBoard(
		checkpoints,
		[
			{ checkpointId: 'cp1', userId: 'u1', bib: null, runnerName: 'Ann', inTime: atElapsed(1800) },
			{ checkpointId: 'cp1', userId: null, bib: '7', runnerName: 'Bob', inTime: atElapsed(1900) }
		],
		START
	);
	assert.equal(board.length, 2);
	assert.deepEqual(
		board.map((r) => r.key).sort(),
		['bib:7', 'u1']
	);
});

test('projects a reached checkpoint as safe when inside cutoff', () => {
	const board = buildBoard(
		checkpoints,
		[{ checkpointId: 'cp1', userId: 'u1', bib: null, runnerName: 'Ann', inTime: atElapsed(1800) }],
		START
	);
	const ann = board[0];
	const cp1 = ann.projection.legs.find((l) => l.checkpointId === 'cp1')!;
	assert.equal(cp1.reached, true);
	assert.equal(cp1.actualElapsedS, 1800);
	assert.equal(cp1.cutoff?.status, 'safe');
});

test('flags a runner DNF when a reached checkpoint blows its cutoff', () => {
	const board = buildBoard(
		checkpoints,
		[{ checkpointId: 'cp1', userId: 'u1', bib: null, runnerName: 'Ann', inTime: atElapsed(4000) }],
		START
	);
	const cp1 = board[0].projection.legs.find((l) => l.checkpointId === 'cp1')!;
	assert.equal(cp1.cutoff?.status, 'miss');
	assert.equal(board[0].projection.status, 'dnf');
});

test('out-only crossings contribute no elapsed sample', () => {
	const board = buildBoard(
		checkpoints,
		[{ checkpointId: 'cp1', userId: 'u1', bib: null, runnerName: 'Ann', inTime: null }],
		START
	);
	const cp1 = board[0].projection.legs.find((l) => l.checkpointId === 'cp1')!;
	assert.equal(cp1.reached, false);
	assert.equal(board[0].projection.coveredM, 0);
});

test('sorts furthest-covered runner first, then the leader by elapsed', () => {
	const board = buildBoard(
		checkpoints,
		[
			// Ann reached cp2; Bob only cp1; Cara cp1 but earlier than Bob.
			{ checkpointId: 'cp1', userId: 'ann', bib: null, runnerName: 'Ann', inTime: atElapsed(1800) },
			{ checkpointId: 'cp2', userId: 'ann', bib: null, runnerName: 'Ann', inTime: atElapsed(3600) },
			{ checkpointId: 'cp1', userId: 'bob', bib: null, runnerName: 'Bob', inTime: atElapsed(2000) },
			{ checkpointId: 'cp1', userId: 'cara', bib: null, runnerName: 'Cara', inTime: atElapsed(1700) }
		],
		START
	);
	assert.deepEqual(
		board.map((r) => r.userId),
		['ann', 'cara', 'bob']
	);
});

test('projects a future checkpoint from pace when not yet reached', () => {
	// Reached cp1 (10km) at 1800s → 0.18 s/m → cp2 (20km) projects to 3600s.
	const board = buildBoard(
		checkpoints,
		[{ checkpointId: 'cp1', userId: 'u1', bib: null, runnerName: 'Ann', inTime: atElapsed(1800) }],
		START
	);
	const cp2 = board[0].projection.legs.find((l) => l.checkpointId === 'cp2')!;
	assert.equal(cp2.reached, false);
	assert.equal(cp2.projectedElapsedS, 3600);
	assert.equal(cp2.cutoff?.status, 'safe');
});

test('marks finished when the last checkpoint is reached', () => {
	const board = buildBoard(
		checkpoints,
		[
			{ checkpointId: 'cp1', userId: 'u1', bib: null, runnerName: 'Ann', inTime: atElapsed(1800) },
			{ checkpointId: 'cp2', userId: 'u1', bib: null, runnerName: 'Ann', inTime: atElapsed(3600) },
			{ checkpointId: 'cp3', userId: 'u1', bib: null, runnerName: 'Ann', inTime: atElapsed(5400) }
		],
		START
	);
	assert.equal(board[0].projection.status, 'finished');
});

test('empty crossings yields an empty board', () => {
	assert.deepEqual(buildBoard(checkpoints, [], START), []);
});

test('two fully-tied runners hold a deterministic order regardless of fetch order', () => {
	// Both reached cp1 at the same elapsed time — a full tie on coveredM AND
	// lastElapsedS. The board must not jitter when the underlying crossing
	// list arrives in a different order between refreshes.
	const tied = (order: ['aaa' | 'zzz', 'aaa' | 'zzz']) =>
		buildBoard(
			checkpoints,
			order.map((id) => ({
				checkpointId: 'cp1',
				userId: id,
				bib: null,
				runnerName: id,
				inTime: atElapsed(1800)
			})),
			START
		).map((r) => r.userId);

	const forward = tied(['aaa', 'zzz']);
	const reversed = tied(['zzz', 'aaa']);
	assert.deepEqual(forward, reversed); // identical on every client / refresh
	assert.deepEqual(forward, ['aaa', 'zzz']); // ordered by the stable key tie-break
});
