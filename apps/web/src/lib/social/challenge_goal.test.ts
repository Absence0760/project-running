import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
	challengeGoalUnit,
	challengeGoalToStored,
	challengeGoalFromStored,
	maxStreakDaysInWindow,
	checkChallengeGoal,
} from './challenge_goal';
import type { ChallengeMetric } from './challenge_progress';

const DAY = 86_400_000;
const METRICS: ChallengeMetric[] = [
	'distance',
	'duration',
	'vert',
	'activity_count',
	'streak_days',
];

test('challengeGoalUnit names one unit for every metric the CHECK admits', () => {
	assert.deepEqual(
		METRICS.map(challengeGoalUnit),
		['distance', 'hours', 'elevation', 'activities', 'days'],
	);
});

test('a distance goal is typed in the reader own unit', () => {
	assert.equal(challengeGoalToStored(100, 'distance', 'km'), 100_000);
	assert.equal(challengeGoalToStored(100, 'distance', 'mi'), 160_934.4);
});

test('an elevation goal is metres for km, feet for mi', () => {
	assert.equal(challengeGoalToStored(2000, 'vert', 'km'), 2000);
	assert.ok(Math.abs(challengeGoalToStored(1000, 'vert', 'mi') - 304.8) < 0.01);
});

test('a duration goal is typed in hours and stored in seconds', () => {
	assert.equal(challengeGoalToStored(5, 'duration', 'km'), 18_000);
	assert.equal(challengeGoalToStored(0.5, 'duration', 'mi'), 1800);
});

test('the two counting metrics pass through unconverted under either unit', () => {
	for (const unit of ['km', 'mi'] as const) {
		assert.equal(challengeGoalToStored(10, 'activity_count', unit), 10);
		assert.equal(challengeGoalToStored(7, 'streak_days', unit), 7);
	}
});

test('challengeGoalFromStored inverts every metric', () => {
	for (const metric of METRICS) {
		for (const unit of ['km', 'mi'] as const) {
			const stored = challengeGoalToStored(42, metric, unit);
			assert.ok(
				Math.abs(challengeGoalFromStored(stored, metric, unit) - 42) < 1e-9,
				`${metric}/${unit}`,
			);
		}
	}
});

test('maxStreakDaysInWindow is the count of dates a window can touch', () => {
	// A window opening just after midnight spans floor(len / day) + 1 dates.
	assert.equal(maxStreakDaysInWindow(0, DAY), 2);
	assert.equal(maxStreakDaysInWindow(0, DAY + 1), 2);
	assert.equal(maxStreakDaysInWindow(0, 2 * DAY), 3);
	assert.equal(maxStreakDaysInWindow(0, 30 * DAY), 31);
});

test('maxStreakDaysInWindow claims nothing for an empty or inverted window', () => {
	assert.equal(maxStreakDaysInWindow(DAY, DAY), 0);
	assert.equal(maxStreakDaysInWindow(2 * DAY, DAY), 0);
});

test('maxStreakDaysInWindow claims nothing for a non-finite bound', () => {
	assert.equal(maxStreakDaysInWindow(Number.NaN, DAY), 0);
	assert.equal(maxStreakDaysInWindow(0, Number.POSITIVE_INFINITY), 0);
});

test('a goal-less board is always acceptable', () => {
	for (const metric of METRICS) {
		assert.equal(checkChallengeGoal(null, metric, 0, 30 * DAY), null);
	}
});

test('a zero goal is refused — the completion RPC awards it to everyone', () => {
	assert.equal(checkChallengeGoal(0, 'distance', 0, 30 * DAY), 'not_positive');
});

test('a negative or non-finite goal is refused', () => {
	assert.equal(checkChallengeGoal(-1, 'distance', 0, 30 * DAY), 'not_positive');
	assert.equal(checkChallengeGoal(Number.NaN, 'distance', 0, 30 * DAY), 'not_positive');
	assert.equal(
		checkChallengeGoal(Number.POSITIVE_INFINITY, 'distance', 0, 30 * DAY),
		'not_positive',
	);
});

test('a streak goal inside the window ceiling is accepted', () => {
	assert.equal(checkChallengeGoal(31, 'streak_days', 0, 30 * DAY), null);
});

test('a streak goal above the window ceiling is refused', () => {
	assert.equal(checkChallengeGoal(32, 'streak_days', 0, 30 * DAY), 'exceeds_window');
	assert.equal(checkChallengeGoal(8, 'streak_days', 0, 3 * DAY), 'exceeds_window');
});

test('a duration goal longer than its own window is NOT refused', () => {
	// The aggregate sums duration_s over runs whose START is in the window; a
	// run started a minute before it closes carries its whole duration, so a
	// 112-hour finish can satisfy a goal the window itself could not hold.
	assert.equal(checkChallengeGoal(112 * 3600, 'duration', 0, DAY), null);
});

