import { test } from 'node:test';
import assert from 'node:assert/strict';

import { comparePeopleRank, type RankablePerson } from './search_ranking';

const mk = (
	name: string,
	runs: number,
	shared = 0,
): RankablePerson => ({
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
