import { test } from 'node:test';
import assert from 'node:assert/strict';
import { entryKey, standingFor, type StandingEntry } from './leaderboard_standing';

const u = (id: string, value: number): StandingEntry => ({
	user_id: id,
	team_club_id: null,
	value,
});
const team = (id: string | null, value: number): StandingEntry => ({
	user_id: null,
	team_club_id: id,
	value,
});

test('entryKey prefers the runner, falls back to the team, else null', () => {
	assert.equal(entryKey(u('runner', 1)), 'runner');
	assert.equal(entryKey(team('club', 1)), 'club');
	assert.equal(entryKey(team(null, 1)), null);
});

test('a viewer who is not on the board has no standing', () => {
	assert.equal(standingFor([u('a', 10), u('b', 5)], 'c'), null);
});

test('an empty board has no standing', () => {
	assert.equal(standingFor([], 'a'), null);
});

test('an unidentifiable viewer has no standing', () => {
	assert.equal(standingFor([u('a', 10)], null), null);
	assert.equal(standingFor([u('a', 10)], ''), null);
});

test('a non-finite own value claims nothing rather than a rank', () => {
	assert.equal(standingFor([u('a', Number.NaN), u('b', 5)], 'a'), null);
});

test('a lone entrant leads with nobody either side', () => {
	const s = standingFor([u('a', 10)], 'a');
	assert.ok(s);
	assert.equal(s.rank, 1);
	assert.equal(s.total, 1);
	assert.equal(s.tiedWith, 0);
	assert.equal(s.chasing, null);
	assert.equal(s.chasedBy, null);
});

test('the leader is chased but chases nobody', () => {
	const s = standingFor([u('a', 30), u('b', 20), u('c', 10)], 'a');
	assert.ok(s);
	assert.equal(s.rank, 1);
	assert.equal(s.total, 3);
	assert.equal(s.chasing, null);
	assert.equal(s.chasedBy?.entry.user_id, 'b');
	assert.equal(s.chasedBy?.delta, 10);
});

test('the last entrant chases but is chased by nobody', () => {
	const s = standingFor([u('a', 30), u('b', 20), u('c', 10)], 'c');
	assert.ok(s);
	assert.equal(s.rank, 3);
	assert.equal(s.chasing?.entry.user_id, 'b');
	assert.equal(s.chasing?.delta, 10);
	assert.equal(s.chasedBy, null);
});

test('a mid-board entrant reports both neighbours, nearest first', () => {
	const s = standingFor([u('a', 100), u('b', 60), u('c', 50), u('d', 20)], 'c');
	assert.ok(s);
	assert.equal(s.rank, 3);
	assert.equal(s.chasing?.entry.user_id, 'b');
	assert.equal(s.chasing?.delta, 10);
	assert.equal(s.chasedBy?.entry.user_id, 'd');
	assert.equal(s.chasedBy?.delta, 30);
});

test('rank is competition rank — a tie shares it and pushes the next entrant down', () => {
	const s = standingFor([u('a', 50), u('b', 50), u('c', 10)], 'b');
	assert.ok(s);
	assert.equal(s.rank, 1);
	assert.equal(s.tiedWith, 1);
	const behind = standingFor([u('a', 50), u('b', 50), u('c', 10)], 'c');
	assert.equal(behind?.rank, 3);
});

test('a tied entrant is neither chased nor chasing — the neighbours skip past them', () => {
	const rows = [u('a', 80), u('b', 50), u('c', 50), u('d', 20)];
	const s = standingFor(rows, 'b');
	assert.ok(s);
	assert.equal(s.tiedWith, 1);
	assert.equal(s.chasing?.entry.user_id, 'a');
	assert.equal(s.chasedBy?.entry.user_id, 'd');
});

test('neighbours tie-break on key ascending, mirroring the SQL board order', () => {
	const rows = [u('zeta', 90), u('alpha', 90), u('me', 50), u('yankee', 20), u('bravo', 20)];
	const s = standingFor(rows, 'me');
	assert.ok(s);
	assert.equal(s.chasing?.entry.user_id, 'alpha');
	assert.equal(s.chasedBy?.entry.user_id, 'bravo');
});

test('a keyless row sorts last inside its tie group, never first', () => {
	const rows = [team(null, 90), team('club-z', 90), team('club-me', 50)];
	const s = standingFor(rows, 'club-me');
	assert.ok(s);
	assert.equal(s.chasing?.entry.team_club_id, 'club-z');
});

test('a team board keys on the club', () => {
	const s = standingFor([team('c1', 400), team('c2', 300), team(null, 100)], 'c2');
	assert.ok(s);
	assert.equal(s.rank, 2);
	assert.equal(s.chasing?.entry.team_club_id, 'c1');
	assert.equal(s.chasing?.delta, 100);
	assert.equal(s.chasedBy?.entry.team_club_id, null);
	assert.equal(s.chasedBy?.delta, 200);
});

test('a non-finite rival is counted on the board but lands in neither neighbour slot', () => {
	const s = standingFor([u('a', Number.NaN), u('b', 30), u('me', 20)], 'me');
	assert.ok(s);
	assert.equal(s.total, 3);
	assert.equal(s.rank, 2);
	assert.equal(s.chasing?.entry.user_id, 'b');
	assert.equal(s.chasedBy, null);
});

test('a zero-valued board is all ties, not a ranking', () => {
	const rows = [u('a', 0), u('b', 0), u('c', 0)];
	const s = standingFor(rows, 'a');
	assert.ok(s);
	assert.equal(s.rank, 1);
	assert.equal(s.tiedWith, 2);
	assert.equal(s.chasing, null);
	assert.equal(s.chasedBy, null);
});