test('the three unbounded metrics take any positive goal', () => {
	for (const metric of ['distance', 'vert', 'activity_count'] as const) {
		assert.equal(checkChallengeGoal(1e9, metric, 0, DAY), null);
	}
});

// ─────────── the SQL rail ───────────
//
// `challenges_goal_ck` is the third rail this pair mirrors, and its own
// comment says so: "Mirrored client-side by checkChallengeGoal /
// maxStreakDaysInWindow on both platforms." Nothing read it. Changing the
// SQL `+ 1` to `+ 0`, or its `> 0` floor to `>= 0`, leaves every
// assertion above green while the client offers a goal Postgres refuses
// as a raw 23514 that names neither bound — which is the exact failure
// the client half exists to prevent.

const GOAL_CK = resolve(
	'../backend/supabase/migrations/20270615_001_challenge_goal_check.sql',
);

function goalConstraintSql(): string {
	const sql = readFileSync(GOAL_CK, 'utf-8');
	const at = sql.indexOf('add constraint challenges_goal_ck');
	assert.notEqual(at, -1, 'challenges_goal_ck is no longer added by this migration');
	const end = sql.indexOf('not valid;', at);
	assert.notEqual(end, -1, 'the constraint body no longer ends where this guard expects');
	// Collapse whitespace so the assertions below are about the predicate,
	// not about how the migration happens to be indented.
	return sql.slice(at, end).replace(/\s+/g, ' ');
}

test('the SQL floor is strict, matching `not_positive` covering 0', () => {
	assert.match(
		goalConstraintSql(),
		/goal_value > 0/,
		'a `>= 0` floor would store a 0 goal, which recompute_challenge_completion ' +
			'awards to every participant while both clients render the board as goal-less',
	);
	assert.equal(checkChallengeGoal(0, 'distance', 0, DAY), 'not_positive');
	assert.equal(checkChallengeGoal(1, 'distance', 0, DAY), null);
});

test('only streak_days is window-bounded on both rails', () => {
	const sql = goalConstraintSql();
	const bounded = [...sql.matchAll(/metric <> '([a-z_]+)'/g)].map((m) => m[1]);
	assert.deepEqual(
		bounded,
		['streak_days'],
		'the SQL bounds a different metric set than the client does',
	);
	// A duration goal longer than its own window is deliberately allowed:
	// the aggregate sums duration_s over runs whose START falls inside the
	// window, so a 112-hour finish begun a minute before it closes counts.
	assert.equal(checkChallengeGoal(400_000, 'duration', 0, DAY), null);
	assert.equal(checkChallengeGoal(3, 'streak_days', 0, DAY), 'exceeds_window');
});

test('the window ceiling is derived from the SQL, not restated beside it', () => {
	const sql = goalConstraintSql();
	const bound = sql.match(
		/goal_value (<=|<) floor\(extract\(epoch from \(ends_at - starts_at\)\) \/ (\d+)\) \+ (\d+)/,
	);
	assert.ok(bound, `the streak bound no longer matches a readable shape in ${GOAL_CK}`);
	const [, comparison, secondsPerDay, addend] = bound;
	assert.equal(comparison, '<=', 'the SQL bound is inclusive; the client refuses only ABOVE it');
	// Evaluate the SQL's own predicate in JS and hold the client to it over
	// a spread of windows, so a change to either number fails here.
	const sqlCeiling = (startMs: number, endMs: number): number =>
		Math.floor((endMs - startMs) / 1000 / Number(secondsPerDay)) + Number(addend);
	for (const days of [1, 2, 7, 30, 365]) {
		const endMs = days * DAY;
		assert.equal(
			maxStreakDaysInWindow(0, endMs),
			sqlCeiling(0, endMs),
			`the client and the CHECK disagree about a ${days}-day window`,
		);
		const ceiling = sqlCeiling(0, endMs);
		assert.equal(checkChallengeGoal(ceiling, 'streak_days', 0, endMs), null);
		assert.equal(
			checkChallengeGoal(ceiling + 1, 'streak_days', 0, endMs),
			'exceeds_window',
		);
	}
	// The client's own day constant has to be the SQL's, expressed in ms.
	assert.equal(Number(secondsPerDay) * 1000, DAY);
});

test('a streak goal is refused outright when the window is unusable', () => {
	// The ceiling collapses to 0, so every positive goal is refused. Only
	// exercised at the maxStreakDaysInWindow level before this.
	for (const [startMs, endMs] of [
		[Number.NaN, DAY],
		[0, Number.NaN],
		[DAY, 0],
		[DAY, DAY],
	]) {
		assert.equal(maxStreakDaysInWindow(startMs, endMs), 0);
		assert.equal(checkChallengeGoal(1, 'streak_days', startMs, endMs), 'exceeds_window');
		// An unbounded metric is unaffected by an unusable window.
		assert.equal(checkChallengeGoal(1, 'distance', startMs, endMs), null);
	}
});

