import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	buildYearInRunningRecap,
	buildMonthInRunningRecap,
	recapHeadline,
	__TEST_ONLY__,
} from './recap';
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
		// The real column. The fixture used to set a top-level `elevation_m`,
		// which no row has — so every elevation assertion here passed against a
		// field production never reads, and totalElevationM was always 0 in the
		// app while the suite stayed green.
		elevation_gain_m: opts.elevation_m ?? 0,
		track_url: null,
		title: null,
		notes: null,
		route_id: opts.route_id ?? null,
		source: 'app',
		activity_type: opts.activity ?? 'run',
		metadata: {},
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

test('buildYearInRunningRecap: a cycle ride is not the fastest pace / longest run', () => {
	const runs = [
		// 5k run at 5:00/km (300 s/km).
		mkRun({ startedAt: '2026-03-01T10:00:00', distance_m: 5000, duration_s: 1500 }),
		// 40 km bike ride at 2:00/km (120 s/km) — faster pace + longer distance,
		// but a "Year in Running" headline must not surface it as either.
		mkRun({
			startedAt: '2026-04-01T10:00:00',
			distance_m: 40000,
			duration_s: 4800,
			activity: 'cycle',
		}),
	];
	const r = buildYearInRunningRecap(runs, 2026);
	assert.equal(r.fastestPaceSecPerKm, 300, 'fastest pace is the run, not the bike');
	assert.equal(r.longestRunM, 5000, 'longest run is the run, not the bike');
	// Totals stay all-inclusive (cross-modal by design).
	assert.equal(r.totalDistanceM, 45000);
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
	// Reason: the activity_type column defaults to 'run' but a fixture
	// may leave it unset. The helper must not crash and should count
	// missing-activity runs as "run" so the tally stays accurate.
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

test('buildYearInRunningRecap: elevation reads the legacy metadata key too', () => {
	// Older rows predate the promoted column and carry only
	// metadata.elevation_m — the key the Dart twin reads.
	const legacy = {
		...mkRun({ startedAt: '2026-03-01T08:00:00', distance_m: 10000, duration_s: 3000 }),
		elevation_gain_m: null,
		metadata: { elevation_m: 250 }
	} as unknown as Run;
	const recap = buildYearInRunningRecap([legacy], 2026);
	assert.equal(recap.totalElevationM, 250);
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

// ─────────── Monthly recap (buildMonthInRunningRecap) ───────────

test('buildMonthInRunningRecap: projects out a single month', () => {
	const runs = [
		mkRun({ startedAt: '2026-03-05T10:00:00', distance_m: 5000, duration_s: 1500 }),
		mkRun({ startedAt: '2026-03-20T10:00:00', distance_m: 7000, duration_s: 2100 }),
		mkRun({ startedAt: '2026-06-01T10:00:00', distance_m: 10000, duration_s: 2700 }),
	];
	const r = buildMonthInRunningRecap(runs, 2026, 3);
	assert.equal(r.month, 3);
	assert.equal(r.runCount, 2);
	assert.equal(r.totalDistanceM, 12000);
	assert.equal(r.totalDurationS, 3600);
	assert.equal(r.longestRunM, 7000);
});

test('buildMonthInRunningRecap: empty month → zeros, keeps the 12-month strip', () => {
	const runs = [mkRun({ startedAt: '2026-06-01T10:00:00', distance_m: 10000, duration_s: 2700 })];
	const r = buildMonthInRunningRecap(runs, 2026, 3);
	assert.equal(r.month, 3);
	assert.equal(r.runCount, 0);
	assert.equal(r.totalDistanceM, 0);
	assert.equal(r.longestRunM, 0);
	assert.equal(r.monthly.length, 12);
	// June still carries its data on the strip even on a March recap.
	assert.equal(r.monthly[5].distanceM, 10000);
});

test('buildMonthInRunningRecap: a cycle ride is not the month longest run / fastest pace', () => {
	const runs = [
		mkRun({ startedAt: '2026-04-01T10:00:00', distance_m: 5000, duration_s: 1500 }),
		mkRun({
			startedAt: '2026-04-02T10:00:00',
			distance_m: 40000,
			duration_s: 4800,
			activity: 'cycle',
		}),
	];
	const r = buildMonthInRunningRecap(runs, 2026, 4);
	assert.equal(r.longestRunM, 5000);
	assert.equal(r.fastestPaceSecPerKm, 300);
	// Totals stay all-inclusive.
	assert.equal(r.totalDistanceM, 45000);
});

test('buildMonthInRunningRecap: extras flow through to month badges', () => {
	const r = buildMonthInRunningRecap(
		[mkRun({ startedAt: '2026-05-01T10:00:00', distance_m: 5000, duration_s: 1500 })],
		2026,
		5,
		{ photoCount: 30, personalRecordCount: 6 },
	);
	assert.equal(r.photoCount, 30);
	assert.equal(r.personalRecordCount, 6);
	assert.equal(r.badges.find((b) => b.id.startsWith('photo'))?.id, 'photo-25');
	assert.equal(r.badges.find((b) => b.id.startsWith('pr'))?.id, 'pr-5');
});

test('buildMonthInRunningRecap: out-of-range month is zero, never throws', () => {
	const r = buildMonthInRunningRecap(
		[mkRun({ startedAt: '2026-05-01T10:00:00', distance_m: 5000, duration_s: 1500 })],
		2026,
		13,
	);
	assert.equal(r.runCount, 0);
	assert.equal(r.totalDistanceM, 0);
});

// --- Cross-year-boundary streaks -------------------------------------------
//
// Streaks are the one recap output derived from runs OUTSIDE the recap period:
// `computeRunStreaks` is handed the whole run set, clamped only at the period's
// last day. So a streak running 28 Dec → 3 Jan is the 2026 card's best streak
// even though four of its days are 2025 runs. These pin that dependency before
// any windowed fetch lands underneath the pages (#734).

const BOUNDARY_STREAK_DAYS = [
	'2025-12-28',
	'2025-12-29',
	'2025-12-30',
	'2025-12-31',
	'2026-01-01',
	'2026-01-02',
	'2026-01-03',
];

function boundaryStreakRuns(): Run[] {
	return BOUNDARY_STREAK_DAYS.map((day) =>
		mkRun({ startedAt: `${day}T10:00:00`, distance_m: 5000, duration_s: 1500 }),
	);
}

test('buildYearInRunningRecap: the 2026 best streak counts the December 2025 days', () => {
	const r = buildYearInRunningRecap(boundaryStreakRuns(), 2026);
	// Only the three January runs are inside the year…
	assert.equal(r.runCount, 3);
	assert.equal(r.totalDistanceM, 15000);
	// …but the streak spans the boundary, so dropping the 2025 runs from the
	// input would report 3 here instead of 7.
	assert.equal(r.bestStreakDays, 7);
	// `now` is stated, not inherited from the clock. Read against a January
	// 2027 reader the January 2026 streak is long dead, and that is the ONLY
	// reason this is 0 — before the anchor fix the assertion held for a
	// second, wrong reason (the card anchored at 31 Dec 2026 regardless of
	// when it was opened), so it stayed green over the live-streak case it
	// never exercised. The test below is that case.
	assert.equal(r.currentStreakDays, 0);
});

test('buildYearInRunningRecap: the card for the year you are IN reports the live streak', () => {
	// The anchor used to be 31 Dec of the card's year unconditionally. For the
	// current year that day is in the future, so `computeRunStreaks` looked for
	// a run on 31 Dec, then on its grace day of 30 Dec, found neither, and
	// returned 0 — every runner opening their own in-progress recap on a live
	// streak was told they had none.
	const now = new Date(2026, 2, 10, 9, 0); // 10 Mar 2026, 09:00 local
	const runs = ['2026-03-07', '2026-03-08', '2026-03-09', '2026-03-10'].map((day) =>
		mkRun({ startedAt: `${day}T07:00:00`, distance_m: 5000, duration_s: 1500 }),
	);
	const r = buildYearInRunningRecap(runs, 2026, {}, now);
	assert.equal(
		r.currentStreakDays,
		4,
		'a streak running up to and including today is the current streak',
	);
	assert.equal(r.bestStreakDays, 4);

	// The Strava grace day still applies at the near end: no run yet today,
	// but yesterday had one, so the streak is alive at its pre-today length.
	const beforeTodaysRun = buildYearInRunningRecap(runs.slice(0, 3), 2026, {}, now);
	assert.equal(
		beforeTodaysRun.currentStreakDays,
		3,
		'the grace day keeps a streak alive on a morning before the run',
	);

	// And a past year's card is unaffected: it still clamps at its own 31 Dec
	// rather than being dragged forward to now.
	const pastYear = buildYearInRunningRecap(boundaryStreakRuns(), 2025, {}, now);
	assert.equal(pastYear.currentStreakDays, 4);
});

test('buildMonthInRunningRecap: the month you are IN reports the live streak', () => {
	const now = new Date(2026, 2, 10, 9, 0);
	const runs = ['2026-03-07', '2026-03-08', '2026-03-09', '2026-03-10'].map((day) =>
		mkRun({ startedAt: `${day}T07:00:00`, distance_m: 5000, duration_s: 1500 }),
	);
	assert.equal(buildMonthInRunningRecap(runs, 2026, 3, {}, now).currentStreakDays, 4);
	// A finished month still clamps at its own last day.
	assert.equal(buildMonthInRunningRecap(boundaryStreakRuns(), 2025, 12, {}, now).currentStreakDays, 4);
});

test('buildYearInRunningRecap: the 2025 card clamps the streak at 31 Dec 2025', () => {
	const r = buildYearInRunningRecap(boundaryStreakRuns(), 2025);
	assert.equal(r.runCount, 4);
	// Runs after the anchor day are excluded, so the 2026 half is not counted.
	assert.equal(r.bestStreakDays, 4);
	assert.equal(r.currentStreakDays, 4);
});

test('buildMonthInRunningRecap: January 2026 best streak counts the December 2025 days', () => {
	const r = buildMonthInRunningRecap(boundaryStreakRuns(), 2026, 1);
	assert.equal(r.runCount, 3);
	assert.equal(r.bestStreakDays, 7);
	// The month card still carries the whole year's monthly buckets, so a month
	// page needs the full year's runs, not just the month's.
	assert.equal(r.monthly.length, 12);
	assert.equal(r.monthly[0].runCount, 3);
});

// --- Out-of-period streaks -------------------------------------------------
//
// The flip side of the boundary rule: a streak has to *reach* the period to be
// the period's streak. `computeRunStreaks` clamps only at the anchor day, so
// the whole of the runner's history used to be in scope and a long-dead streak
// became "your best streak" on a card titled with a year it never touched —
// and shipped in the public share image.

/** A 40-day streak in early 2024, then a short one inside the target period. */
function staleStreakRuns(): Run[] {
	const out: Run[] = [];
	for (let i = 0; i < 40; i++) {
		const d = new Date(2024, 1, 1 + i);
		out.push(
			mkRun({
				id: `old-${i}`,
				startedAt: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}T10:00:00`,
				distance_m: 5000,
				duration_s: 1500,
			}),
		);
	}
	for (const day of ['2026-03-10', '2026-03-11', '2026-03-12']) {
		out.push(mkRun({ id: day, startedAt: `${day}T10:00:00`, distance_m: 5000, duration_s: 1500 }));
	}
	return out;
}

test('buildYearInRunningRecap: a streak from a previous year is not this year’s best', () => {
	const r = buildYearInRunningRecap(staleStreakRuns(), 2026);
	assert.equal(r.runCount, 3);
	assert.equal(r.bestStreakDays, 3, 'the 2024 streak must not headline the 2026 card');
});

test('buildYearInRunningRecap: an out-of-period streak earns no trophy', () => {
	const r = buildYearInRunningRecap(staleStreakRuns(), 2026);
	assert.equal(
		r.badges.find((b) => b.id.startsWith('streak')),
		undefined,
		'a 2024 streak must not put a streak trophy on the 2026 grid',
	);
});

test('buildYearInRunningRecap: a year with no runs at all has no streak', () => {
	const r = buildYearInRunningRecap(staleStreakRuns(), 2025);
	assert.equal(r.runCount, 0);
	assert.equal(r.bestStreakDays, 0);
	assert.equal(r.currentStreakDays, 0);
});

test('buildMonthInRunningRecap: a streak from an earlier month is not this month’s best', () => {
	// The 3-day streak sits in March; the April card must not claim it.
	const r = buildMonthInRunningRecap(staleStreakRuns(), 2026, 4);
	assert.equal(r.runCount, 0);
	assert.equal(r.bestStreakDays, 0);
	assert.equal(r.badges.find((b) => b.id.startsWith('streak')), undefined);
});

test('buildMonthInRunningRecap: the month the streak ran in still reports it', () => {
	const r = buildMonthInRunningRecap(staleStreakRuns(), 2026, 3);
	assert.equal(r.runCount, 3);
	assert.equal(r.bestStreakDays, 3);
});

test('a non-numeric extras count is floored to 0, not propagated as NaN', () => {
	// `Math.max(0, Math.trunc(x ?? 0))` does not floor a NaN — `Math.trunc(NaN)`
	// is NaN and `Math.max(0, NaN)` is NaN — so a non-numeric count from
	// `fetchRecapExtras` reached the recap object, the badge thresholds it
	// feeds, and every snapshot published to `public_recaps`.
	const bad = { photoCount: NaN, personalRecordCount: Infinity };
	const y = buildYearInRunningRecap([], 2026, bad);
	assert.equal(y.photoCount, 0);
	assert.equal(y.personalRecordCount, 0);
	const mth = buildMonthInRunningRecap([], 2026, 3, bad);
	assert.equal(mth.photoCount, 0);
	assert.equal(mth.personalRecordCount, 0);
	// A count that IS a number still survives the same path.
	assert.equal(buildYearInRunningRecap([], 2026, { photoCount: 7.9 }).photoCount, 7);
});

test('the recap week is ISO Monday-anchored, deliberately unlike the dashboard strip', () => {
	// `training/current_week.ts` honours the runner's `week_start` over the same
	// runs; this does not, and the difference is a decision rather than drift. A
	// recap is PUBLISHED to `public_recaps` and re-rendered by /recap/share/[id]
	// and the OG image for readers who are not the runner, from a payload whose
	// Dart producer writes the same field shape from another device — a week
	// boundary that varied with a preference would make one artifact mean two
	// things with nothing in it saying which.
	const { mondayOf } = __TEST_ONLY__;
	// 2026-03-08 is a Sunday; a Sunday-first reading would open a week there.
	assert.equal(mondayOf(new Date(2026, 2, 8)), '2026-03-02');
	assert.equal(mondayOf(new Date(2026, 2, 9)), '2026-03-09');
});
