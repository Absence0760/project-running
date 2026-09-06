import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { RunningPrTracker, normaliseExerciseName, type GymSetLike } from './gym_prs';

/**
 * The TS half of the `gym_workout_summaries` drift pin.
 *
 * /gym used to derive its PR badges and row stats in the browser from every
 * gym_sets row the account held — an unbounded read PostgREST truncates at
 * 1000 rows. Migration 20270510_001 moved the aggregation into SQL. The PR
 * definition still lives in `gym_prs.ts` (mirrored in `gym_prs.dart`), so the
 * SQL is a mirror and can drift from it silently.
 *
 * This file and `apps/backend/supabase/tests/gym_workout_summaries_test.sql`
 * build the SAME fixture and assert the SAME expected answer — this one by
 * running the real `RunningPrTracker`, that one by calling the RPC. Change one
 * side and the other fails.
 *
 * Fixture (oldest → newest), chosen to separate the three PR metrics:
 *   w1  Bench 60x5, Bench 60x8, OHP 40x8, Pull-up 10xnull   first of everything
 *   w2  <TAB>Bench 60x5, <TAB> 5x50                          beats nothing
 *   w3  "bench  press" 62.5x3                               weight PR only
 *   w4  Pull-up 12xnull                                     bodyweight, no PR
 *   w5  Back Squat 100x5                                    new exercise
 *   w6  OHP 40x10                                           volume + e1rm PR
 */

interface FixtureWorkout {
	id: string;
	sets: Array<{ exercise_name: string; reps: number | null; weight_kg: number | null }>;
}

/** Oldest first — the order `gym_workout_summaries` judges them in. */
const FIXTURE: FixtureWorkout[] = [
	{
		id: 'w1',
		sets: [
			{ exercise_name: 'Bench Press', reps: 5, weight_kg: 60 },
			{ exercise_name: 'Bench Press', reps: 8, weight_kg: 60 },
			{ exercise_name: 'Overhead Press', reps: 8, weight_kg: 40 },
			{ exercise_name: 'Pull-up', reps: 10, weight_kg: null },
		],
	},
	{
		id: 'w2',
		sets: [
			// Tab-prefixed on purpose. Postgres `btrim(text)` strips U+0020 alone,
			// so before migration 20270623000001 this keyed as ' bench press'
			// server-side and 'bench press' here — a brand-new exercise to the
			// RPC, and a first sighting is a PR on all three metrics, so w2
			// joined the SQL side's is_pr set and not this one (decisions § 790).
			{ exercise_name: '\u0009Bench Press', reps: 5, weight_kg: 60 },
			// A whitespace-only name passes the length(1..120) CHECK. It carries
			// weight into the volume stat but is not an exercise and can never
			// set a PR. A TAB rather than a space for the same reason: the old
			// blank-name filter `btrim(coalesce(name,'')) <> ''` kept it.
			{ exercise_name: '\u0009', reps: 5, weight_kg: 50 },
		],
	},
	{ id: 'w3', sets: [{ exercise_name: 'bench  press', reps: 3, weight_kg: 62.5 }] },
	{ id: 'w4', sets: [{ exercise_name: 'Pull-up', reps: 12, weight_kg: null }] },
	{ id: 'w5', sets: [{ exercise_name: 'Back Squat', reps: 5, weight_kg: 100 }] },
	{ id: 'w6', sets: [{ exercise_name: 'Overhead Press', reps: 10, weight_kg: 40 }] },
];

/** The `is_pr` column the RPC must return true for, and for nothing else. */
const EXPECTED_PR_WORKOUTS = ['w1', 'w3', 'w5', 'w6'];

/** `(set_count, exercise_count, volume_kg)` per workout. */
const EXPECTED_STATS: Record<string, [number, number, number]> = {
	w1: [4, 3, 1100],
	w2: [2, 1, 550],
	w3: [1, 1, 188],
	w4: [1, 1, 0],
	w5: [1, 1, 500],
	w6: [1, 1, 400],
};

test('gym_workout_summaries: is_pr matches RunningPrTracker over the shared fixture', () => {
	const tracker = new RunningPrTracker();
	const flagged: string[] = [];
	for (const w of FIXTURE) {
		const sets: GymSetLike[] = w.sets.map((s) => ({
			exercise_name: s.exercise_name,
			reps: s.reps,
			weight_kg: s.weight_kg,
		}));
		if (tracker.judge(sets).length > 0) flagged.push(w.id);
	}
	assert.deepEqual(flagged, EXPECTED_PR_WORKOUTS);
});

test('gym_workout_summaries: w3 is a weight PR on the whitespace-collapsed name', () => {
	// "bench  press" and "Bench Press" are one exercise, so w3's 62.5 kg has to
	// be judged against w1's 60 kg rather than treated as a brand-new lift.
	assert.equal(normaliseExerciseName('bench  press'), normaliseExerciseName('Bench Press'));
	const tracker = new RunningPrTracker();
	tracker.judge(FIXTURE[0].sets);
	tracker.judge(FIXTURE[1].sets);
	assert.deepEqual(tracker.judge(FIXTURE[2].sets), [
		{ key: 'bench press', exerciseName: 'bench  press', kinds: ['weight'] },
	]);
});

test('gym_workout_summaries: w6 is a volume + e1rm PR at an unchanged weight', () => {
	const tracker = new RunningPrTracker();
	for (const w of FIXTURE.slice(0, 5)) tracker.judge(w.sets);
	assert.deepEqual(tracker.judge(FIXTURE[5].sets), [
		{ key: 'overhead press', exerciseName: 'Overhead Press', kinds: ['volume', 'e1rm'] },
	]);
});

test('gym_workout_summaries: the row stats the SQL returns per workout', () => {
	for (const w of FIXTURE) {
		const [setCount, exerciseCount, volumeKg] = EXPECTED_STATS[w.id];
		assert.equal(w.sets.length, setCount, `${w.id} set_count`);

		const names = new Set<string>();
		for (const s of w.sets) {
			const key = normaliseExerciseName(s.exercise_name);
			if (key !== '') names.add(key);
		}
		assert.equal(names.size, exerciseCount, `${w.id} exercise_count`);

		let volume = 0;
		for (const s of w.sets) {
			if (s.reps != null && s.weight_kg != null) volume += s.reps * s.weight_kg;
		}
		assert.equal(Math.round(volume), volumeKg, `${w.id} volume_kg`);
	}
});

test('gym_workout_summaries: the whitespace-only set is volume, not an exercise', () => {
	const w2 = FIXTURE[1];
	assert.equal(normaliseExerciseName(w2.sets[1].exercise_name), '');
	// 60x5 + 50x5 — the blank-named set is still work performed.
	assert.equal(EXPECTED_STATS.w2[2], 550);
	assert.equal(EXPECTED_STATS.w2[1], 1);
});
