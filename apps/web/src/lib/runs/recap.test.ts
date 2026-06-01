import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { buildYearInRunningRecap, recapHeadline } from './recap';
import type { Run } from '../types';

function mkRun(opts: {
	id?: string;
	startedAt: string;
	distance_m: number;
	duration_s: number;
	elevation_m?: number;
	route_id?: string | null;
	activity?: string;
}): Run {
	return {
		id: opts.id ?? `run-${opts.startedAt}`,
		user_id: 'u',
		started_at: opts.startedAt,
		distance_m: opts.distance_m,
		duration_s: opts.duration_s,
		elevation_m: opts.elevation_m ?? 0,
		track_url: null,
		title: null,
		notes: null,
		route_id: opts.route_id ?? null,
		source: 'app',
		metadata: opts.activity ? { activity_type: opts.activity } : {},
	} as unknown as Run;
}

test('buildYearInRunningRecap: empty input → zeros', () => {
	const r = buildYearInRunningRecap([], 2026);
	assert.equal(r.year, 2026);
	assert.equal(r.runCount, 0);
	assert.equal(r.totalDistanceM, 0);
	assert.equal(r.longestRunM, 0);
	assert.equal(r.fastestPaceSecPerKm, null);
	assert.equal(r.topWeek, null);
	assert.equal(r.uniqueRouteCount, 0);
	assert.equal(r.mostUsedActivity, null);
	assert.equal(r.monthly.length, 12);
	for (const m of r.monthly) assert.equal(m.runCount, 0);
});

