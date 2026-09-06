import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	estimatedOneRepMax,
	normaliseExerciseName,
	computeExercisePrs,
	distinctExerciseCount,
	workoutPrs,
	RunningPrTracker,
	kE1rmMaxReps,
	type GymSetLike,
} from './gym_prs';
import {
	EXERCISE_FOLD_KEYS,
	EXERCISE_FOLD_VALUES,
	EXERCISE_FOLD_UNICODE_VERSION,
} from './exercise_fold_table';

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

test('workoutPrs: the result carries the grouping key, not a re-derivable display string', () => {
	// The name carries BOTH collapses the naive fold misses, because the two
	// runtimes miss DIFFERENT ones and the intersection is empty: measured over
	// all 1,488 table entries, Node 24 (Unicode 17.0) disagrees with the frozen
	// table at exactly U+0130 and Dart 3.12 disagrees at 465 others, none of
	// them U+0130. The internal whitespace run is the witness that holds on
	// both, so this test and its Dart mirror take the same input.
	//
	// A caller that keys a lookup on `exerciseName.trim().toLowerCase()` stores
	// a key no block spelled `incline press` can ever hit, and the exercise's
	// chips vanish with no error anywhere (§ 1248). An ASCII single-spaced name
	// would pass either way.
	const prs = workoutPrs([], [set('\u0130ncline  Press', 5, 100)]);
	assert.equal(prs.length, 1);
	assert.equal(prs[0].key, 'incline press');
	assert.equal(prs[0].exerciseName, '\u0130ncline  Press');
	assert.notEqual(prs[0].key, prs[0].exerciseName.trim().toLowerCase());
	assert.equal(prs[0].key, normaliseExerciseName('incline press'));
});

test('distinctExerciseCount: spellings the canonical fold merges count once', () => {
	// Each pair is one lift under two spellings that `trim().toLowerCase()`
	// keeps apart: an internal whitespace run, a non-breaking space, and a
	// code point the runtimes disagree about.
	assert.equal(distinctExerciseCount(['Bench  Press', 'Bench Press']), 1);
	assert.equal(distinctExerciseCount(['Bench\u00a0Press', 'bench press']), 1);
	assert.equal(distinctExerciseCount(['\u0130ncline Press', 'incline press']), 1);
	assert.equal(distinctExerciseCount(['Bench Press', 'Back Squat']), 2);
});

