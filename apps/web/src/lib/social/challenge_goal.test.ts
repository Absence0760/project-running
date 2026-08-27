import { test } from 'node:test';
import assert from 'node:assert/strict';
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
