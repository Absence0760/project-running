import { test } from 'node:test';
import assert from 'node:assert/strict';

import { summariseRoutineHistory, type RoutineSessionRow } from './routine_history';

const NOW = Date.parse('2026-08-15T12:00:00.000Z');

function row(over: Partial<RoutineSessionRow> & { id: string; started_at: string }): RoutineSessionRow {
	return { title: null, metadata: {}, ...over };
}

test('no rows yields an empty history the caller can self-hide on', () => {
	const h = summariseRoutineHistory([], NOW);
	assert.equal(h.sessionCount, 0);
	assert.equal(h.lastPerformedAt, null);
	assert.equal(h.daysSinceLast, null);
	assert.equal(h.completedRate, null);
	assert.equal(h.gradedCount, 0);
	assert.deepEqual(h.sessions, []);
});

test('sessions are ordered newest first regardless of input order', () => {
	const h = summariseRoutineHistory(
		[
			row({ id: 'a', started_at: '2026-08-01T10:00:00.000Z' }),
			row({ id: 'c', started_at: '2026-08-12T10:00:00.000Z' }),
			row({ id: 'b', started_at: '2026-08-05T10:00:00.000Z' }),
		],
		NOW,
	);
	assert.deepEqual(
		h.sessions.map((s) => s.id),
		['c', 'b', 'a'],
	);
	assert.equal(h.lastPerformedAt, '2026-08-12T10:00:00.000Z');
});

test('an in-flight draft row is not a performed session', () => {
	const h = summariseRoutineHistory(
		[
			row({ id: 'done', started_at: '2026-08-10T10:00:00.000Z', metadata: { gym_adherence: 'completed' } }),
			row({
				id: 'draft',
				started_at: '2026-08-14T10:00:00.000Z',
				metadata: { routine_id: 'r1', gym_session_draft: { saved_at: '2026-08-14T10:05:00.000Z', results: [] } },
			}),
		],
		NOW,
	);
	assert.equal(h.sessionCount, 1);
	assert.equal(h.sessions[0].id, 'done');
	assert.equal(h.lastPerformedAt, '2026-08-10T10:00:00.000Z');
});

test('a save-as-is row counts as a session but is ungraded, not completed', () => {
	const h = summariseRoutineHistory(
		[row({ id: 'x', started_at: '2026-08-10T10:00:00.000Z', metadata: { routine_id: 'r1' } })],
		NOW,
	);
	assert.equal(h.sessionCount, 1);
	assert.equal(h.sessions[0].verdict, 'ungraded');
	assert.equal(h.gradedCount, 0);
	assert.equal(h.completedCount, 0);
	assert.equal(h.completedRate, null);
});

test('each stored verdict is carried through and counted', () => {
	const h = summariseRoutineHistory(
		[
			row({ id: 'a', started_at: '2026-08-01T10:00:00.000Z', metadata: { gym_adherence: 'completed' } }),
			row({ id: 'b', started_at: '2026-08-02T10:00:00.000Z', metadata: { gym_adherence: 'partial' } }),
			row({ id: 'c', started_at: '2026-08-03T10:00:00.000Z', metadata: { gym_adherence: 'abandoned' } }),
			row({ id: 'd', started_at: '2026-08-04T10:00:00.000Z', metadata: { gym_adherence: 'completed' } }),
		],
		NOW,
	);
	assert.deepEqual(
		h.sessions.map((s) => s.verdict),
		['completed', 'abandoned', 'partial', 'completed'],
	);
	assert.equal(h.gradedCount, 4);
	assert.equal(h.completedCount, 2);
	assert.equal(h.completedRate, 0.5);
});

test('an ungraded session is excluded from the rate denominator, not counted as a miss', () => {
	const h = summariseRoutineHistory(
		[
			row({ id: 'a', started_at: '2026-08-01T10:00:00.000Z', metadata: { gym_adherence: 'completed' } }),
			row({ id: 'b', started_at: '2026-08-02T10:00:00.000Z', metadata: { routine_id: 'r1' } }),
		],
		NOW,
	);
	assert.equal(h.sessionCount, 2);
	assert.equal(h.gradedCount, 1);
	assert.equal(h.completedRate, 1);
});

test('an unrecognised verdict string is ungraded rather than trusted', () => {
	const h = summariseRoutineHistory(
		[row({ id: 'a', started_at: '2026-08-01T10:00:00.000Z', metadata: { gym_adherence: 'crushed_it' } })],
		NOW,
	);
	assert.equal(h.sessions[0].verdict, 'ungraded');
	assert.equal(h.gradedCount, 0);
});

test('a null or non-object metadata bag degrades to ungraded', () => {
	const h = summariseRoutineHistory(
		[
			row({ id: 'a', started_at: '2026-08-01T10:00:00.000Z', metadata: null }),
			row({ id: 'b', started_at: '2026-08-02T10:00:00.000Z', metadata: 'nonsense' }),
			{ id: 'c', started_at: '2026-08-03T10:00:00.000Z' },
		],
		NOW,
	);
	assert.equal(h.sessionCount, 3);
	assert.equal(h.gradedCount, 0);
});

test('days since last is whole elapsed days, floored', () => {
	const h = summariseRoutineHistory(
		[row({ id: 'a', started_at: '2026-08-12T23:00:00.000Z' })],
		NOW,
	);
	assert.equal(h.daysSinceLast, 2);
});

test('a session stamped ahead of the clock reads as today, never negative', () => {
	const h = summariseRoutineHistory(
		[row({ id: 'a', started_at: '2026-08-20T10:00:00.000Z' })],
		NOW,
	);
	assert.equal(h.daysSinceLast, 0);
});

test('an unparseable start time is dropped rather than sorted as NaN', () => {
	const h = summariseRoutineHistory(
		[
			row({ id: 'bad', started_at: 'not-a-date' }),
			row({ id: 'good', started_at: '2026-08-10T10:00:00.000Z' }),
		],
		NOW,
	);
	assert.equal(h.sessionCount, 1);
	assert.equal(h.sessions[0].id, 'good');
});

test('a row with no id is dropped rather than rendered as an unlinkable session', () => {
	const h = summariseRoutineHistory(
		[{ id: '', started_at: '2026-08-10T10:00:00.000Z' }],
		NOW,
	);
	assert.equal(h.sessionCount, 0);
});

test('the workout title rides along for the session list', () => {
	const h = summariseRoutineHistory(
		[row({ id: 'a', started_at: '2026-08-10T10:00:00.000Z', title: 'Push day A' })],
		NOW,
	);
	assert.equal(h.sessions[0].title, 'Push day A');
});
