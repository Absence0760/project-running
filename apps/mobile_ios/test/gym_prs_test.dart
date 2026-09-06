import 'package:flutter_test/flutter_test.dart';

import '../lib/exercise_fold_table.dart';
import '../lib/gym_prs.dart';

GymSetLike _set(String name, num? reps, num? weightKg) =>
    GymSetLike(exerciseName: name, reps: reps, weightKg: weightKg);

void main() {
  group('estimatedOneRepMax', () {
    test('a true single reports the lifted weight', () {
      expect(estimatedOneRepMax(100, 1), 100);
    });

    test('Epley for multi-rep sets', () {
      expect((estimatedOneRepMax(100, 5) - 116.6667).abs() < 0.001, isTrue);
    });

    test('reps clamp past the accuracy ceiling', () {
      expect(estimatedOneRepMax(50, 30), estimatedOneRepMax(50, kE1rmMaxReps));
    });

    test('non-positive inputs return 0', () {
      expect(estimatedOneRepMax(0, 5), 0);
      expect(estimatedOneRepMax(100, 0), 0);
      expect(estimatedOneRepMax(-5, 5), 0);
    });

    test('fractional reps keep the fraction (not truncated to int)', () {
      // 100 × 5.5 → 100 · (1 + 5.5/30) = 118.333…, distinct from 100 × 5.
      expect((estimatedOneRepMax(100, 5.5) - 118.3333).abs() < 0.001, isTrue);
      expect(estimatedOneRepMax(100, 5.5), isNot(estimatedOneRepMax(100, 5)));
    });
  });

  group('normaliseExerciseName', () {
    test('case, trim, whitespace collapse', () {
      expect(normaliseExerciseName('  Bench  Press '), 'bench press');
      expect(normaliseExerciseName('bench press'), 'bench press');
    });
  });

  group('computeExercisePrs', () {
    test('groups case-insensitively and keeps first spelling', () {
      final prs = computeExercisePrs([
        _set('Bench Press', 5, 100),
        _set('bench press', 3, 110),
      ]);
      expect(prs.length, 1);
      final bench = prs['bench press']!;
      expect(bench.exerciseName, 'Bench Press');
      expect(bench.heaviestWeightKg, 110);
      expect(bench.heaviestWeightReps, 3);
    });

    test('heaviest-weight tie broken by more reps', () {
      final prs = computeExercisePrs([_set('Squat', 3, 140), _set('Squat', 6, 140)]);
      expect(prs['squat']!.heaviestWeightKg, 140);
      expect(prs['squat']!.heaviestWeightReps, 6);
    });

    test('best single-set volume', () {
      final prs = computeExercisePrs([
        _set('Deadlift', 5, 100),
        _set('Deadlift', 3, 180),
      ]);
      expect(prs['deadlift']!.bestVolumeKg, 540);
    });

    test('best e1rm prefers the stronger estimate, not raw weight', () {
      final prs = computeExercisePrs([_set('OHP', 5, 100), _set('OHP', 1, 105)]);
      expect(prs['ohp']!.bestEst1RmKg, 116.7);
    });

    test('blank exercise names are ignored', () {
      final prs = computeExercisePrs([_set('   ', 5, 100), _set('', 5, 50)]);
      expect(prs.length, 0);
    });

    test('bodyweight set (no weight) yields no weight/volume/e1rm PR', () {
      final prs = computeExercisePrs([_set('Pull-up', 10, null)]);
      final pr = prs['pull-up']!;
      expect(pr.heaviestWeightKg, isNull);
      expect(pr.bestVolumeKg, isNull);
      expect(pr.bestEst1RmKg, isNull);
    });

    test('numeric strings from string columns are parsed', () {
      final prs = computeExercisePrs([
        const GymSetLike(exerciseName: 'Row', reps: 8, weightKg: 60),
      ]);
      expect(prs['row']!.heaviestWeightKg, 60);
      expect(prs['row']!.bestVolumeKg, 480);
    });

    test('a fractional-rep set produces matching volume and e1rm across platforms', () {
      // reps 5.5 must feed BOTH the volume and the e1rm path unrounded, so the
      // two Dart metrics agree with each other and with the TS twin.
      final prs = computeExercisePrs([_set('Bench', 5.5, 100)]);
      expect(prs['bench']!.bestVolumeKg, 550);
      expect(prs['bench']!.bestEst1RmKg, 118.3);
    });
  });

  group('workoutPrs', () {
    test('first time an exercise is logged, every metric is a PR', () {
      final prs = workoutPrs([], [_set('Bench', 5, 100)]);
      expect(prs.length, 1);
      expect(prs[0].exerciseName, 'Bench');
      final kinds = prs[0].kinds.toList()..sort((a, b) => a.index.compareTo(b.index));
      expect(kinds, [PrKind.weight, PrKind.volume, PrKind.e1rm]);
    });

    test('only the bettered metrics are reported', () {
      final prior = [_set('Bench', 5, 100)];
      final prs = workoutPrs(prior, [_set('Bench', 1, 110)]);
      expect(prs.length, 1);
      expect(prs[0].kinds, [PrKind.weight]);
    });

    test('no PR when the workout ties but does not beat prior', () {
      final prior = [_set('Squat', 5, 140)];
      final prs = workoutPrs(prior, [_set('Squat', 5, 140)]);
      expect(prs, isEmpty);
    });

    test('an unrelated exercise with no history is its own PR', () {
      final prior = [_set('Bench', 5, 100)];
      final prs = workoutPrs(prior, [_set('Bench', 3, 90), _set('Curl', 10, 20)]);
      expect(prs.length, 1);
      expect(prs[0].exerciseName, 'Curl');
    });

    test('case-insensitive history match prevents a false PR', () {
      final prior = [_set('Bench Press', 5, 100)];
      final prs = workoutPrs(prior, [_set('bench press', 5, 95)]);
      expect(prs, isEmpty);
    });

    test('the result carries the grouping key, not a re-derivable display string', () {
      // The name carries BOTH collapses the naive fold misses, because the two
      // runtimes miss DIFFERENT ones and the intersection is empty: measured
      // over all 1,488 table entries, Dart 3.12 disagrees with the frozen table
      // at 465 code points and Node 24 (Unicode 17.0) at exactly U+0130, which
      // is in neither set the other misses. The internal whitespace run is the
      // witness that holds on both, so this test and its web mirror take the
      // same input.
      //
      // A caller that keys a lookup on `exerciseName.trim().toLowerCase()`
      // stores a key no block spelled `incline press` can ever hit, and the
      // exercise's chips vanish with no error anywhere (§ 1248). An ASCII
      // single-spaced name would pass either way.
      final prs = workoutPrs([], [_set('\u0130ncline  Press', 5, 100)]);
      expect(prs.length, 1);
      expect(prs[0].key, 'incline press');
      expect(prs[0].exerciseName, '\u0130ncline  Press');
      expect(prs[0].key, isNot(prs[0].exerciseName.trim().toLowerCase()));
      expect(prs[0].key, normaliseExerciseName('incline press'));
    });
  });

  group('distinctExerciseCount', () {
    test('spellings the canonical fold merges count once', () {
      // Each pair is one lift under two spellings that `trim().toLowerCase()`
      // keeps apart: an internal whitespace run, a non-breaking space, and a
      // code point the runtimes disagree about.
      expect(distinctExerciseCount(['Bench  Press', 'Bench Press']), 1);
      expect(distinctExerciseCount(['Bench\u00a0Press', 'bench press']), 1);
      expect(distinctExerciseCount(['\u0130ncline Press', 'incline press']), 1);
      expect(distinctExerciseCount(['Bench Press', 'Back Squat']), 2);
    });

    test('blank and whitespace-only names contribute nothing', () {
      // Matches computeExercisePrs, which drops a blank-named set outright — a
      // count that included it disagreed with every keyed surface.
      expect(distinctExerciseCount(['', '   ', '\u00a0', 'Bench Press']), 1);
      expect(distinctExerciseCount(<String>[]), 0);
    });
  });

  group('RunningPrTracker', () {
    test('judge matches workoutPrs walked over a growing prior', () {
      // The O(n) single-pass tracker must produce, per workout, the SAME PR
      // kinds as workoutPrs(all-sets-before, this-workout).
      final workouts = <List<GymSetLike>>[
        [_set('Bench', 5, 100), _set('Squat', 5, 140)],
        [_set('Bench', 5, 95)],
        [_set('Bench', 3, 110), _set('Curl', 10, 20)],
        [_set('Squat', 1, 160)],
        [_set('bench press', 5, 200)],
        [_set('Bench', 5, 100)],
      ];
      final tracker = RunningPrTracker();
      final prior = <GymSetLike>[];
      List<String> norm(List<WorkoutPrResult> rs) => rs
          .map((r) => '${r.exerciseName}:${(r.kinds.map((k) => k.name).toList()..sort()).join(',')}')
          .toList()
        ..sort();
      for (final w in workouts) {
        final viaTracker = tracker.judge(w);
        final viaLoop = workoutPrs(prior, w);
        prior.addAll(w);
        expect(norm(viaTracker), norm(viaLoop));
      }
    });
  });

  test('the whitespace class matches web, U+0085 included', () {
    // exercise_key is PERSISTED, so a name that normalises differently on the
    // two platforms buckets one exercise into two PRs. Dart's trim() strips
    // every Unicode White_Space code point (incl. NEL); JS's does not, so the
    // class is spelled out on both sides rather than left to the runtime.
    expect(normaliseExerciseName('Bench Press\u0085'), 'bench press');
    expect(normaliseExerciseName('\u00a0Bench\u2003Press\u2028'), 'bench press');
    expect(normaliseExerciseName('  Bench   press '), 'bench press');
  });

  test('the whitespace class folds what the SQL rail folds, and nothing more',
      () {
    // The key is derived on three rails and PERSISTED, so a name the server
    // buckets differently from the clients splits one exercise into two: the
    // local PR tracker says PR where gym_workout_summaries.is_pr says no.
    // Every case here disagreed before migration 20270623000001
    // (decisions § 790).
    //
    // btrim(text) strips U+0020 alone, so any other edge whitespace survived
    // the trim and the \s+ pass then turned it into a leading/trailing SPACE.
    expect(normaliseExerciseName('\u0009Bench Press'), 'bench press');
    expect(normaliseExerciseName('Bench Press\u000a'), 'bench press');
    // Postgres \s past ASCII is the locale provider's opinion, not Unicode's:
    // the ICU provider folds NBSP and the libc one does not. Neither folds
    // U+FEFF, which is invisible and must not split a bucket.
    expect(normaliseExerciseName('Bench\u00a0Press'), 'bench press');
    expect(normaliseExerciseName('Bench\ufeffPress'), 'bench press');
    // A name that is nothing but whitespace is not an exercise. The server's
    // btrim(coalesce(name,'')) <> '' filter kept a lone tab as an exercise
    // named " "; both clients always dropped it.
    expect(normaliseExerciseName('\u0009\u00a0'), '');
    // The ICU provider also folds U+001C-U+001F. Those are control characters,
    // not spaces — the clients must NOT start folding them to match.
    expect(normaliseExerciseName('Bench\u001cPress'), 'bench\u001cpress');
  });

  test('the case fold matches what the SQL rail case-folds', () {
    // No rail reaches for its own runtime's lowercase any more: all three fold
    // through the frozen table (decisions § 1175). These are the cases that
    // were reachable in a Latin or Greek exercise name while they did.
    //
    // U+0130's FULL lowercase is 'i' + U+0307 (what JS and ICU return); its
    // SIMPLE one is a bare 'i', which is the mapping the table carries, so a
    // key written here satisfies the CHECK on
    // gym_routine_exercises.exercise_key.
    expect(normaliseExerciseName('\u0130tme'), 'itme');
    expect(normaliseExerciseName('\u0130TME'), 'itme');
    // Final sigma: ICU and JS apply Unicode's contextual Final_Sigma rule and
    // this rail and libc never do, so an all-caps Greek spelling has to be
    // folded onto U+03C3 or it never meets its own lower-case one.
    expect(normaliseExerciseName('\u039f\u0394\u039f\u03a3'),
        '\u03bf\u03b4\u03bf\u03c3');
    expect(normaliseExerciseName('\u03bf\u03b4\u03bf\u03c2'),
        '\u03bf\u03b4\u03bf\u03c3');
    // An ASCII capital I stays an i. Under a Turkish-locale database the old
    // server derivation folded it to U+0131 and split every "Incline Press".
    expect(normaliseExerciseName('INCLINE Press'), 'incline press');
    // And the accented-capital merge every non-English lifter depends on is
    // intact — an ASCII-only fold would have split these two.
    expect(normaliseExerciseName('\u00dcBERZ\u00dcGE'), '\u00fcberz\u00fcge');
    expect(normaliseExerciseName('\u00fcberz\u00fcge'), '\u00fcberz\u00fcge');
  });

  test('the frozen fold table is 1:1, ascending and unchained', () {
    // Every rail applies the table in ONE pass — Postgres translate() and both
    // clients' per-code-point lookup — so these are the claims that make the
    // three answers the same answer rather than three passes that happen to
    // agree today (decisions § 1175).
    expect(kExerciseFoldKeys.length, kExerciseFoldValues.length);
    final keys = kExerciseFoldKeys.toSet();
    expect(keys.length, kExerciseFoldKeys.length);
    for (var i = 1; i < kExerciseFoldKeys.length; i++) {
      expect(kExerciseFoldKeys[i - 1] < kExerciseFoldKeys[i], isTrue);
    }
    for (var i = 0; i < kExerciseFoldKeys.length; i++) {
      expect(kExerciseFoldValues[i], isNot(kExerciseFoldKeys[i]));
      // A value the table also folds would make fold(fold(x)) differ from
      // fold(x), and the CHECK re-derives the key from the name on every write.
      expect(keys.contains(kExerciseFoldValues[i]), isFalse);
    }
    // The SQL rail takes a 26-pair fast path for an all-ASCII name, which is
    // only answer-identical to the full table while its ASCII half is exactly
    // this.
    final ascii = <int, int>{
      for (var i = 0; i < kExerciseFoldKeys.length; i++)
        if (kExerciseFoldKeys[i] < 0x80) kExerciseFoldKeys[i]: kExerciseFoldValues[i],
    };
    expect(ascii, {for (var i = 0; i < 26; i++) 0x41 + i: 0x61 + i});
  });

  test('the fold is the table, not this runtime', () {
    // The point of the table. Dart's own toLowerCase() is simple case mapping
    // from an older Unicode revision and leaves every one of these alone, so
    // before the table each was a name this rail could not persist without a
    // 23514 from a CHECK web and the server both agreed on. One from each
    // family the 465-code-point gap covered: Cherokee (Unicode 8.0), the Latin
    // Extended-D additions, Garay and Medefaidrin in the supplementary planes.
    for (final pair in <List<String>>[
      ['\u13a0', '\uab70'],
      ['\ua7cb', '\u0264'],
      ['\u{10d50}', '\u{10d70}'],
      ['\u{16e40}', '\u{16e60}'],
    ]) {
      expect(pair[0].toLowerCase(), pair[0],
          reason: 'this runtime would have left ${pair[0]} alone');
      expect(normaliseExerciseName(pair[0]), pair[1]);
    }
    expect(kExerciseFoldUnicodeVersion.isNotEmpty, isTrue);
  });

  test('the fold walks code points, not code units', () {
    // 307 of the 1,488 entries are outside the BMP. A code-unit walk would fold
    // each half of the surrogate pair separately, match neither, and leave the
    // name uppercase — a second bucket for the same lift.
    const deseret = '\u{10400}\u{10401}';
    expect(normaliseExerciseName(deseret), '\u{10428}\u{10429}');
    expect(normaliseExerciseName('Bench $deseret Press'),
        'bench \u{10428}\u{10429} press');
  });
}