test('buildYearInRunningRecap: filters runs by year', () => {
	const runs = [
		mkRun({ startedAt: '2025-12-31T10:00:00Z', distance_m: 5000, duration_s: 1500 }),
		mkRun({ startedAt: '2026-01-15T10:00:00Z', distance_m: 10000, duration_s: 2700 }),
		mkRun({ startedAt: '2027-01-01T10:00:00Z', distance_m: 5000, duration_s: 1500 }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.equal(r.runCount, 1);
	assert.equal(r.totalDistanceM, 10000);
});

test('buildYearInRunningRecap: monthly buckets line up with the calendar', () => {
	const runs = [
		mkRun({ startedAt: '2026-01-15T10:00:00', distance_m: 5000, duration_s: 1500 }),
		mkRun({ startedAt: '2026-01-22T10:00:00', distance_m: 5000, duration_s: 1500 }),
		mkRun({ startedAt: '2026-06-01T10:00:00', distance_m: 10000, duration_s: 2700 }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.equal(r.monthly[0].runCount, 2);
	assert.equal(r.monthly[0].distanceM, 10000);
	assert.equal(r.monthly[5].runCount, 1);
	assert.equal(r.monthly[5].distanceM, 10000);
	// Months with no runs still appear with zero count.
	assert.equal(r.monthly[3].runCount, 0);
});

test('buildYearInRunningRecap: longest run is the max', () => {
	const runs = [
		mkRun({ startedAt: '2026-02-01T10:00:00', distance_m: 5000, duration_s: 1500 }),
		mkRun({ startedAt: '2026-03-01T10:00:00', distance_m: 21097, duration_s: 7200 }),
		mkRun({ startedAt: '2026-04-01T10:00:00', distance_m: 10000, duration_s: 2700 }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.equal(r.longestRunM, 21097);
});

test('buildYearInRunningRecap: fastest pace ignores sub-500 m efforts', () => {
	const runs = [
		// Sub-500 m strolls — should not count even at "fast" pace.
		mkRun({ startedAt: '2026-01-01T10:00:00', distance_m: 200, duration_s: 60 }), // 300 s/km — would be PR
		// 10k at 4:30/km
		mkRun({ startedAt: '2026-02-01T10:00:00', distance_m: 10000, duration_s: 2700 }),
		// 5k at 4:00/km
		mkRun({ startedAt: '2026-03-01T10:00:00', distance_m: 5000, duration_s: 1200 }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	// 5k at 4:00/km = 240 s/km — the fastest qualifying.
	assert.equal(r.fastestPaceSecPerKm, 240);
});

test('buildYearInRunningRecap: top week sums all distance in a Mon-Sun window', () => {
	// Three runs in week 1 of Feb 2026 — Mon Feb 2 / Wed Feb 4 / Fri
	// Feb 6 — plus one in week 2. The top week should be Feb 2's row.
	const runs = [
		mkRun({ startedAt: '2026-02-02T10:00:00', distance_m: 5000, duration_s: 1500 }),
		mkRun({ startedAt: '2026-02-04T10:00:00', distance_m: 8000, duration_s: 2400 }),
		mkRun({ startedAt: '2026-02-06T10:00:00', distance_m: 6000, duration_s: 1800 }),
		mkRun({ startedAt: '2026-02-10T10:00:00', distance_m: 10000, duration_s: 2700 }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.notEqual(r.topWeek, null);
	assert.equal(r.topWeek!.weekStart, '2026-02-02');
	assert.equal(r.topWeek!.distanceM, 19000);
	assert.equal(r.topWeek!.runCount, 3);
});

test('buildYearInRunningRecap: uniqueRouteCount counts distinct route_ids', () => {
	const runs = [
		mkRun({ startedAt: '2026-02-01T10:00:00', distance_m: 5000, duration_s: 1500, route_id: 'r1' }),
		mkRun({ startedAt: '2026-02-02T10:00:00', distance_m: 5000, duration_s: 1500, route_id: 'r1' }),
		mkRun({ startedAt: '2026-02-03T10:00:00', distance_m: 5000, duration_s: 1500, route_id: 'r2' }),
		mkRun({ startedAt: '2026-02-04T10:00:00', distance_m: 5000, duration_s: 1500, route_id: null }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.equal(r.uniqueRouteCount, 2);
});

test('buildYearInRunningRecap: mostUsedActivity is the max-count bucket', () => {
	const runs = [
		mkRun({ startedAt: '2026-02-01T10:00:00', distance_m: 5000, duration_s: 1500, activity: 'run' }),
		mkRun({ startedAt: '2026-02-02T10:00:00', distance_m: 5000, duration_s: 1500, activity: 'run' }),
		mkRun({ startedAt: '2026-02-03T10:00:00', distance_m: 5000, duration_s: 1500, activity: 'walk' }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.equal(r.mostUsedActivity, 'run');
});

test('buildYearInRunningRecap: streaks read the full set, not just the year', () => {
	// Streak crosses Dec 28 - Jan 3. Best for year 2026 should still be 7
	// because the streak overlapped into Jan even though it started in
	// 2025.
	const runs: Run[] = [];
	for (let i = 0; i < 7; i++) {
		const d = new Date(2025, 11, 28 + i, 12, 0, 0);
		runs.push(
			mkRun({
				startedAt: d.toISOString(),
				distance_m: 5000,
				duration_s: 1500,
			}),
		);
	}
	const r = buildYearInRunningRecap(runs, 2026);
	assert.ok(r.bestStreakDays >= 3, `expected >=3 days, got ${r.bestStreakDays}`);
});

test('recapHeadline: km vs mi switches the unit string', () => {
	const recap = buildYearInRunningRecap(
		[mkRun({ startedAt: '2026-01-01T10:00:00', distance_m: 1_609_344, duration_s: 540_000 })],
		2026,
	);
	assert.equal(recapHeadline(recap, 'km'), '2026: 1609 km across 1 runs.');
	assert.equal(recapHeadline(recap, 'mi'), '2026: 1000 mi across 1 runs.');
});

test('recapHeadline: empty recap shows the "no runs" string', () => {
	const recap = buildYearInRunningRecap([], 2026);
	assert.equal(recapHeadline(recap, 'km'), 'No runs in 2026 yet.');
});

test('buildYearInRunningRecap: earliest + latest start times in HH:MM', () => {
	const runs = [
		mkRun({ startedAt: '2026-02-01T05:30:00', distance_m: 5000, duration_s: 1500 }),
		mkRun({ startedAt: '2026-02-02T12:15:00', distance_m: 5000, duration_s: 1500 }),
		mkRun({ startedAt: '2026-02-03T20:45:00', distance_m: 5000, duration_s: 1500 }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.match(r.earliestStartLocal!, /^\d{2}:\d{2}$/);
	assert.match(r.latestStartLocal!, /^\d{2}:\d{2}$/);
});

// ─────────── Round 3 edge cases ───────────

test('buildYearInRunningRecap: activity_type missing → defaults to "run"', () => {
	// Reason: metadata.activity_type is optional in the jsonb bag.
	// The helper must not crash and should count missing-activity
	// runs as "run" so the most-used-activity tally stays accurate.
	const runs = [
		mkRun({ startedAt: '2026-02-01T10:00:00', distance_m: 5000, duration_s: 1500 }), // no activity
		mkRun({ startedAt: '2026-02-02T10:00:00', distance_m: 5000, duration_s: 1500 }), // no activity
		mkRun({ startedAt: '2026-02-03T10:00:00', distance_m: 5000, duration_s: 1500, activity: 'walk' }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.equal(r.mostUsedActivity, 'run');
});

test('buildYearInRunningRecap: top-week anchor is a Monday in local time', () => {
	// Reason: ISO weeks start on Monday but JS's Date.getDay() puts
	// Sunday at 0. mondayOf() corrects via `(dow + 6) % 7`. The week-
	// of-Feb-1 (a Sunday in 2026) should bucket under the previous
	// Monday (Jan 26).
	const runs = [
		mkRun({ startedAt: '2026-02-01T10:00:00', distance_m: 5000, duration_s: 1500 }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.notEqual(r.topWeek, null);
	assert.equal(r.topWeek!.weekStart, '2026-01-26');
});

test('buildYearInRunningRecap: fastest pace is in seconds-per-km', () => {
	// 10k at 50:00 exactly = 300 s/km. Pin the unit so a refactor that
	// accidentally swapped to s/mi would be caught.
	const runs = [
		mkRun({ startedAt: '2026-02-01T10:00:00', distance_m: 10000, duration_s: 3000 }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.equal(r.fastestPaceSecPerKm, 300);
});

test('buildYearInRunningRecap: zero-duration runs do not produce Infinity pace', () => {
	// Defensive: a manual entry with duration=0 must not pollute the
	// fastest-pace field with Infinity.
	const runs = [
		mkRun({ startedAt: '2026-02-01T10:00:00', distance_m: 5000, duration_s: 0 }),
		mkRun({ startedAt: '2026-02-02T10:00:00', distance_m: 5000, duration_s: 1500 }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.equal(r.fastestPaceSecPerKm, 300);
	assert.ok(Number.isFinite(r.fastestPaceSecPerKm!));
});

test('buildYearInRunningRecap: zero runs → null earliest + latest start', () => {
	const r = buildYearInRunningRecap([], 2026);
	assert.equal(r.earliestStartLocal, null);
	assert.equal(r.latestStartLocal, null);
});

test('buildYearInRunningRecap: elevation falls back to 0 when absent', () => {
	// Reason: elevation_m is nullable on the row. mkRun defaults to 0
	// already; this test ensures the aggregate stays at 0 rather than
	// NaN-poisoning the sum when a single run has it absent.
	const runs = [
		mkRun({ startedAt: '2026-02-01T10:00:00', distance_m: 5000, duration_s: 1500 }),
		mkRun({ startedAt: '2026-02-02T10:00:00', distance_m: 5000, duration_s: 1500, elevation_m: 50 }),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.equal(r.totalElevationM, 50);
});

// ─────────── Badges + extras (Year-in-Sport parity) ───────────

test('buildYearInRunningRecap: extras default to 0 and emit no photo/PR badge', () => {
	const r = buildYearInRunningRecap(
		[mkRun({ startedAt: '2026-03-01T10:00:00', distance_m: 5000, duration_s: 1500 })],
		2026,
	);
	assert.equal(r.photoCount, 0);
	assert.equal(r.personalRecordCount, 0);
	assert.ok(!r.badges.some((b) => b.id.startsWith('photo')));
	assert.ok(!r.badges.some((b) => b.id.startsWith('pr')));
});

test('buildYearInRunningRecap: extras surface photo + PR counts and badges', () => {
	const r = buildYearInRunningRecap(
		[mkRun({ startedAt: '2026-03-01T10:00:00', distance_m: 5000, duration_s: 1500 })],
		2026,
		{ photoCount: 30, personalRecordCount: 6 },
	);
	assert.equal(r.photoCount, 30);
	assert.equal(r.personalRecordCount, 6);
	assert.equal(r.badges.find((b) => b.id.startsWith('photo'))?.id, 'photo-25');
	assert.equal(r.badges.find((b) => b.id.startsWith('pr'))?.id, 'pr-5');
});

test('buildYearInRunningRecap: negative / fractional extras are clamped to a non-negative int', () => {
	const r = buildYearInRunningRecap([], 2026, { photoCount: -3, personalRecordCount: 2.9 });
	assert.equal(r.photoCount, 0);
	assert.equal(r.personalRecordCount, 2);
});

test('badges: one badge per category — the highest tier reached wins', () => {
	// 1,200 km should produce the 1,000 km badge, not 500 + 100 too.
	const runs = Array.from({ length: 12 }, (_, i) =>
		mkRun({
			startedAt: `2026-0${(i % 9) + 1}-0${(i % 9) + 1}T10:00:00`,
			distance_m: 100_000,
			duration_s: 30_000,
		}),
	);
	const r = buildYearInRunningRecap(runs, 2026);
	const distBadges = r.badges.filter((b) => b.id.startsWith('dist-'));
	assert.equal(distBadges.length, 1);
	assert.equal(distBadges[0].id, 'dist-1000');
});

test('badges: a marathon-length longest run earns the Marathon trophy', () => {
	const r = buildYearInRunningRecap(
		[mkRun({ startedAt: '2026-04-01T08:00:00', distance_m: 42_300, duration_s: 14_400 })],
		2026,
	);
	assert.ok(r.badges.some((b) => b.id === 'long-marathon'));
	assert.ok(!r.badges.some((b) => b.id === 'long-ultra'));
});

test('badges: an early start before 06:00 earns the Early bird trophy', () => {
	const r = buildYearInRunningRecap(
		[mkRun({ startedAt: '2026-05-01T05:15:00', distance_m: 5000, duration_s: 1500 })],
		2026,
	);
	assert.ok(r.badges.some((b) => b.id === 'early'));
	assert.ok(!r.badges.some((b) => b.id === 'night'));
});

test('badges: an empty year earns no trophies', () => {
	const r = buildYearInRunningRecap([], 2026);
	assert.equal(r.badges.length, 0);
});
