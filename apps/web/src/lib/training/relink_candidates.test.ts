import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	filterRelinkCandidates,
	DEFAULT_RELINK_WINDOW_DAYS,
	type RelinkCandidateRun,
} from './relink_candidates.js';

function run(
	id: string,
	startedAt: string,
	distance_m = 5000,
	duration_s = 1800
): RelinkCandidateRun {
	return { id, started_at: startedAt, distance_m, duration_s };
}

test('returns in-window runs newest-first', () => {
	const out = filterRelinkCandidates({
		runs: [
			run('a', '2026-04-05T07:00:00Z'),
			run('b', '2026-04-07T07:00:00Z'),
			run('c', '2026-04-03T07:00:00Z'),
		],
		linkedRunIds: [],
		currentRunId: null,
		scheduledDate: '2026-04-05',
	});
	assert.deepEqual(out.map((r) => r.id), ['b', 'a', 'c']);
});

test('excludes runs outside the ±window', () => {
	const out = filterRelinkCandidates({
		runs: [
			run('near', '2026-04-06T07:00:00Z'),
			run('far', '2026-04-20T07:00:00Z'),
		],
		linkedRunIds: [],
		currentRunId: null,
		scheduledDate: '2026-04-05',
		windowDays: 7,
	});
	assert.deepEqual(out.map((r) => r.id), ['near']);
});

test('boundary day is in-window (inclusive)', () => {
	const out = filterRelinkCandidates({
		runs: [run('edge', '2026-04-12T07:00:00Z')],
		linkedRunIds: [],
		currentRunId: null,
		scheduledDate: '2026-04-05',
		windowDays: 7,
	});
	assert.deepEqual(out.map((r) => r.id), ['edge']);
});

test('one day past the boundary is excluded', () => {
	const out = filterRelinkCandidates({
		runs: [run('past', '2026-04-13T07:00:00Z')],
		linkedRunIds: [],
		currentRunId: null,
		scheduledDate: '2026-04-05',
		windowDays: 7,
	});
	assert.deepEqual(out, []);
});

test('excludes a run already linked to another workout (double-count guard)', () => {
	const out = filterRelinkCandidates({
		runs: [run('linked-elsewhere', '2026-04-05T07:00:00Z'), run('free', '2026-04-05T08:00:00Z')],
		linkedRunIds: ['linked-elsewhere'],
		currentRunId: null,
		scheduledDate: '2026-04-05',
	});
	assert.deepEqual(out.map((r) => r.id), ['free']);
});

test('keeps the workout\'s OWN current run selectable even though it is linked', () => {
	const out = filterRelinkCandidates({
		runs: [run('current', '2026-04-05T07:00:00Z'), run('other-linked', '2026-04-05T08:00:00Z')],
		linkedRunIds: ['current', 'other-linked'],
		currentRunId: 'current',
		scheduledDate: '2026-04-05',
	});
	assert.deepEqual(out.map((r) => r.id), ['current']);
});

test('the current run stays visible even when out of window', () => {
	const out = filterRelinkCandidates({
		runs: [run('current-far', '2026-05-01T07:00:00Z')],
		linkedRunIds: ['current-far'],
		currentRunId: 'current-far',
		scheduledDate: '2026-04-05',
		windowDays: 7,
	});
	assert.deepEqual(out.map((r) => r.id), ['current-far']);
});

test('empty runs yields empty', () => {
	const out = filterRelinkCandidates({
		runs: [],
		linkedRunIds: ['x'],
		currentRunId: 'x',
		scheduledDate: '2026-04-05',
	});
	assert.deepEqual(out, []);
});

test('default window is 7 days', () => {
	assert.equal(DEFAULT_RELINK_WINDOW_DAYS, 7);
	const out = filterRelinkCandidates({
		runs: [run('d8', '2026-04-13T07:00:00Z'), run('d7', '2026-04-12T07:00:00Z')],
		linkedRunIds: [],
		currentRunId: null,
		scheduledDate: '2026-04-05',
	});
	assert.deepEqual(out.map((r) => r.id), ['d7']);
});

// A window that straddles a DST transition (spring-forward 2024-03-10): the
// run on 03-04 is exactly 8 calendar days before a workout scheduled 03-12, so
// it is OUT of a ±7-day window. UTC-anchoring the day gap keeps this exact on
// both platforms; the previous local-midnight span drifted to 7 d 23 h, which
// the Dart twin's Duration.inDays truncated to 7 (wrongly INCLUDING it).
test('DST-straddling window counts exact calendar days (8 d → excluded at 7)', () => {
	const out = filterRelinkCandidates({
		runs: [
			run('dst-edge', '2024-03-04T12:00:00Z'),
			run('inside', '2024-03-06T12:00:00Z'),
		],
		linkedRunIds: [],
		currentRunId: null,
		scheduledDate: '2024-03-12',
	});
	assert.deepEqual(out.map((r) => r.id), ['inside']);
});

// decisions § 1241: the tie is broken on `id`, not left to whatever the fetch
// returned. Both tests below are the same case at the two sizes that matter —
// the second is past Dart's 33-element insertion-sort threshold, where its
// `List.sort` reorders equal elements on every run.
test('two runs at the identical instant order by id, not by fetch order', () => {
	const forward = filterRelinkCandidates({
		runs: [run('b', '2026-04-05T07:00:00Z'), run('a', '2026-04-05T07:00:00Z')],
		linkedRunIds: [],
		currentRunId: null,
		scheduledDate: '2026-04-05',
	});
	const reversed = filterRelinkCandidates({
		runs: [run('a', '2026-04-05T07:00:00Z'), run('b', '2026-04-05T07:00:00Z')],
		linkedRunIds: [],
		currentRunId: null,
		scheduledDate: '2026-04-05',
	});
	assert.deepEqual(
		forward.map((r) => r.id),
		['a', 'b']
	);
	assert.deepEqual(
		reversed.map((r) => r.id),
		['a', 'b']
	);
});

test('a 40-run all-tied list is ordered by id regardless of fetch order', () => {
	const ids = Array.from({ length: 40 }, (_, i) => `run-${String(i).padStart(2, '0')}`);
	const runs = ids.map((id) => run(id, '2026-04-05T07:00:00Z'));
	const shuffled = [...runs].reverse();
	const input = { linkedRunIds: [], currentRunId: null, scheduledDate: '2026-04-05' };
	assert.deepEqual(
		filterRelinkCandidates({ runs, ...input }).map((r) => r.id),
		ids
	);
	assert.deepEqual(
		filterRelinkCandidates({ runs: shuffled, ...input }).map((r) => r.id),
		ids
	);
});
