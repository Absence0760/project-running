import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	mergeMyProgress,
	myProgressView,
	teamLabel,
	type MyProgressRow,
} from './challenge_list';

const row = (over: Partial<MyProgressRow> & { id: string }): MyProgressRow => ({
	my_value: null,
	my_rank: null,
	completed_at: null,
	...over,
});

test('mergeMyProgress folds the aggregate onto matching ids', () => {
	const out = mergeMyProgress(
		[row({ id: 'a' }), row({ id: 'b' })],
		[{ id: 'b', my_value: 42, my_rank: 3, completed_at: '2026-01-02T00:00:00Z' }],
	);
	assert.deepEqual(out[0], row({ id: 'a' }));
	assert.equal(out[1].my_value, 42);
	assert.equal(out[1].my_rank, 3);
	assert.equal(out[1].completed_at, '2026-01-02T00:00:00Z');
});

test('mergeMyProgress leaves uncovered rows null rather than zeroing them', () => {
	const out = mergeMyProgress([row({ id: 'old' })], []);
	assert.equal(out[0].my_value, null);
	assert.equal(out[0].my_rank, null);
});

test('mergeMyProgress preserves input order', () => {
	const out = mergeMyProgress(
		[row({ id: 'c' }), row({ id: 'a' }), row({ id: 'b' })],
		[
			{ id: 'a', my_value: 1, my_rank: 1, completed_at: null },
			{ id: 'b', my_value: 2, my_rank: 2, completed_at: null },
		],
	);
	assert.deepEqual(
		out.map((r) => r.id),
		['c', 'a', 'b'],
	);
});

test('mergeMyProgress keeps a zero value from the aggregate', () => {
	const out = mergeMyProgress([row({ id: 'a' })], [{ id: 'a', my_value: 0, my_rank: 5, completed_at: null }]);
	assert.equal(out[0].my_value, 0);
	assert.equal(out[0].my_rank, 5);
});

test('mergeMyProgress does not drop an existing value when the aggregate has none', () => {
	const out = mergeMyProgress(
		[row({ id: 'a', my_value: 7, my_rank: 2 })],
		[{ id: 'a', my_value: null, my_rank: null, completed_at: null }],
	);
	assert.equal(out[0].my_value, 7);
	assert.equal(out[0].my_rank, 2);
});

test('mergeMyProgress prefers the row completed_at it already read', () => {
	const out = mergeMyProgress(
		[row({ id: 'a', completed_at: '2026-01-01T00:00:00Z' })],
		[{ id: 'a', my_value: 1, my_rank: 1, completed_at: '2026-06-06T00:00:00Z' }],
	);
	assert.equal(out[0].completed_at, '2026-01-01T00:00:00Z');
});

test('mergeMyProgress does not mutate its inputs', () => {
	const rows = [row({ id: 'a' })];
	mergeMyProgress(rows, [{ id: 'a', my_value: 9, my_rank: 1, completed_at: null }]);
	assert.equal(rows[0].my_value, null);
});

const NOW = Date.parse('2026-03-10T12:00:00Z');

test('myProgressView reports a served value as known', () => {
	assert.deepEqual(myProgressView({ my_value: 12345, starts_at: '2026-03-01T00:00:00Z' }, NOW), {
		state: 'known',
		value: 12345,
	});
});

test('myProgressView treats a served zero as known, not missing', () => {
	assert.deepEqual(myProgressView({ my_value: 0, starts_at: '2026-03-01T00:00:00Z' }, NOW), {
		state: 'known',
		value: 0,
	});
});

test('myProgressView calls an unopened window a true zero', () => {
	assert.deepEqual(myProgressView({ my_value: null, starts_at: '2026-04-01T00:00:00Z' }, NOW), {
		state: 'not_started',
		value: 0,
	});
});

test('myProgressView will not claim zero for an open window with no value', () => {
	assert.equal(
		myProgressView({ my_value: null, starts_at: '2026-01-01T00:00:00Z' }, NOW).state,
		'unknown',
	);
});

test('myProgressView treats the exact start instant as started', () => {
	assert.equal(myProgressView({ my_value: null, starts_at: '2026-03-10T12:00:00Z' }, NOW).state, 'unknown');
});

test('a served value outranks a client clock that thinks the window is shut', () => {
	// Client clock behind the server's: the aggregate only covers challenges the
	// SERVER considers started, so its value must win over the local comparison.
	assert.deepEqual(myProgressView({ my_value: 500, starts_at: '2026-04-01T00:00:00Z' }, NOW), {
		state: 'known',
		value: 500,
	});
});

test('myProgressView fails closed on a non-finite value', () => {
	assert.equal(myProgressView({ my_value: Number.NaN, starts_at: '2026-01-01T00:00:00Z' }, NOW).state, 'unknown');
	assert.equal(
		myProgressView({ my_value: Number.POSITIVE_INFINITY, starts_at: '2026-01-01T00:00:00Z' }, NOW).state,
		'unknown',
	);
});

test('myProgressView fails closed on an unparseable start', () => {
	assert.equal(myProgressView({ my_value: null, starts_at: 'not a date' }, NOW).state, 'unknown');
});

const CLUB = '2c1cf5b0-0000-4000-8000-000000000001';

test('teamLabel resolves a readable club to its name', () => {
	assert.deepEqual(teamLabel(CLUB, { [CLUB]: 'Trail Pack' }), { kind: 'named', name: 'Trail Pack' });
});

test('teamLabel never renders the raw club id for an unreadable club', () => {
	assert.deepEqual(teamLabel(CLUB, {}), { kind: 'unresolved' });
	assert.deepEqual(teamLabel(CLUB, { [CLUB]: '   ' }), { kind: 'unresolved' });
	assert.deepEqual(teamLabel(CLUB, { other: 'Trail Pack' }), { kind: 'unresolved' });
});

test('teamLabel reports the unaffiliated bucket separately from an unreadable club', () => {
	assert.deepEqual(teamLabel(null, { [CLUB]: 'Trail Pack' }), { kind: 'no_club' });
	assert.deepEqual(teamLabel(undefined, {}), { kind: 'no_club' });
	assert.deepEqual(teamLabel('', {}), { kind: 'no_club' });
});