test('distinctExerciseCount: blank and whitespace-only names contribute nothing', () => {
	// Matches computeExercisePrs, which drops a blank-named set outright — a
	// count that included it disagreed with every keyed surface.
	assert.equal(distinctExerciseCount(['', '   ', '\u00a0', 'Bench Press']), 1);
	assert.equal(distinctExerciseCount([]), 0);
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

test('normaliseExerciseName folds the same whitespace class as the Dart twin', () => {
	// exercise_key is PERSISTED, so a name that normalises differently on the
	// two platforms buckets one exercise into two PRs. Dart's trim() strips
	// every Unicode White_Space code point (incl. U+0085 NEL) and JS's does
	// not, so the class is spelled out on both sides.
	assert.equal(normaliseExerciseName('Bench Press\u0085'), 'bench press');
	assert.equal(normaliseExerciseName('\u00a0Bench\u2003Press\u2028'), 'bench press');
	assert.equal(normaliseExerciseName('  Bench   press '), 'bench press');
});

test('normaliseExerciseName folds what the SQL rail folds, and nothing more', () => {
	// The key is derived on three rails and PERSISTED, so a name the server
	// buckets differently from the clients splits one exercise into two: the
	// local PR tracker says PR where gym_workout_summaries.is_pr says no.
	// Every case here disagreed before migration 20270623000001
	// (decisions § 790).
	//
	// btrim(text) strips U+0020 alone, so any other edge whitespace survived
	// the trim and the \s+ pass then turned it into a leading/trailing SPACE.
	assert.equal(normaliseExerciseName('\u0009Bench Press'), 'bench press');
	assert.equal(normaliseExerciseName('Bench Press\u000a'), 'bench press');
	// Postgres \s past ASCII is the locale provider's opinion, not Unicode's:
	// the ICU provider folds NBSP and the libc one does not. Neither folds
	// U+FEFF, which is invisible and must not split a bucket.
	assert.equal(normaliseExerciseName('Bench\u00a0Press'), 'bench press');
	assert.equal(normaliseExerciseName('Bench\ufeffPress'), 'bench press');
	// A name that is nothing but whitespace is not an exercise. The server's
	// btrim(coalesce(name,'')) <> '' filter kept a lone tab as an exercise
	// named " "; both clients always dropped it.
	assert.equal(normaliseExerciseName('\u0009\u00a0'), '');
	// The ICU provider also folds U+001C-U+001F. Those are control characters,
	// not spaces — the clients must NOT start folding them to match.
	assert.equal(normaliseExerciseName('Bench\u001cPress'), 'bench\u001cpress');
});

test('normaliseExerciseName case-folds what the SQL rail case-folds', () => {
	// No rail reaches for its own runtime's lowercase any more: all three fold
	// through the frozen table (decisions § 1175). These are the cases that
	// were reachable in a Latin or Greek exercise name while they did.
	//
	// U+0130's FULL lowercase is 'i' + U+0307 (what JS and ICU return); its
	// SIMPLE one is a bare 'i', which is the mapping the table carries, so a
	// mobile-written exercise_key for this name satisfies the CHECK on
	// gym_routine_exercises.
	assert.equal(normaliseExerciseName('\u0130tme'), 'itme');
	assert.equal(normaliseExerciseName('\u0130TME'), 'itme');
	// Final sigma: ICU and JS apply Unicode's contextual Final_Sigma rule and
	// Dart and libc never do, so an all-caps Greek spelling has to be folded
	// onto U+03C3 or it never meets its own lower-case one.
	assert.equal(normaliseExerciseName('\u039f\u0394\u039f\u03a3'), '\u03bf\u03b4\u03bf\u03c3');
	assert.equal(normaliseExerciseName('\u03bf\u03b4\u03bf\u03c2'), '\u03bf\u03b4\u03bf\u03c3');
	// An ASCII capital I stays an i. Under a Turkish-locale database the old
	// server derivation folded it to U+0131 and split every "Incline Press".
	assert.equal(normaliseExerciseName('INCLINE Press'), 'incline press');
	// And the accented-capital merge every non-English lifter depends on is
	// intact — an ASCII-only fold would have split these two.
	assert.equal(normaliseExerciseName('\u00dcBERZ\u00dcGE'), '\u00fcberz\u00fcge');
	assert.equal(normaliseExerciseName('\u00fcberz\u00fcge'), '\u00fcberz\u00fcge');
});

test('the frozen fold table is 1:1, ascending and unchained', () => {
	// Every rail applies the table in ONE pass — Postgres translate() and both
	// clients' per-code-point lookup — so these are the claims that make the
	// three answers the same answer rather than three passes that happen to
	// agree today (decisions § 1175).
	assert.equal(EXERCISE_FOLD_KEYS.length, EXERCISE_FOLD_VALUES.length);
	const keys = new Set(EXERCISE_FOLD_KEYS);
	assert.equal(keys.size, EXERCISE_FOLD_KEYS.length);
	for (let i = 1; i < EXERCISE_FOLD_KEYS.length; i++) {
		assert.ok(EXERCISE_FOLD_KEYS[i - 1] < EXERCISE_FOLD_KEYS[i]);
	}
	for (let i = 0; i < EXERCISE_FOLD_KEYS.length; i++) {
		assert.notEqual(EXERCISE_FOLD_VALUES[i], EXERCISE_FOLD_KEYS[i]);
		// A value the table also folds would make fold(fold(x)) differ from
		// fold(x), and the CHECK re-derives the key from the name on every write.
		assert.ok(!keys.has(EXERCISE_FOLD_VALUES[i]));
	}
	// The SQL rail takes a 26-pair fast path for an all-ASCII name, which is
	// only answer-identical to the full table while its ASCII half is exactly
	// this.
	const ascii = EXERCISE_FOLD_KEYS.map((cp, i) => [cp, EXERCISE_FOLD_VALUES[i]] as const).filter(
		([cp]) => cp < 0x80,
	);
	assert.deepEqual(
		ascii,
		Array.from({ length: 26 }, (_, i) => [0x41 + i, 0x61 + i]),
	);
});

test('the frozen fold table is the simple lowercase mapping of the version it names', (t) => {
	// The table is FROZEN, so a newer Node folding more letters is not drift —
	// it is the next migration's work. This checks the table against the data it
	// was rendered from only when the two are the same version, and says so
	// rather than passing silently when they are not.
	if (process.versions.unicode !== EXERCISE_FOLD_UNICODE_VERSION) {
		t.skip(
			`this Node carries Unicode ${process.versions.unicode}, the table is frozen at ${EXERCISE_FOLD_UNICODE_VERSION} — the cross-check needs the two to match`,
		);
		return;
	}
	const table = new Map(EXERCISE_FOLD_KEYS.map((cp, i) => [cp, EXERCISE_FOLD_VALUES[i]]));
	for (let cp = 0; cp <= 0x10ffff; cp++) {
		if (cp >= 0xd800 && cp <= 0xdfff) continue;
		const source = String.fromCodePoint(cp);
		const lowered = source.toLowerCase();
		// U+0130 is the only code point whose UNCONDITIONAL full lowercase is
		// longer than one code point; the table takes its simple mapping.
		const expected =
			lowered === source ? undefined : cp === 0x0130 ? 0x0069 : lowered.codePointAt(0);
		assert.equal(
			table.get(cp),
			expected,
			`U+${cp.toString(16).toUpperCase()} disagrees with this build's simple lowercase`,
		);
		if (lowered !== source && cp !== 0x0130) assert.equal([...lowered].length, 1);
	}
});

test('normaliseExerciseName folds code points the runtimes disagreed about', () => {
	// One from each family the 465-code-point web-to-mobile gap covered:
	// Cherokee (Unicode 8.0), the Latin Extended-D additions, Garay and
	// Medefaidrin in the supplementary planes. Dart's own toLowerCase leaves
	// every one of them alone, so before the table these were names the phone
	// could not persist without a 23514 (decisions § 1175).
	assert.equal(normaliseExerciseName('\u13a0'), '\uab70');
	assert.equal(normaliseExerciseName('\ua7cb'), '\u0264');
	assert.equal(normaliseExerciseName('\u{10d50}'), '\u{10d70}');
	assert.equal(normaliseExerciseName('\u{16e40}'), '\u{16e60}');
});

test('normaliseExerciseName folds by code point, not by code unit', () => {
	// 307 of the 1,488 entries are outside the BMP. A code-unit walk would fold
	// each half of the surrogate pair separately, match neither, and leave the
	// name uppercase — a second bucket for the same lift.
	const deseret = '\u{10400}\u{10401}';
	assert.equal(normaliseExerciseName(deseret), '\u{10428}\u{10429}');
	assert.equal(normaliseExerciseName(`Bench ${deseret} Press`), `bench \u{10428}\u{10429} press`);
});
