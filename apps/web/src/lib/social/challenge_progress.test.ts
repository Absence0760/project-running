import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	progressFraction,
	isComplete,
	progressParts,
	metricFromActivity,
	rankParticipants,
	challengePace,
} from './challenge_progress';

const DAY = 86_400_000;

test('progressFraction clamps to 0..1', () => {
	assert.equal(progressFraction(50, 100), 0.5);
	assert.equal(progressFraction(150, 100), 1);
	assert.equal(progressFraction(-10, 100), 0);
});

test('progressFraction null goal → null', () => {
	assert.equal(progressFraction(50, null), null);
	assert.equal(progressFraction(50, 0), null);
});

test('isComplete respects >= goal', () => {
	assert.equal(isComplete(99, 100), false);
	assert.equal(isComplete(100, 100), true);
	assert.equal(isComplete(101, 100), true);
	assert.equal(isComplete(100, null), false);
});

test('progressParts bundles fraction + complete', () => {
	const p = progressParts('distance', 60000, 100000);
	assert.equal(p.metric, 'distance');
	assert.equal(p.value, 60000);
	assert.equal(p.goal, 100000);
	assert.equal(p.fraction, 0.6);
	assert.equal(p.complete, false);
});

test('progressParts goal-less board has null fraction', () => {
	const p = progressParts('distance', 60000, null);
	assert.equal(p.fraction, null);
	assert.equal(p.complete, false);
});

test('metricFromActivity distance reads distance_m (number or string)', () => {
	assert.equal(metricFromActivity({ distance_m: 5000 }, 'distance', null), 5000);
	assert.equal(metricFromActivity({ distance_m: '5000' }, 'distance', null), 5000);
});

test('metricFromActivity duration reads duration_s', () => {
	assert.equal(metricFromActivity({ duration_s: 1800 }, 'duration', null), 1800);
});

test('metricFromActivity vert reads elevation_gain_m (number or string, missing → 0)', () => {
	assert.equal(metricFromActivity({ elevation_gain_m: 640 }, 'vert', null), 640);
	assert.equal(metricFromActivity({ elevation_gain_m: '640' }, 'vert', null), 640);
	assert.equal(metricFromActivity({}, 'vert', null), 0);
});

test('metricFromActivity count + streak each contribute 1', () => {
	assert.equal(metricFromActivity({}, 'activity_count', null), 1);
	assert.equal(metricFromActivity({}, 'streak_days', null), 1);
});

test('metricFromActivity activity_type filter excludes non-matching', () => {
	assert.equal(metricFromActivity({ distance_m: 5000, activity_type: 'walk' }, 'distance', 'run'), 0);
	assert.equal(metricFromActivity({ distance_m: 5000, activity_type: 'run' }, 'distance', 'run'), 5000);
});

test('metricFromActivity defaults missing activity_type to run', () => {
	assert.equal(metricFromActivity({ distance_m: 5000 }, 'distance', 'run'), 5000);
});

test('metricFromActivity coerces null/garbage to 0', () => {
	assert.equal(metricFromActivity({ distance_m: null }, 'distance', null), 0);
	assert.equal(metricFromActivity({ distance_m: 'abc' }, 'distance', null), 0);
});

test('rankParticipants orders by value desc with stable user_id tie-break', () => {
	const ranked = rankParticipants([
		{ user_id: 'b', value: 30 },
		{ user_id: 'a', value: 50 },
		{ user_id: 'c', value: 50 },
	]);
	assert.deepEqual(
		ranked.map((r) => [r.entry.user_id, r.rank]),
		[
			['a', 1],
			['c', 1],
			['b', 3],
		],
	);
});

test('rankParticipants falls back to team_club_id for team boards', () => {
	const ranked = rankParticipants([
		{ user_id: null, team_club_id: 'blue', value: 50 },
		{ user_id: null, team_club_id: 'red', value: 50 },
	]);
	assert.deepEqual(
		ranked.map((r) => [r.entry.team_club_id, r.rank]),
		[
			['blue', 1],
			['red', 1],
		],
	);
});

test('challengePace on_track at the even-pace line mid-window', () => {
	const p = challengePace(50, 100, 0, 10 * DAY, 5 * DAY);
	assert.equal(p.status, 'active');
	assert.equal(p.elapsedFraction, 0.5);
	assert.equal(p.expectedValue, 50);
	assert.equal(p.projectedValue, 100);
	assert.equal(p.remainingValue, 50);
	assert.equal(p.daysRemaining, 5);
	assert.equal(p.requiredPerDay, 10);
	assert.equal(p.verdict, 'on_track');
});

test('challengePace behind flags the daily rate needed to finish', () => {
	const p = challengePace(30, 100, 0, 10 * DAY, 5 * DAY);
	assert.equal(p.verdict, 'behind');
	assert.equal(p.projectedValue, 60);
	assert.equal(p.remainingValue, 70);
	assert.equal(p.requiredPerDay, 14);
});

test('challengePace ahead when past the even-pace line', () => {
	const p = challengePace(70, 100, 0, 10 * DAY, 5 * DAY);
	assert.equal(p.verdict, 'ahead');
	assert.equal(p.projectedValue, 140);
	assert.equal(p.requiredPerDay, 6);
});

test('challengePace goal-less board nulls every goal-derived field', () => {
	const p = challengePace(50, null, 0, 10 * DAY, 5 * DAY);
	assert.equal(p.status, 'active');
	assert.equal(p.elapsedFraction, 0.5);
	assert.equal(p.daysRemaining, 5);
	assert.equal(p.expectedValue, null);
	assert.equal(p.projectedValue, null);
	assert.equal(p.remainingValue, null);
	assert.equal(p.requiredPerDay, null);
	assert.equal(p.verdict, null);
});

test('challengePace upcoming has no projection or verdict yet', () => {
	const p = challengePace(0, 100, 2 * DAY, 12 * DAY, 0);
	assert.equal(p.status, 'upcoming');
	assert.equal(p.elapsedFraction, 0);
	assert.equal(p.projectedValue, null);
	assert.equal(p.verdict, null);
	assert.equal(p.daysRemaining, 12);
});

test('challengePace ended freezes projection to the final value', () => {
	const p = challengePace(80, 100, 0, 10 * DAY, 11 * DAY);
	assert.equal(p.status, 'ended');
	assert.equal(p.elapsedFraction, 1);
	assert.equal(p.projectedValue, 80);
	assert.equal(p.remainingValue, 20);
	assert.equal(p.requiredPerDay, null);
	assert.equal(p.verdict, null);
	assert.equal(p.daysRemaining, 0);
});

test('challengePace complete drops the verdict + required rate', () => {
	const p = challengePace(120, 100, 0, 10 * DAY, 5 * DAY);
	assert.equal(p.verdict, null);
	assert.equal(p.remainingValue, 0);
	assert.equal(p.requiredPerDay, null);
});

test('challengePace daysRemaining ceils a partial day', () => {
	const p = challengePace(40, 100, 0, 10 * DAY, 5.5 * DAY);
	assert.equal(p.daysRemaining, 5);
	assert.equal(p.requiredPerDay, 12);
});
