import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	routineHistoryFromAggregate,
	type RoutineHistoryAggregate,
	type RoutineSessionRow,
} from './routine_history';

const NOW = Date.parse('2026-08-15T12:00:00.000Z');

function row(over: Partial<RoutineSessionRow> & { id: string; started_at: string }): RoutineSessionRow {
	return { title: null, metadata: {}, ...over };
}

/// The RPC's own tallies, defaulted off the page so a case that only cares
/// about row shaping doesn't have to restate them.
function agg(
	recentRows: RoutineSessionRow[],
	over: Partial<RoutineHistoryAggregate> = {},
): RoutineHistoryAggregate {
	return {
		sessionCount: recentRows.length,
		lastPerformedAt: null,
		gradedCount: 0,
		completedCount: 0,
		recentRows,
		...over,
	};
}

test('an empty aggregate yields a history the caller can self-hide on', () => {
	const h = routineHistoryFromAggregate(agg([]), NOW);
	assert.equal(h.sessionCount, 0);
	assert.equal(h.lastPerformedAt, null);
	assert.equal(h.daysSinceLast, null);
	assert.equal(h.completedRate, null);
	assert.equal(h.gradedCount, 0);
	assert.deepEqual(h.recentSessions, []);
});

test('recent sessions are ordered newest first regardless of input order', () => {
	const h = routineHistoryFromAggregate(
		agg(
			[
				row({ id: 'a', started_at: '2026-08-01T10:00:00.000Z' }),
				row({ id: 'c', started_at: '2026-08-12T10:00:00.000Z' }),
				row({ id: 'b', started_at: '2026-08-05T10:00:00.000Z' }),
			],
			{ lastPerformedAt: '2026-08-12T10:00:00.000Z' },
		),
		NOW,
	);
	assert.deepEqual(
		h.recentSessions.map((s) => s.id),
		['c', 'b', 'a'],
	);
	assert.equal(h.lastPerformedAt, '2026-08-12T10:00:00.000Z');
});

test('an in-flight draft row is not a performed session', () => {
	const h = routineHistoryFromAggregate(
		agg(
			[
				row({ id: 'done', started_at: '2026-08-10T10:00:00.000Z', metadata: { gym_adherence: 'completed' } }),
				row({
					id: 'draft',
					started_at: '2026-08-14T10:00:00.000Z',
					metadata: { routine_id: 'r1', gym_session_draft: { saved_at: '2026-08-14T10:05:00.000Z', results: [] } },
				}),
			],
			{ sessionCount: 1, lastPerformedAt: '2026-08-10T10:00:00.000Z', gradedCount: 1, completedCount: 1 },
		),
		NOW,
	);
	assert.equal(h.recentSessions.length, 1);
	assert.equal(h.recentSessions[0].id, 'done');
	assert.equal(h.sessionCount, 1);
	assert.equal(h.lastPerformedAt, '2026-08-10T10:00:00.000Z');
});

// The exclusion is a three-rail contract: Dart asks `is Map` and the RPC asks
// `jsonb_typeof(...) = 'object'`. A marker that is not a JSON object leaves the
// row a session performed on all three, so a divergence fails here.
test('a non-object under the draft key leaves the row a session performed', () => {
	const h = routineHistoryFromAggregate(
		agg(
			[
				row({
					id: 'arr',
					started_at: '2026-08-10T10:00:00.000Z',
					metadata: { routine_id: 'r1', gym_session_draft: [] },
				}),
			],
			{ sessionCount: 1, lastPerformedAt: '2026-08-10T10:00:00.000Z' },
		),
		NOW,
	);
	assert.equal(h.recentSessions.length, 1);
	assert.equal(h.recentSessions[0].id, 'arr');
	assert.equal(h.sessionCount, 1);
});

test('a save-as-is row is ungraded, not completed', () => {
	const h = routineHistoryFromAggregate(
		agg([row({ id: 'x', started_at: '2026-08-10T10:00:00.000Z', metadata: { routine_id: 'r1' } })], {
			sessionCount: 1,
			lastPerformedAt: '2026-08-10T10:00:00.000Z',
		}),
		NOW,
	);
	assert.equal(h.sessionCount, 1);
	assert.equal(h.recentSessions[0].verdict, 'ungraded');
	assert.equal(h.gradedCount, 0);
	assert.equal(h.completedCount, 0);
	assert.equal(h.completedRate, null);
});

test('each stored verdict is carried through onto its row', () => {
	const h = routineHistoryFromAggregate(
		agg(
			[
				row({ id: 'a', started_at: '2026-08-01T10:00:00.000Z', metadata: { gym_adherence: 'completed' } }),
				row({ id: 'b', started_at: '2026-08-02T10:00:00.000Z', metadata: { gym_adherence: 'partial' } }),
				row({ id: 'c', started_at: '2026-08-03T10:00:00.000Z', metadata: { gym_adherence: 'abandoned' } }),
				row({ id: 'd', started_at: '2026-08-04T10:00:00.000Z', metadata: { gym_adherence: 'completed' } }),
			],
			{ sessionCount: 4, lastPerformedAt: '2026-08-04T10:00:00.000Z', gradedCount: 4, completedCount: 2 },
		),
		NOW,
	);
	assert.deepEqual(
		h.recentSessions.map((s) => s.verdict),
		['completed', 'abandoned', 'partial', 'completed'],
	);
	assert.equal(h.gradedCount, 4);
	assert.equal(h.completedCount, 2);
	assert.equal(h.completedRate, 0.5);
});

