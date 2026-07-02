import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	replanRemaining,
	MAKE_UP_MAX_INCREASE,
	EASE_OFF_SCALE,
	type ReplanWeek,
} from './plan_replan';

function wo(
	id: string,
	scheduledDate: string,
	kind: string,
	targetDistanceM: number | null,
	{ completed = false, skipped = false, isPast = false } = {},
) {
	return { id, scheduledDate, kind, targetDistanceM, completed, skipped, isPast };
}

test('replanRemaining: an on-track plan proposes no changes', () => {
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 40_000,
			actualMetres: 39_000,
			isComplete: true,
			workouts: [wo('a', '2026-06-01', 'long', 20_000, { completed: true, isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'build',
			plannedMetres: 42_000,
			actualMetres: 0,
			isComplete: false,
			workouts: [wo('b', '2026-06-08', 'long', 22_000)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-05' });
	assert.equal(r.onTrack, true);
	assert.equal(r.changes.length, 0);
});

test('replanRemaining: a missed long run in build is made up by bumping the next long (capped 15%)', () => {
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 40_000,
			actualMetres: 20_000,
			isComplete: true,
			// Missed the 28 km long run.
			workouts: [wo('missed', '2026-06-01', 'long', 28_000, { completed: false, isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'build',
			plannedMetres: 42_000,
			actualMetres: 0,
			isComplete: false,
			workouts: [wo('next', '2026-06-08', 'long', 22_000)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-05' });
	// The missed (past) run is frozen — never mutated.
	assert.equal(r.changes.some((c) => c.workoutId === 'missed'), false);
	const makeUp = r.changes.find((c) => c.workoutId === 'next');
	assert.equal(makeUp?.reason, 'make_up_long');
	// 28 km missed but capped to 22 km * 1.15 = 25.3 km → 25300.
	assert.equal(makeUp?.toMetres, Math.round(22_000 * (1 + MAKE_UP_MAX_INCREASE)));
});

test('replanRemaining: a make-up never shrinks an already-longer next long run', () => {
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 40_000,
			actualMetres: 20_000,
			isComplete: true,
			workouts: [wo('missed', '2026-06-01', 'long', 16_000, { isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'build',
			plannedMetres: 42_000,
			actualMetres: 0,
			isComplete: false,
			// Already longer than the missed one — no bump.
			workouts: [wo('next', '2026-06-08', 'long', 24_000)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-05' });
	// Next long already exceeds the missed distance → no make-up, and the
	// past missed run is frozen → no change at all.
	assert.equal(r.onTrack, true);
	assert.equal(r.changes.length, 0);
});

test('replanRemaining: several missed long runs make up the LARGEST, not the earliest', () => {
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 40_000,
			actualMetres: 20_000,
			isComplete: true,
			// Earliest miss (smaller).
			workouts: [wo('miss-a', '2026-06-01', 'long', 24_000, { isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'build',
			plannedMetres: 44_000,
			actualMetres: 22_000,
			isComplete: true,
			// Later miss (largest) — this is the one to recover.
			workouts: [wo('miss-b', '2026-06-08', 'long', 30_000, { isPast: true })],
		},
		{
			weekIndex: 2,
			phase: 'build',
			plannedMetres: 46_000,
			actualMetres: 0,
			isComplete: false,
			workouts: [wo('next', '2026-06-15', 'long', 22_000)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-12' });
	const makeUp = r.changes.find((c) => c.workoutId === 'next');
	assert.equal(makeUp?.reason, 'make_up_long');
	// Driven by the 30 km miss → capped to 22 km * 1.15 = 25.3 km → 25300,
	// NOT the earlier 24 km miss (which would only reach 24000).
	assert.equal(makeUp?.toMetres, Math.round(22_000 * (1 + MAKE_UP_MAX_INCREASE)));
	// Exactly one make-up change for the next long (no double-push).
	assert.equal(r.changes.filter((c) => c.reason === 'make_up_long').length, 1);
});

test('replanRemaining: largest missed long wins even when it is the EARLIEST week', () => {
	// Mirror image of the previous case — the largest miss now iterates
	// first. The result must be identical: order must not matter.
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 44_000,
			actualMetres: 22_000,
			isComplete: true,
			workouts: [wo('big', '2026-06-01', 'long', 30_000, { isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'build',
			plannedMetres: 40_000,
			actualMetres: 20_000,
			isComplete: true,
			workouts: [wo('small', '2026-06-08', 'long', 24_000, { isPast: true })],
		},
		{
			weekIndex: 2,
			phase: 'build',
			plannedMetres: 46_000,
			actualMetres: 0,
			isComplete: false,
			workouts: [wo('next', '2026-06-15', 'long', 22_000)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-12' });
	const makeUp = r.changes.find((c) => c.workoutId === 'next');
	assert.equal(makeUp?.toMetres, Math.round(22_000 * (1 + MAKE_UP_MAX_INCREASE)));
	assert.equal(r.changes.filter((c) => c.reason === 'make_up_long').length, 1);
});

test('replanRemaining: when the largest miss is under the cap the make-up reaches it exactly', () => {
	// Largest miss 24 km < cap (22 km * 1.15 = 25.3 km), so the make-up lands
	// ON the largest miss — proving the max feeds Math.min, not the cap, and
	// not the smaller/earlier 20 km miss.
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 40_000,
			actualMetres: 20_000,
			isComplete: true,
			workouts: [wo('small', '2026-06-01', 'long', 20_000, { isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'build',
			plannedMetres: 42_000,
			actualMetres: 21_000,
			isComplete: true,
			workouts: [wo('mid', '2026-06-08', 'long', 24_000, { isPast: true })],
		},
		{
			weekIndex: 2,
			phase: 'build',
			plannedMetres: 44_000,
			actualMetres: 0,
			isComplete: false,
			workouts: [wo('next', '2026-06-15', 'long', 22_000)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-12' });
	const makeUp = r.changes.find((c) => c.workoutId === 'next');
	assert.equal(makeUp?.toMetres, 24_000);
});

test('replanRemaining: a taper miss is excluded from the make-up max even if it is the largest', () => {
	// The 35 km taper miss gets "skip" advice → it must NOT drive the make-up.
	// Only the 23 km build miss is eligible, and it is under the cap, so the
	// next long lands on 23 km — not the taper's 35 km (which the cap would
	// otherwise mask as 25.3 km).
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 40_000,
			actualMetres: 20_000,
			isComplete: true,
			workouts: [wo('build-miss', '2026-06-01', 'long', 23_000, { isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'taper',
			plannedMetres: 38_000,
			actualMetres: 10_000,
			isComplete: true,
			workouts: [wo('taper-miss', '2026-06-08', 'long', 35_000, { isPast: true })],
		},
		{
			weekIndex: 2,
			phase: 'build',
			plannedMetres: 42_000,
			actualMetres: 0,
			isComplete: false,
			workouts: [wo('next', '2026-06-15', 'long', 22_000)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-12' });
	const makeUp = r.changes.find((c) => c.workoutId === 'next');
	assert.equal(makeUp?.toMetres, 23_000);
});

test('replanRemaining: three missed longs still produce exactly one capped make-up', () => {
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 36_000,
			actualMetres: 18_000,
			isComplete: true,
			workouts: [wo('m1', '2026-06-01', 'long', 18_000, { isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'build',
			plannedMetres: 44_000,
			actualMetres: 22_000,
			isComplete: true,
			workouts: [wo('m2', '2026-06-08', 'long', 31_000, { isPast: true })],
		},
		{
			weekIndex: 2,
			phase: 'build',
			plannedMetres: 40_000,
			actualMetres: 20_000,
			isComplete: true,
			workouts: [wo('m3', '2026-06-15', 'long', 24_000, { isPast: true })],
		},
		{
			weekIndex: 3,
			phase: 'build',
			plannedMetres: 46_000,
			actualMetres: 0,
			isComplete: false,
			workouts: [wo('next', '2026-06-22', 'long', 22_000)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-19' });
	const makeUps = r.changes.filter((c) => c.reason === 'make_up_long');
	assert.equal(makeUps.length, 1);
	// Largest miss is 31 km → capped to 22 km * 1.15.
	assert.equal(makeUps[0].toMetres, Math.round(22_000 * (1 + MAKE_UP_MAX_INCREASE)));
});

test('replanRemaining: a missed long run in the TAPER is skipped, never made up', () => {
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'taper',
			plannedMetres: 25_000,
			actualMetres: 10_000,
			isComplete: true,
			workouts: [wo('missed', '2026-06-01', 'long', 18_000, { isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'race',
			plannedMetres: 10_000,
			actualMetres: 0,
			isComplete: false,
			workouts: [wo('race', '2026-06-08', 'race', 42_195)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-05' });
	// Missed long in the taper → no make-up; race week untouched; past frozen.
	assert.equal(r.onTrack, true);
	assert.equal(r.changes.length, 0);
});

test('replanRemaining: an explicitly SKIPPED long run is never made up', () => {
	// The runner deliberately dropped this build-phase long run via the
	// workout-detail Skip button (skipped_at stamped → skipped: true). It's off
	// the books, so even though it is the largest miss, it must not drive a
	// make-up of the next long run.
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 44_000,
			actualMetres: 18_000,
			isComplete: true,
			workouts: [wo('skipped', '2026-06-01', 'long', 30_000, { skipped: true, isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'build',
			plannedMetres: 46_000,
			actualMetres: 0,
			isComplete: false,
			workouts: [wo('next', '2026-06-08', 'long', 22_000)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-05' });
	// No make-up proposed for the deliberately-skipped run.
	assert.equal(r.changes.some((c) => c.reason === 'make_up_long'), false);
	assert.equal(r.onTrack, true);
	assert.equal(r.changes.length, 0);
});

test('replanRemaining: a skipped long is excluded but a genuine miss still makes up', () => {
	// The largest miss (35 km) was explicitly skipped; only the 23 km genuine
	// miss is eligible, so the next long lands on 23 km — proving skip is
	// filtered out of the make-up max exactly like a taper miss.
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 40_000,
			actualMetres: 20_000,
			isComplete: true,
			workouts: [wo('genuine-miss', '2026-06-01', 'long', 23_000, { isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'build',
			plannedMetres: 48_000,
			actualMetres: 12_000,
			isComplete: true,
			workouts: [wo('skipped', '2026-06-08', 'long', 35_000, { skipped: true, isPast: true })],
		},
		{
			weekIndex: 2,
			phase: 'build',
			plannedMetres: 42_000,
			actualMetres: 0,
			isComplete: false,
			workouts: [wo('next', '2026-06-15', 'long', 22_000)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-12' });
	const makeUp = r.changes.find((c) => c.workoutId === 'next');
	assert.equal(makeUp?.toMetres, 23_000);
});

test('replanRemaining: cumulative over-running eases the next future week', () => {
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 40_000,
			actualMetres: 52_000, // +30% over → ease next week
			isComplete: true,
			workouts: [wo('a', '2026-06-01', 'easy', 10_000, { completed: true, isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'build',
			plannedMetres: 42_000,
			actualMetres: 0,
			isComplete: false,
			workouts: [
				wo('tempo', '2026-06-08', 'tempo', 12_000),
				wo('long', '2026-06-13', 'long', 22_000),
				wo('rest', '2026-06-09', 'rest', null),
			],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-05' });
	const ease = r.changes.find((c) => c.workoutId === 'tempo');
	assert.equal(ease?.reason, 'ease_over_running');
	assert.equal(ease?.toMetres, Math.round(12_000 * EASE_OFF_SCALE));
	// Long runs + rest days are not eased.
	assert.equal(r.changes.some((c) => c.workoutId === 'long'), false);
	assert.equal(r.changes.some((c) => c.workoutId === 'rest'), false);
});

test('replanRemaining: never touches a past (frozen) future-week placeholder or the taper', () => {
	const weeks: ReplanWeek[] = [
		{
			weekIndex: 0,
			phase: 'build',
			plannedMetres: 40_000,
			actualMetres: 60_000, // big over-run
			isComplete: true,
			workouts: [wo('done', '2026-06-01', 'tempo', 10_000, { completed: true, isPast: true })],
		},
		{
			weekIndex: 1,
			phase: 'taper',
			plannedMetres: 30_000,
			actualMetres: 0,
			isComplete: false,
			// Taper week — must not be eased even though we're over-running.
			workouts: [wo('taper-tempo', '2026-06-08', 'tempo', 8_000)],
		},
	];
	const r = replanRemaining({ weeks, today: '2026-06-05' });
	assert.equal(r.changes.length, 0);
	assert.equal(r.onTrack, true);
});
