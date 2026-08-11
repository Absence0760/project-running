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

test('marking a week recovery strips the interval structure, not just the kind', () => {
	// A generated build-phase interval carries a `structure` describing the
	// session. Converting kind → recovery while leaving it behind produced a
	// "Recovery" workout that still described (and, on mobile, still EXECUTED)
	// 5 x 1000 m at VO2max pace: the workout-detail page renders the Structure
	// card from it, and expandWorkoutSteps in run_recorder builds the executed
	// step list from it. The stated 5100 m also contradicted the structure's
	// own 8500 m of work.
	const patch = recoveryWorkoutPatch({
		kind: 'interval',
		target_distance_m: 8500,
		target_pace_sec_per_km: 269,
		structure: {
			warmup: { distance_m: 1500, pace: 'easy' },
			repeats: { count: 5, distance_m: 1000, pace_sec_per_km: 269, recovery_distance_m: 400 },
			cooldown: { distance_m: 1500, pace: 'easy' }
		}
	} as Parameters<typeof recoveryWorkoutPatch>[0]);
	assert.ok(patch);
	assert.equal(patch!.kind, 'recovery');
	assert.equal(patch!.target_pace_sec_per_km, null);
	assert.equal(patch!.target_pace_tolerance_sec, null);
	assert.equal(patch!.structure, null, 'the VO2max session must not survive the deload');
	assert.equal(patch!.target_distance_m, Math.round(8500 * RECOVERY_SCALE));
});

test('every quality kind sheds its structure on a recovery week', () => {
	for (const kind of ['tempo', 'interval', 'marathon_pace']) {
		const patch = recoveryWorkoutPatch({
			kind,
			target_distance_m: 8000,
			structure: { steady: { distance_m: 5000, pace_sec_per_km: 300 } }
		} as Parameters<typeof recoveryWorkoutPatch>[0]);
		assert.ok(patch, kind);
		assert.equal(patch!.structure, null, kind);
	}
});

test('a non-quality workout keeps its shape apart from the volume scale', () => {
	// An easy/long run is only scaled — clearing a structure it does not have
	// must not start emitting a spurious null that would wipe a real one.
	const patch = recoveryWorkoutPatch({ kind: 'long', target_distance_m: 20_000 } as Parameters<
		typeof recoveryWorkoutPatch
	>[0]);
	assert.ok(patch);
	assert.equal(patch!.kind, undefined);
	assert.equal('structure' in patch!, false);
	assert.equal(patch!.target_distance_m, Math.round(20_000 * RECOVERY_SCALE));
});