test('the rate is completed-of-GRADED, so an ungraded session is not a miss', () => {
	const h = routineHistoryFromAggregate(
		agg(
			[
				row({ id: 'a', started_at: '2026-08-01T10:00:00.000Z', metadata: { gym_adherence: 'completed' } }),
				row({ id: 'b', started_at: '2026-08-02T10:00:00.000Z', metadata: { routine_id: 'r1' } }),
			],
			{ sessionCount: 2, lastPerformedAt: '2026-08-02T10:00:00.000Z', gradedCount: 1, completedCount: 1 },
		),
		NOW,
	);
	assert.equal(h.sessionCount, 2);
	assert.equal(h.gradedCount, 1);
	assert.equal(h.completedRate, 1);
});

test('an unrecognised verdict string is ungraded rather than trusted', () => {
	const h = routineHistoryFromAggregate(
		agg([row({ id: 'a', started_at: '2026-08-01T10:00:00.000Z', metadata: { gym_adherence: 'crushed_it' } })], {
			sessionCount: 1,
			lastPerformedAt: '2026-08-01T10:00:00.000Z',
		}),
		NOW,
	);
	assert.equal(h.recentSessions[0].verdict, 'ungraded');
	assert.equal(h.gradedCount, 0);
});

test('a null or non-object metadata bag degrades to ungraded', () => {
	const h = routineHistoryFromAggregate(
		agg(
			[
				row({ id: 'a', started_at: '2026-08-01T10:00:00.000Z', metadata: null }),
				row({ id: 'b', started_at: '2026-08-02T10:00:00.000Z', metadata: 'nonsense' }),
				{ id: 'c', started_at: '2026-08-03T10:00:00.000Z' },
			],
			{ sessionCount: 3, lastPerformedAt: '2026-08-03T10:00:00.000Z' },
		),
		NOW,
	);
	assert.equal(h.recentSessions.length, 3);
	assert.equal(h.gradedCount, 0);
});

test('days since last is whole elapsed days, floored', () => {
	const h = routineHistoryFromAggregate(
		agg([row({ id: 'a', started_at: '2026-08-12T23:00:00.000Z' })], {
			sessionCount: 1,
			lastPerformedAt: '2026-08-12T23:00:00.000Z',
		}),
		NOW,
	);
	assert.equal(h.daysSinceLast, 2);
});

test('a session stamped ahead of the clock reads as today, never negative', () => {
	const h = routineHistoryFromAggregate(
		agg([row({ id: 'a', started_at: '2026-08-20T10:00:00.000Z' })], {
			sessionCount: 1,
			lastPerformedAt: '2026-08-20T10:00:00.000Z',
		}),
		NOW,
	);
	assert.equal(h.daysSinceLast, 0);
});

test('an unparseable start time is dropped rather than sorted as NaN', () => {
	const h = routineHistoryFromAggregate(
		agg(
			[
				row({ id: 'bad', started_at: 'not-a-date' }),
				row({ id: 'good', started_at: '2026-08-10T10:00:00.000Z' }),
			],
			{ sessionCount: 2, lastPerformedAt: '2026-08-10T10:00:00.000Z' },
		),
		NOW,
	);
	assert.equal(h.recentSessions.length, 1);
	assert.equal(h.recentSessions[0].id, 'good');
});

test('a row with no id is dropped rather than rendered as an unlinkable session', () => {
	const h = routineHistoryFromAggregate(
		agg([{ id: '', started_at: '2026-08-10T10:00:00.000Z' }], { sessionCount: 1 }),
		NOW,
	);
	assert.equal(h.recentSessions.length, 0);
});

test('the workout title rides along for the session list', () => {
	const h = routineHistoryFromAggregate(
		agg([row({ id: 'a', started_at: '2026-08-10T10:00:00.000Z', title: 'Push day A' })], { sessionCount: 1 }),
		NOW,
	);
	assert.equal(h.recentSessions[0].title, 'Push day A');
});

test('the count is the aggregate, not the page — a bounded page never caps it', () => {
	const h = routineHistoryFromAggregate(
		agg(
			[
				row({ id: 'a', started_at: '2026-08-14T10:00:00.000Z', metadata: { gym_adherence: 'completed' } }),
				row({ id: 'b', started_at: '2026-08-07T10:00:00.000Z', metadata: { gym_adherence: 'completed' } }),
			],
			{
				sessionCount: 812,
				lastPerformedAt: '2026-08-14T10:00:00.000Z',
				gradedCount: 800,
				completedCount: 600,
			},
		),
		NOW,
	);
	assert.equal(h.sessionCount, 812);
	assert.equal(h.recentSessions.length, 2);
	assert.equal(h.gradedCount, 800);
	assert.equal(h.completedRate, 0.75);
	assert.equal(h.daysSinceLast, 1);
});

test('an empty page under a real count still reports days since last', () => {
	// The date is the aggregate's, so it survives a page the caller bounded to
	// nothing — reading it off the first listed row would lose it.
	const h = routineHistoryFromAggregate(
		agg([], { sessionCount: 40, lastPerformedAt: '2026-08-05T12:00:00.000Z', gradedCount: 40, completedCount: 10 }),
		NOW,
	);
	assert.equal(h.sessionCount, 40);
	assert.deepEqual(h.recentSessions, []);
	assert.equal(h.daysSinceLast, 10);
	assert.equal(h.completedRate, 0.25);
});

test('an unparseable last-performed stamp suppresses days-since rather than reading NaN', () => {
	const h = routineHistoryFromAggregate(
		agg([], { sessionCount: 3, lastPerformedAt: 'not-a-date' }),
		NOW,
	);
	assert.equal(h.sessionCount, 3);
	assert.equal(h.daysSinceLast, null);
});
