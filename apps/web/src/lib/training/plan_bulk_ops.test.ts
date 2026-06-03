import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	shiftIsoDate,
	recoveryWorkoutPatch,
	recoveryWeekVolume,
	RECOVERY_SCALE,
} from './plan_bulk_ops';

// ─────────────────────── shiftIsoDate ───────────────────────

test('shiftIsoDate: forward + backward', () => {
	assert.equal(shiftIsoDate('2026-06-07', 7), '2026-06-14');
	assert.equal(shiftIsoDate('2026-06-07', -7), '2026-05-31');
});

test('shiftIsoDate: crosses month + year boundaries', () => {
	assert.equal(shiftIsoDate('2026-06-28', 5), '2026-07-03');
	assert.equal(shiftIsoDate('2026-12-30', 3), '2027-01-02');
});

test('shiftIsoDate: zero is identity', () => {
	assert.equal(shiftIsoDate('2026-06-07', 0), '2026-06-07');
});

// ─────────────────────── recoveryWorkoutPatch ───────────────────────

test('recoveryWorkoutPatch: leaves rest + race untouched', () => {
	assert.equal(recoveryWorkoutPatch({ kind: 'rest', target_distance_m: null }), null);
	assert.equal(recoveryWorkoutPatch({ kind: 'race', target_distance_m: 42_195 }), null);
});

test('recoveryWorkoutPatch: converts a quality session to recovery + clears pace', () => {
	const p = recoveryWorkoutPatch({ kind: 'tempo', target_distance_m: 12_000 });
	assert.equal(p?.kind, 'recovery');
	assert.equal(p?.target_pace_sec_per_km, null);
	assert.equal(p?.target_distance_m, Math.round(12_000 * RECOVERY_SCALE));
});

test('recoveryWorkoutPatch: scales an easy run distance but keeps its kind', () => {
	const p = recoveryWorkoutPatch({ kind: 'easy', target_distance_m: 10_000 });
	assert.equal(p?.kind, undefined); // kind unchanged
	assert.equal(p?.target_distance_m, 6_000);
});

test('recoveryWorkoutPatch: a distance-less easy run has nothing to change', () => {
	assert.equal(recoveryWorkoutPatch({ kind: 'easy', target_distance_m: null }), null);
});

test('recoveryWorkoutPatch: long run scales but stays a long run', () => {
	const p = recoveryWorkoutPatch({ kind: 'long', target_distance_m: 30_000 });
	assert.equal(p?.kind, undefined);
	assert.equal(p?.target_distance_m, 18_000);
});

// ─────────────────────── recoveryWeekVolume ───────────────────────

test('recoveryWeekVolume: scales volume, passes through null', () => {
	assert.equal(recoveryWeekVolume(50_000), 30_000);
	assert.equal(recoveryWeekVolume(null), null);
});
