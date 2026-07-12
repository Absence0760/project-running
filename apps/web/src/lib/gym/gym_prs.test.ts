import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	estimatedOneRepMax,
	normaliseExerciseName,
	computeExercisePrs,
	workoutPrs,
	RunningPrTracker,
	kE1rmMaxReps,
	type GymSetLike,
} from './gym_prs';

function set(exercise_name: string, reps: number | null, weight_kg: number | null): GymSetLike {
	return { exercise_name, reps, weight_kg };
}

test('estimatedOneRepMax: a true single reports the lifted weight', () => {
	assert.equal(estimatedOneRepMax(100, 1), 100);
});

test('estimatedOneRepMax: Epley for multi-rep sets', () => {
	// 100 × 5 → 100 · (1 + 5/30) = 116.666…
	assert.ok(Math.abs(estimatedOneRepMax(100, 5) - 116.6667) < 0.001);
});

test('estimatedOneRepMax: reps clamp past the accuracy ceiling', () => {
	// 30 reps is clamped to kE1rmMaxReps so an endurance set can't fake a 1RM.
	assert.equal(estimatedOneRepMax(50, 30), estimatedOneRepMax(50, kE1rmMaxReps));
});

test('estimatedOneRepMax: non-positive inputs return 0', () => {
	assert.equal(estimatedOneRepMax(0, 5), 0);
	assert.equal(estimatedOneRepMax(100, 0), 0);
	assert.equal(estimatedOneRepMax(-5, 5), 0);
});

test('estimatedOneRepMax: fractional reps keep the fraction (not truncated to int)', () => {
	// 100 × 5.5 → 100 · (1 + 5.5/30) = 118.333…, distinct from 100 × 5.
	assert.ok(Math.abs(estimatedOneRepMax(100, 5.5) - 118.3333) < 0.001);
	assert.notEqual(estimatedOneRepMax(100, 5.5), estimatedOneRepMax(100, 5));
});

test('normaliseExerciseName: case, trim, whitespace collapse', () => {
	assert.equal(normaliseExerciseName('  Bench  Press '), 'bench press');
	assert.equal(normaliseExerciseName('bench press'), 'bench press');
});

test('computeExercisePrs: groups case-insensitively and keeps first spelling', () => {
	const prs = computeExercisePrs([
		set('Bench Press', 5, 100),
		set('bench press', 3, 110),
	]);
	assert.equal(prs.size, 1);
	const bench = prs.get('bench press');
	assert.ok(bench);
	assert.equal(bench.exerciseName, 'Bench Press'); // first-seen spelling
	assert.equal(bench.heaviestWeightKg, 110);
	assert.equal(bench.heaviestWeightReps, 3);
});

test('computeExercisePrs: heaviest-weight tie broken by more reps', () => {
	const prs = computeExercisePrs([set('Squat', 3, 140), set('Squat', 6, 140)]);
	assert.equal(prs.get('squat')?.heaviestWeightKg, 140);
	assert.equal(prs.get('squat')?.heaviestWeightReps, 6);
});

test('computeExercisePrs: best single-set volume', () => {
	const prs = computeExercisePrs([
		set('Deadlift', 5, 100), // 500
		set('Deadlift', 3, 180), // 540
	]);
	assert.equal(prs.get('deadlift')?.bestVolumeKg, 540);
});

test('computeExercisePrs: best e1rm prefers the stronger estimate, not raw weight', () => {
	// 5×100 (e1rm 116.7) should beat 1×105 (e1rm 105).
	const prs = computeExercisePrs([set('OHP', 5, 100), set('OHP', 1, 105)]);
	assert.equal(prs.get('ohp')?.bestEst1RmKg, 116.7);
});

test('computeExercisePrs: blank exercise names are ignored', () => {
	const prs = computeExercisePrs([set('   ', 5, 100), set('', 5, 50)]);
	assert.equal(prs.size, 0);
});

test('computeExercisePrs: bodyweight set (no weight) yields no weight/volume/e1rm PR', () => {
	const prs = computeExercisePrs([set('Pull-up', 10, null)]);
	const pr = prs.get('pull-up');
	assert.ok(pr);
	assert.equal(pr.heaviestWeightKg, null);
	assert.equal(pr.bestVolumeKg, null);
	assert.equal(pr.bestEst1RmKg, null);
});

