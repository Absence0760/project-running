import assert from 'node:assert/strict';
import { test } from 'node:test';

import { compareLeaderboard, type LeaderboardSortable } from './race_leaderboard';

function sorted(rows: LeaderboardSortable[]): string[] {
	return [...rows].sort(compareLeaderboard).map((r) => r.user_id);
}

test('furthest distance ranks first', () => {
	const rows: LeaderboardSortable[] = [
		{ user_id: 'a', distance_m: 1000, elapsed_s: 300 },
		{ user_id: 'b', distance_m: 5000, elapsed_s: 300 },
		{ user_id: 'c', distance_m: 3000, elapsed_s: 300 }
	];
	assert.deepEqual(sorted(rows), ['b', 'c', 'a']);
});

test('tie on distance breaks by lower elapsed (faster runner first)', () => {
	const rows: LeaderboardSortable[] = [
		{ user_id: 'slow', distance_m: 5000, elapsed_s: 1800 },
		{ user_id: 'fast', distance_m: 5000, elapsed_s: 1200 }
	];
	assert.deepEqual(sorted(rows), ['fast', 'slow']);
});

test('tie on distance and elapsed breaks by user_id for a total, stable order', () => {
	const rows: LeaderboardSortable[] = [
		{ user_id: 'zebra', distance_m: 5000, elapsed_s: 1200 },
		{ user_id: 'alpha', distance_m: 5000, elapsed_s: 1200 }
	];
	assert.deepEqual(sorted(rows), ['alpha', 'zebra']);
	// Re-sorting the reverse input yields the identical order — no jitter.
	assert.deepEqual(sorted([...rows].reverse()), ['alpha', 'zebra']);
});

test('null distance sorts to the back (treated as 0)', () => {
	const rows: LeaderboardSortable[] = [
		{ user_id: 'nodist', distance_m: null, elapsed_s: 300 },
		{ user_id: 'has', distance_m: 100, elapsed_s: 300 }
	];
	assert.deepEqual(sorted(rows), ['has', 'nodist']);
});

test('null elapsed sorts after a present elapsed at the same distance', () => {
	const rows: LeaderboardSortable[] = [
		{ user_id: 'noelapsed', distance_m: 5000, elapsed_s: null },
		{ user_id: 'timed', distance_m: 5000, elapsed_s: 1200 }
	];
	assert.deepEqual(sorted(rows), ['timed', 'noelapsed']);
});

test('comparator is deterministic regardless of input order', () => {
	const rows: LeaderboardSortable[] = [
		{ user_id: 'a', distance_m: 3000, elapsed_s: 900 },
		{ user_id: 'b', distance_m: 3000, elapsed_s: 900 },
		{ user_id: 'c', distance_m: 4000, elapsed_s: 900 }
	];
	const first = sorted(rows);
	const second = sorted([rows[2], rows[0], rows[1]]);
	assert.deepEqual(first, second);
	assert.deepEqual(first, ['c', 'a', 'b']);
});
