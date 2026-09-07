import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { sortRoster, type RosterSortKey } from './roster_sort';
import type { CoachRosterRow } from '$lib/core/data';

function row(over: Partial<CoachRosterRow> & { athlete_id: string }): CoachRosterRow {
	return {
		display_name: null,
		avatar_url: null,
		last_run_at: null,
		runs_7d: 0,
		distance_7d_m: 0,
		load_acute: 0,
		load_chronic: 0,
		active_plan_id: null,
		plan_completion_pct: 0,
		...over,
	};
}

const KEYS: RosterSortKey[] = ['risk', 'lastRun', 'load', 'plan', 'name'];

test('every column is a total order, so the roster does not reshuffle between renders', () => {
	// Reason: `coach_roster_summary` carries no unique `ORDER BY`, and each key
	// below ties readily — two athletes with no runs logged, both on 0 acute
	// load, both on 0% plan completion, both nameless. `Array.prototype.sort`
	// is stable, so the order then fell through to whatever the RPC happened to
	// return and a coach watching the roster saw it rearrange itself.
	const tied = [row({ athlete_id: 'c' }), row({ athlete_id: 'a' }), row({ athlete_id: 'b' })];
	for (const key of KEYS) {
		for (const dir of ['asc', 'desc'] as const) {
			assert.deepEqual(
				sortRoster(tied, key, dir).map((r) => r.athlete_id),
				['a', 'b', 'c'],
				`${key}/${dir} left a tie group in input order`,
			);
		}
	}
});

test('two athletes under one display name still order totally', () => {
	// Reason: the collation answers 0 for two DIFFERENT strings — two people
	// genuinely called `John Smith`, or one name precomposed against the other
	// decomposed — so the name column needs the id as much as the numeric ones.
	const rows = [
		row({ athlete_id: 'z', display_name: 'John Smith' }),
		row({ athlete_id: 'a', display_name: 'John Smith' }),
	];
	assert.deepEqual(
		sortRoster(rows, 'name', 'asc').map((r) => r.athlete_id),
		['a', 'z'],
	);
});

test('the id tiebreak does not reverse with the direction', () => {
	// Reason: it sits outside `* dir` on purpose. Flipping the column must
	// reverse the ranked groups, not scramble the members of a tie.
	const rows = [
		row({ athlete_id: 'b', load_acute: 10 }),
		row({ athlete_id: 'a', load_acute: 10 }),
		row({ athlete_id: 'c', load_acute: 99 }),
	];
	assert.deepEqual(
		sortRoster(rows, 'load', 'asc').map((r) => r.athlete_id),
		['a', 'b', 'c'],
	);
	assert.deepEqual(
		sortRoster(rows, 'load', 'desc').map((r) => r.athlete_id),
		['c', 'a', 'b'],
	);
});

test('the ranked term still wins over the id', () => {
	// Reason: the tiebreak must not become the primary term — a coach reads the
	// roster by risk, never by uuid.
	const rows = [
		row({ athlete_id: 'a', load_acute: 1, load_chronic: 100 }),
		row({ athlete_id: 'z', load_acute: 200, load_chronic: 100 }),
	];
	assert.deepEqual(
		sortRoster(rows, 'risk', 'desc').map((r) => r.athlete_id),
		['z', 'a'],
	);
});

test('sortRoster does not mutate the roster it was handed', () => {
	// Reason: it reads a `$state` array straight out of the page. An in-place
	// sort would write to reactive state from inside a `$derived`.
	const rows = [row({ athlete_id: 'c' }), row({ athlete_id: 'a' })];
	sortRoster(rows, 'name', 'asc');
	assert.deepEqual(
		rows.map((r) => r.athlete_id),
		['c', 'a'],
	);
});
