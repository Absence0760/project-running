import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	weeklyDrift,
	missedWorkoutAdvice,
	PLAN_DRIFT_THRESHOLD,
} from './plan_adherence';

// ─────────────────────── weeklyDrift ───────────────────────

test('weeklyDrift: on-track when actual matches planned', () => {
	const d = weeklyDrift(40_000, 41_000);
	assert.equal(d.direction, 'on_track');
	assert.equal(d.flagged, false);
});

test('weeklyDrift: flags under-running past the threshold', () => {
	// 40 km planned, 28 km actual → −30% drift.
	const d = weeklyDrift(40_000, 28_000);
	assert.equal(d.direction, 'under');
	assert.equal(d.flagged, true);
	assert.ok(d.driftFraction < -PLAN_DRIFT_THRESHOLD);
});

test('weeklyDrift: flags over-running past the threshold', () => {
	// 40 km planned, 52 km actual → +30% drift (the easy-week trap).
	const d = weeklyDrift(40_000, 52_000);
	assert.equal(d.direction, 'over');
	assert.equal(d.flagged, true);
	assert.ok(d.driftFraction > PLAN_DRIFT_THRESHOLD);
});

test('weeklyDrift: just inside the threshold is not flagged', () => {
	// 40 km planned, 47 km actual → +17.5%, under the 20% bar.
	const d = weeklyDrift(40_000, 47_000);
	assert.equal(d.direction, 'on_track');
	assert.equal(d.flagged, false);
});

test('weeklyDrift: no planned volume yields a neutral, unflagged result', () => {
	const d = weeklyDrift(0, 30_000);
	assert.equal(d.direction, 'on_track');
	assert.equal(d.flagged, false);
	assert.equal(d.driftFraction, 0);
});

test('weeklyDrift: clamps negative actual to zero', () => {
	const d = weeklyDrift(40_000, -5);
	assert.equal(d.actualMetres, 0);
	assert.equal(d.direction, 'under');
});

// ─────────────────────── missedWorkoutAdvice ───────────────────────

test('missedWorkoutAdvice: base/build long run is worth making up', () => {
	const a = missedWorkoutAdvice({
		kind: 'long',
		isTaper: false,
		recoveryWeekImminent: false,
	});
	assert.equal(a.recommendation, 'make_up');
	assert.equal(a.reason, 'key_session');
});

test('missedWorkoutAdvice: skip a long run missed in the taper', () => {
	const a = missedWorkoutAdvice({
		kind: 'long',
		isTaper: true,
		recoveryWeekImminent: false,
	});
	assert.equal(a.recommendation, 'skip');
	assert.equal(a.reason, 'taper');
});

test('missedWorkoutAdvice: skip when a recovery week is imminent', () => {
	const a = missedWorkoutAdvice({
		kind: 'long',
		isTaper: false,
		recoveryWeekImminent: true,
	});
	assert.equal(a.recommendation, 'skip');
	assert.equal(a.reason, 'recovery_soon');
});

test('missedWorkoutAdvice: taper takes precedence over recovery-soon', () => {
	const a = missedWorkoutAdvice({
		kind: 'long',
		isTaper: true,
		recoveryWeekImminent: true,
	});
	assert.equal(a.reason, 'taper');
});

test('missedWorkoutAdvice: a missed quality session is just skipped', () => {
	for (const kind of ['tempo', 'interval', 'easy', 'marathon_pace']) {
		const a = missedWorkoutAdvice({ kind, isTaper: false, recoveryWeekImminent: false });
		assert.equal(a.recommendation, 'skip');
		assert.equal(a.reason, 'not_long_run');
	}
});
