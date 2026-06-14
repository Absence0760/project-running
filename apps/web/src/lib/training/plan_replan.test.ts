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
	{ completed = false, isPast = false } = {},
) {
	return { id, scheduledDate, kind, targetDistanceM, completed, isPast };
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