test('computeExercisePrs: numeric strings from jsonb/string columns are parsed', () => {
	const prs = computeExercisePrs([
		{ exercise_name: 'Row', reps: '8' as unknown as number, weight_kg: '60' as unknown as number },
	]);
	assert.equal(prs.get('row')?.heaviestWeightKg, 60);
	assert.equal(prs.get('row')?.bestVolumeKg, 480);
});

test('computeExercisePrs: a fractional-rep set produces matching volume and e1rm across platforms', () => {
	// reps 5.5 must feed BOTH the volume and the e1rm path unrounded, so the
	// two metrics agree with each other and with the Dart twin.
	const prs = computeExercisePrs([set('Bench', 5.5, 100)]);
	assert.equal(prs.get('bench')?.bestVolumeKg, 550);
	assert.equal(prs.get('bench')?.bestEst1RmKg, 118.3);
});

test('workoutPrs: first time an exercise is logged, every metric is a PR', () => {
	const prs = workoutPrs([], [set('Bench', 5, 100)]);
	assert.equal(prs.length, 1);
	assert.equal(prs[0].exerciseName, 'Bench');
	assert.deepEqual(prs[0].kinds.sort(), ['e1rm', 'volume', 'weight']);
});

test('workoutPrs: only the bettered metrics are reported', () => {
	const prior = [set('Bench', 5, 100)]; // weight 100, vol 500, e1rm 116.7
	// 1×110: heavier weight + higher e1rm (110) but LOWER volume (110 < 500).
	const prs = workoutPrs(prior, [set('Bench', 1, 110)]);
	assert.equal(prs.length, 1);
	assert.deepEqual(prs[0].kinds.sort(), ['weight']);
});

test('workoutPrs: no PR when the workout ties but does not beat prior', () => {
	const prior = [set('Squat', 5, 140)];
	const prs = workoutPrs(prior, [set('Squat', 5, 140)]);
	assert.deepEqual(prs, []);
});

test('workoutPrs: an unrelated exercise with no history is its own PR', () => {
	const prior = [set('Bench', 5, 100)];
	const prs = workoutPrs(prior, [set('Bench', 3, 90), set('Curl', 10, 20)]);
	// Bench 3×90 beats nothing; Curl is brand new.
	assert.equal(prs.length, 1);
	assert.equal(prs[0].exerciseName, 'Curl');
});

test('workoutPrs: case-insensitive history match prevents a false PR', () => {
	const prior = [set('Bench Press', 5, 100)];
	const prs = workoutPrs(prior, [set('bench press', 5, 95)]);
	assert.deepEqual(prs, []);
});

test('RunningPrTracker.judge matches workoutPrs walked over growing prior', () => {
	// A chronological sequence of workouts (each a set list). The running
	// tracker must produce, per workout, the SAME PR kinds as
	// workoutPrs(all-sets-before, this-workout) — the O(n) single pass can't
	// drift from the O(workouts×sets) reference.
	const workouts: GymSetLike[][] = [
		[set('Bench', 5, 100), set('Squat', 5, 140)], // both brand-new PRs
		[set('Bench', 5, 95)], // beats nothing
		[set('Bench', 3, 110), set('Curl', 10, 20)], // Bench weight+e1rm PR, Curl new
		[set('Squat', 1, 160)], // Squat weight+e1rm PR, not volume
		[set('bench press', 5, 200)], // different exercise key — its own PR
		[set('Bench', 5, 100)], // ties the original, no PR
	];
	const tracker = new RunningPrTracker();
	const prior: GymSetLike[] = [];
	for (const w of workouts) {
		const viaTracker = tracker.judge(w);
		const viaLoop = workoutPrs(prior, w);
		prior.push(...w);
		// Order-independent compare of the (exerciseName, sorted kinds) sets.
		const norm = (rs: typeof viaLoop) =>
			rs
				.map((r) => `${r.exerciseName}:${[...r.kinds].sort().join(',')}`)
				.sort();
		assert.deepEqual(norm(viaTracker), norm(viaLoop));
	}
});
