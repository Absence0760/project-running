import { test } from 'node:test';
import assert from 'node:assert/strict';

import { comparePeopleRank, comparePersonName, type RankablePerson } from './search_ranking';

const mk = (
	name: string,
	runs: number,
	shared = 0,
	id = name,
): RankablePerson => ({
	id,
	display_name: name,
	public_runs_count: runs,
	shared_clubs: shared,
});

test('comparePeopleRank puts higher-run-count accounts first', () => {
	const a = mk('Alex Real', 25);
	const b = mk('Alex Bot', 0);
	const sorted = [a, b].sort(comparePeopleRank);
	assert.equal(sorted[0].display_name, 'Alex Real');
});

test('comparePeopleRank breaks ties with shared_clubs', () => {
	const a = mk('Alex Stranger', 5, 0);
	const b = mk('Alex Clubmate', 5, 3);
	const sorted = [a, b].sort(comparePeopleRank);
	assert.equal(sorted[0].display_name, 'Alex Clubmate');
});

test('comparePeopleRank falls through to display_name alphabetical', () => {
	const a = mk('Alex Bravo', 0, 0);
	const b = mk('Alex Alpha', 0, 0);
	const sorted = [a, b].sort(comparePeopleRank);
	assert.equal(sorted[0].display_name, 'Alex Alpha');
});

test('comparePeopleRank does not hide 0-runs accounts (they rank last, not absent)', () => {
	// A friend you search for by exact name may have posted no runs
	// yet. Surface them after the high-signal accounts, but surface
	// them. Regressing this to a hard filter would be a bad UX.
	const real = mk('Real Runner', 100, 0);
	const friend = mk('Quiet Friend', 0, 0);
	const sorted = [friend, real].sort(comparePeopleRank);
	assert.equal(sorted.length, 2);
	assert.equal(sorted[0].display_name, 'Real Runner');
	assert.equal(sorted[1].display_name, 'Quiet Friend');
});

test('comparePeopleRank is stable across identical signals (alphabetical falls through)', () => {
	const items = [
		mk('Charlie', 10, 1),
		mk('Bravo', 10, 1),
		mk('Alpha', 10, 1),
	];
	const sorted = [...items].sort(comparePeopleRank);
	assert.deepEqual(
		sorted.map((p) => p.display_name),
		['Alpha', 'Bravo', 'Charlie'],
	);
});

test('a swarm of 0-run bots cannot push a real account out of the top spot', () => {
	const bots = Array.from({ length: 50 }, (_, i) => mk(`Bot${i}`, 0));
	const real = mk('Zara Real', 1);
	const sorted = [...bots, real].sort(comparePeopleRank);
	assert.equal(sorted[0].display_name, 'Zara Real');
});

test('two people under one display name sort into the same order every render', () => {
	// Reason: a collation answers 0 for two DIFFERENT strings, and the sort is
	// stable, so the order then fell through to whatever the query returned —
	// and no `ORDER BY` on the search or suggested-people paths makes that
	// unique. Two accounts genuinely called `John Smith` swapped places between
	// renders of the same result set.
	const first = mk('John Smith', 0, 0, 'a1111111');
	const second = mk('John Smith', 0, 0, 'b2222222');
	assert.deepEqual(
		[second, first].sort(comparePeopleRank).map((p) => p.id),
		['a1111111', 'b2222222'],
	);
	assert.deepEqual(
		[first, second].sort(comparePeopleRank).map((p) => p.id),
		['a1111111', 'b2222222'],
	);
});

test('a precomposed and a decomposed spelling of one name still order totally', () => {
	// Reason: the other way a collation returns 0 for two distinct strings.
	// `Å` as U+00C5 and as `A` + U+030A compare equal under every locale, so
	// the id is the only term left that can separate them.
	const precomposed = mk('Åsa Berg', 3, 1, 'z-late');
	const decomposed = mk('Åsa Berg', 3, 1, 'a-early');
	assert.equal((precomposed.display_name ?? '').localeCompare(decomposed.display_name ?? ''), 0);
	assert.deepEqual(
		[precomposed, decomposed].sort(comparePeopleRank).map((p) => p.id),
		['a-early', 'z-late'],
	);
});

test('comparePersonName is the collation first and the id only as a tiebreak', () => {
	// Reason: the id must not become the primary term. A reader looking for
	// `Ana` reads a list ordered by name, not by uuid.
	const ana = mk('Ana', 0, 0, 'zzzz');
	const bo = mk('Bo', 0, 0, 'aaaa');
	assert.ok(comparePersonName(ana, bo) < 0);
	assert.equal(comparePersonName(ana, ana), 0);
});
