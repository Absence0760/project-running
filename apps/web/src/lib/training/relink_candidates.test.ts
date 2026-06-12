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
