// Unit tests for the week-over-week / month-over-month trend deltas. Run with:
//   npx tsx --test src/lib/training/trend_deltas.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { computeTrendDeltas } from './trend_deltas';

// A Wednesday at midday — mid-week and mid-month, so both current windows are
// partial and the "same slice of the prior period" comparison is exercised.
const NOW = new Date(2026, 5, 17, 12, 0, 0); // 2026-06-17 (Wed), local time.

function run(date: Date, distance_m: number, duration_s: number) {
	return { started_at: date.toISOString(), distance_m, duration_s };
}

function daysBefore(n: number, hour = 9): Date {
	const d = new Date(NOW);
	d.setDate(NOW.getDate() - n);
	d.setHours(hour, 0, 0, 0);
	return d;
}

test('empty history yields all-zero flat deltas', () => {
	const t = computeTrendDeltas([], 'monday', NOW);
	for (const period of [t.week, t.month]) {
		for (const m of [period.distanceM, period.durationS, period.runs]) {
			assert.equal(m.current, 0);
			assert.equal(m.prior, 0);
			assert.equal(m.delta, 0);
			assert.equal(m.direction, 'flat');
			assert.equal(m.pct, null);
		}
	}
});

test('week delta counts this-week runs as current', () => {
	// Monday-start week containing Wed 2026-06-17 begins Mon 2026-06-15.
	const runs = [
		run(daysBefore(0), 5000, 1500), // today (Wed)
		run(daysBefore(2), 3000, 900), // Mon, in this week
	];
	const t = computeTrendDeltas(runs, 'monday', NOW);
	assert.equal(t.week.runs.current, 2);
	assert.equal(t.week.distanceM.current, 8000);
	assert.equal(t.week.durationS.current, 2400);
	assert.equal(t.week.runs.prior, 0);
	assert.equal(t.week.runs.direction, 'up');
});

test('prior week only counts the same to-date slice, not the whole week', () => {
	// This week: one run today. Last week: a run 7 days ago (same weekday/time,
	// so inside the to-date slice) AND a run 4 days ago (Sat last week — AFTER
	// the Wed-midday cutoff, so OUTSIDE the prior slice).
	const runs = [
		run(daysBefore(0), 5000, 1500), // this Wed
		run(daysBefore(7), 4000, 1200), // last Wed — inside prior slice
		run(daysBefore(4), 9000, 2700), // last Sat — after the slice, excluded
	];
	const t = computeTrendDeltas(runs, 'monday', NOW);
	assert.equal(t.week.runs.current, 1);
	assert.equal(t.week.runs.prior, 1);
	assert.equal(t.week.distanceM.current, 5000);
	assert.equal(t.week.distanceM.prior, 4000);
	assert.equal(t.week.distanceM.delta, 1000);
	assert.equal(t.week.distanceM.direction, 'up');
	assert.equal(t.week.distanceM.pct, 25);
});

test('a down week reads down with a negative pct', () => {
	const runs = [
		run(daysBefore(0), 2000, 600), // this week
		run(daysBefore(7), 8000, 2400), // same slice last week
	];
	const t = computeTrendDeltas(runs, 'monday', NOW);
	assert.equal(t.week.distanceM.delta, -6000);
	assert.equal(t.week.distanceM.direction, 'down');
	assert.equal(t.week.distanceM.pct, -75);
});

test('pct is null when the prior window is empty (no divide-by-zero)', () => {
	const runs = [run(daysBefore(0), 5000, 1500)];
	const t = computeTrendDeltas(runs, 'monday', NOW);
	assert.equal(t.week.distanceM.prior, 0);
	assert.equal(t.week.distanceM.pct, null);
	assert.equal(t.week.distanceM.direction, 'up');
});

test('equal current and prior reads flat', () => {
	const runs = [run(daysBefore(0), 5000, 1500), run(daysBefore(7), 5000, 1500)];
	const t = computeTrendDeltas(runs, 'monday', NOW);
	assert.equal(t.week.distanceM.delta, 0);
	assert.equal(t.week.distanceM.direction, 'flat');
	assert.equal(t.week.distanceM.pct, 0);
});

test('week_start_day = sunday shifts the week boundary', () => {
	// With Sunday-start, the week containing Wed 2026-06-17 begins Sun
	// 2026-06-14. A run on Sun 2026-06-14 (3 days ago) is IN this week under
	// Sunday-start but was in LAST week under Monday-start.
	const sundayRun = run(daysBefore(3), 6000, 1800); // Sun 2026-06-14
	const sun = computeTrendDeltas([sundayRun], 'sunday', NOW);
	const mon = computeTrendDeltas([sundayRun], 'monday', NOW);
	assert.equal(sun.week.runs.current, 1);
	assert.equal(mon.week.runs.current, 0);
});

test('month delta counts this-month runs and compares the prior month slice', () => {
	// June-to-date (1st–17th) vs May 1st–17th.
	const runs = [
		run(new Date(2026, 5, 3, 9), 10000, 3000), // June 3 — current
		run(new Date(2026, 5, 12, 9), 5000, 1500), // June 12 — current
		run(new Date(2026, 4, 5, 9), 8000, 2400), // May 5 — prior slice
		run(new Date(2026, 4, 25, 9), 20000, 6000), // May 25 — after the slice, excluded
	];
	const t = computeTrendDeltas(runs, 'monday', NOW);
	assert.equal(t.month.runs.current, 2);
	assert.equal(t.month.distanceM.current, 15000);
	assert.equal(t.month.runs.prior, 1);
	assert.equal(t.month.distanceM.prior, 8000);
	assert.equal(t.month.distanceM.direction, 'up');
});

test('runs outside both windows are ignored entirely', () => {
	const runs = [
		run(new Date(2026, 3, 10, 9), 42000, 12000), // April — two months back
		run(daysBefore(20), 15000, 4500), // ~late May, before the June slice
	];
	const t = computeTrendDeltas(runs, 'monday', NOW);
	assert.equal(t.week.runs.current, 0);
	assert.equal(t.month.runs.current, 0);
});

test('non-finite timestamps and metrics do not poison the totals', () => {
	const runs = [
		run(daysBefore(0), 5000, 1500),
		{ started_at: 'not-a-date', distance_m: 9999, duration_s: 9999 },
		{ started_at: daysBefore(0).toISOString(), distance_m: NaN, duration_s: NaN },
	];
	const t = computeTrendDeltas(runs, 'monday', NOW);
	// The valid run plus the NaN-metric run (both today) count; NaN metrics
	// contribute 0, the bad-date row is skipped.
	assert.equal(t.week.runs.current, 2);
	assert.equal(t.week.distanceM.current, 5000);
	assert.equal(t.week.durationS.current, 1500);
});
