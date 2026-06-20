import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	progressFraction,
	isComplete,
	progressParts,
	metricFromActivity,
	rankParticipants,
} from './challenge_progress';

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
