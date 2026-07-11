import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	computeConsistency,
	kSteadyCovThreshold,
	type ConsistencyActivity,
} from './consistency';

// A fixed Wednesday so the current week is unambiguous under both week starts.
const NOW = new Date('2026-06-17T10:00:00'); // Wed 2026-06-17, local time

/// One activity `weeksAgo` whole weeks before NOW (same weekday), with the
/// given distance. Keeps each planted run comfortably inside its target week.
function weeksAgo(n: number, distanceM = 8_000): ConsistencyActivity {
	const d = new Date(NOW);
	d.setDate(d.getDate() - n * 7);
	return { started_at: d.toISOString(), distance_m: distanceM };
}

test('null when there is no history at all', () => {
	assert.equal(computeConsistency([], 'monday', 12, NOW), null);
});

test('null with only a single active week (cannot call one week consistent)', () => {
	const acts = [weeksAgo(0), weeksAgo(0, 5_000)]; // two runs, same current week
	assert.equal(computeConsistency(acts, 'monday', 12, NOW), null);
});

test('counts distinct active weeks across the window', () => {
	const acts = [weeksAgo(0), weeksAgo(2), weeksAgo(4)];
	const s = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(s);
	assert.equal(s.windowWeeks, 12);
	assert.equal(s.weeksActive, 3);
	assert.equal(s.activePct, 25); // 3 / 12
});

test('two runs in the same week count that week once', () => {
	const same = new Date(NOW);
	same.setDate(same.getDate() - 1); // still the current week (Tue)
	const acts = [
		weeksAgo(0),
		{ started_at: same.toISOString(), distance_m: 6_000 },
		weeksAgo(3),
	];
	const s = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(s);
	assert.equal(s.weeksActive, 2); // current week + the week 3 back
});

test('perfect consistency: every week active reads 100%', () => {
	const acts = Array.from({ length: 12 }, (_, i) => weeksAgo(i));
	const s = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(s);
	assert.equal(s.weeksActive, 12);
	assert.equal(s.activePct, 100);
	assert.equal(s.currentStreak, 12);
	assert.equal(s.longestStreak, 12);
});

test('current streak counts trailing active weeks', () => {
	// active weeks: 0,1,2 (trailing) then a gap at 3, then 5.
	const acts = [weeksAgo(0), weeksAgo(1), weeksAgo(2), weeksAgo(5)];
	const s = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(s);
	assert.equal(s.currentStreak, 3);
	assert.equal(s.longestStreak, 3);
});

test('an empty in-progress current week does not break the streak (grace)', () => {
	// No run this week (0); active weeks 1,2,3 back.
	const acts = [weeksAgo(1), weeksAgo(2), weeksAgo(3)];
	const s = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(s);
	// Grace skips the empty current week, so the streak is the 3 prior weeks.
	assert.equal(s.currentStreak, 3);
});

test('the streak still breaks at a genuine gap, not just the current week', () => {
	// Active this week + last week, gap two weeks back, then more.
	const acts = [weeksAgo(0), weeksAgo(1), weeksAgo(3), weeksAgo(4)];
	const s = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(s);
	assert.equal(s.currentStreak, 2); // stops at the week-2 gap
	assert.equal(s.longestStreak, 2); // both runs of 2
});

test('longestStreak finds the best run anywhere, not just the trailing one', () => {
	// current week active (streak 1), gap, then weeks 3,4,5,6 back all active.
	const acts = [weeksAgo(0), weeksAgo(3), weeksAgo(4), weeksAgo(5), weeksAgo(6)];
	const s = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(s);
	assert.equal(s.currentStreak, 1);
	assert.equal(s.longestStreak, 4);
});

test('weeklyDistanceM is oldest→newest, length windowWeeks, last is current', () => {
	const acts = [weeksAgo(0, 10_000), weeksAgo(11, 4_000)];
	const s = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(s);
	assert.equal(s.weeklyDistanceM.length, 12);
	assert.equal(s.weeklyDistanceM[0], 4_000); // oldest week (11 back)
	assert.equal(s.weeklyDistanceM[11], 10_000); // current week
});

test('steady volume: near-equal weekly volume reads steady with a low CoV', () => {
	const acts = [weeksAgo(0, 40_000), weeksAgo(1, 42_000), weeksAgo(2, 38_000)];
	const s = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(s);
	assert.equal(s.steadiness, 'steady');
	assert.ok(s.volumeCov != null && s.volumeCov <= kSteadyCovThreshold);
});

test('variable volume: a sawtooth of weekly volume reads variable', () => {
	const acts = [weeksAgo(0, 10_000), weeksAgo(1, 70_000), weeksAgo(2, 5_000), weeksAgo(3, 60_000)];
	const s = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(s);
	assert.equal(s.steadiness, 'variable');
	assert.ok(s.volumeCov != null && s.volumeCov > kSteadyCovThreshold);
});

test('non-positive / NaN distances and out-of-window runs are ignored', () => {
	const stale = new Date(NOW);
	stale.setDate(stale.getDate() - 40 * 7); // way before the 12-week window
	const acts: ConsistencyActivity[] = [
		weeksAgo(0),
		weeksAgo(2),
		{ started_at: NOW.toISOString(), distance_m: 0 }, // zero distance
		{ started_at: NOW.toISOString(), distance_m: Number.NaN }, // NaN distance
		{ started_at: 'not-a-date', distance_m: 5_000 }, // bad timestamp
		{ started_at: stale.toISOString(), distance_m: 9_000 }, // out of window
	];
	const s = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(s);
	assert.equal(s.weeksActive, 2); // only the two valid in-window weeks
});

test('honours a Sunday week start', () => {
	// NOW is a Wednesday. A run "last Sunday" (3 days back) is the SAME
	// calendar week under a Sunday start, but the PREVIOUS week under Monday.
	const lastSunday = new Date(NOW);
	lastSunday.setDate(lastSunday.getDate() - 3); // Sun 2026-06-14
	const acts = [weeksAgo(0), { started_at: lastSunday.toISOString(), distance_m: 6_000 }, weeksAgo(4)];
	const sun = computeConsistency(acts, 'sunday', 12, NOW);
	const mon = computeConsistency(acts, 'monday', 12, NOW);
	assert.ok(sun && mon);
	// Sunday start merges NOW + lastSunday into one week → 2 active weeks.
	assert.equal(sun.weeksActive, 2);
	// Monday start splits them → 3 active weeks.
	assert.equal(mon.weeksActive, 3);
});

test('a shorter window scopes the count', () => {
	const acts = [weeksAgo(0), weeksAgo(1), weeksAgo(6)];
	const s = computeConsistency(acts, 'monday', 4, NOW);
	assert.ok(s);
	assert.equal(s.windowWeeks, 4);
	assert.equal(s.weeksActive, 2); // week 6 back falls outside the 4-week window
});

test('a non-positive window is rejected', () => {
	assert.equal(computeConsistency([weeksAgo(0), weeksAgo(1)], 'monday', 0, NOW), null);
});
