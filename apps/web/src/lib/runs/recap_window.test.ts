import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { buildYearInRunningRecap, buildMonthInRunningRecap } from './recap';
import { recapYearWindow, isInRecapWindow, mergeRecapRuns } from './recap_window';
import type { Run } from '../types';

function mkRun(startedAt: string, distance_m = 5000, duration_s = 1500): Run {
	return {
		id: `run-${startedAt}`,
		user_id: 'u',
		started_at: new Date(startedAt).toISOString(),
		distance_m,
		duration_s,
		elevation_gain_m: 40,
		track_url: null,
		route_id: 'route-1',
		source: 'app',
		activity_type: 'run',
		metadata: {},
	} as unknown as Run;
}

/**
 * The same 28 Dec 2025 → 3 Jan 2026 streak `recap.test.ts` pins on the engine,
 * plus older history so "outside the window" is not just the neighbouring days.
 */
function boundaryHistory(): Run[] {
	return [
		mkRun('2023-06-01T10:00:00'),
		mkRun('2024-11-11T10:00:00'),
		mkRun('2025-12-28T10:00:00'),
		mkRun('2025-12-29T10:00:00'),
		mkRun('2025-12-30T10:00:00'),
		mkRun('2025-12-31T10:00:00'),
		mkRun('2026-01-01T10:00:00', 12000, 3600),
		mkRun('2026-01-02T10:00:00'),
		mkRun('2026-01-03T10:00:00'),
		mkRun('2026-07-04T10:00:00', 21100, 6000),
		mkRun('2027-02-02T10:00:00'),
	];
}

/** What `fetchRunsForRecap` does on the wire, reproduced without Supabase. */
function splitAndMerge(all: Run[], year: number): Run[] {
	const win = recapYearWindow(year);
	const windowed = all.filter((r) => isInRecapWindow(r.started_at, win));
	return mergeRecapRuns(
		windowed,
		all.map((r) => r.started_at),
		win,
	);
}

test('recapYearWindow: spans the runner local year, not the UTC one', () => {
	const win = recapYearWindow(2026);
	assert.equal(Date.parse(win.fromIso), new Date(2026, 0, 1).getTime());
	assert.equal(Date.parse(win.beforeIso), new Date(2027, 0, 1).getTime());
	assert.equal(isInRecapWindow(new Date(2026, 0, 1).toISOString(), win), true);
	assert.equal(isInRecapWindow(new Date(2026, 11, 31, 23, 59).toISOString(), win), true);
	assert.equal(isInRecapWindow(new Date(2025, 11, 31, 23, 59).toISOString(), win), false);
	assert.equal(isInRecapWindow(new Date(2027, 0, 1).toISOString(), win), false);
});

test('isInRecapWindow: an unparseable timestamp is out, never in', () => {
	assert.equal(isInRecapWindow('not a date', recapYearWindow(2026)), false);
});

test('mergeRecapRuns: keeps the window verbatim and stubs only what is outside', () => {
	const all = boundaryHistory();
	const win = recapYearWindow(2026);
	const windowed = all.filter((r) => isInRecapWindow(r.started_at, win));
	const merged = mergeRecapRuns(
		windowed,
		all.map((r) => r.started_at),
		win,
	);
	assert.equal(windowed.length, 4);
	assert.equal(merged.length, all.length);
	// The window's own rows are not duplicated by the unfiltered timestamp read.
	assert.equal(merged.filter((r) => isInRecapWindow(r.started_at, win)).length, 4);
	for (const r of merged) {
		if (isInRecapWindow(r.started_at, win)) continue;
		assert.equal(r.distance_m, 0);
		assert.equal(r.duration_s, 0);
	}
});

test('mergeRecapRuns: the windowed read reproduces the annual recap exactly', () => {
	const all = boundaryHistory();
	for (const year of [2025, 2026, 2027]) {
		assert.deepEqual(
			buildYearInRunningRecap(splitAndMerge(all, year), year, {
				photoCount: 3,
				personalRecordCount: 2,
			}),
			buildYearInRunningRecap(all, year, { photoCount: 3, personalRecordCount: 2 }),
			`annual recap for ${year} must not change`,
		);
	}
});

test('mergeRecapRuns: the windowed read reproduces the monthly recap exactly', () => {
	const all = boundaryHistory();
	for (const month of [1, 7, 12]) {
		assert.deepEqual(
			buildMonthInRunningRecap(splitAndMerge(all, 2026), 2026, month),
			buildMonthInRunningRecap(all, 2026, month),
			`monthly recap for 2026-${month} must not change`,
		);
	}
});

test('mergeRecapRuns: the cross-boundary best streak survives the window', () => {
	const all = boundaryHistory();
	// The claim recap.test.ts pins on the engine, now through the split read:
	// four of the seven streak days are 2025 rows the window excludes.
	assert.equal(buildYearInRunningRecap(splitAndMerge(all, 2026), 2026).bestStreakDays, 7);
	assert.equal(buildMonthInRunningRecap(splitAndMerge(all, 2026), 2026, 1).bestStreakDays, 7);
});

test('mergeRecapRuns: an empty history is an empty recap', () => {
	const merged = mergeRecapRuns([], [], recapYearWindow(2026));
	assert.equal(merged.length, 0);
	assert.equal(buildYearInRunningRecap(merged, 2026).runCount, 0);
});
