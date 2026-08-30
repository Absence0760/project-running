import 'package:flutter_test/flutter_test.dart';

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

  test('the whitespace class matches the web and SQL twins', () {
    // exercise_key is PERSISTED and three rails derive it, so a name that
    // normalises differently on any of them buckets one exercise into two.
    const members = <int>[
      0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0x85, 0xa0, 0x1680, 0x2000, 0x2001,
      0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
      0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff,
    ];
    for (final cp in members) {
      final c = String.fromCharCode(cp);
      final hex = cp.toRadixString(16);
      expect(normaliseExerciseName('Bench${c}Press'), 'bench press',
          reason: 'inner U+$hex');
      // The edge cases are the ones the SQL rail got wrong: btrim(text) with
      // no second argument strips ONLY U+0020, so every other member survived
      // the trim and the collapse then turned it into a leading/trailing space.
      expect(normaliseExerciseName('${c}Bench Press'), 'bench press',
          reason: 'leading U+$hex');
      expect(normaliseExerciseName('Bench Press$c'), 'bench press',
          reason: 'trailing U+$hex');
    }
    expect(normaliseExerciseName('  Bench   press '), 'bench press');
    expect(normaliseExerciseName('\t\n'), '');
  });

  test('non-whitespace format characters are left alone', () {
    // U+200B ZWSP and U+180E are NOT whitespace in any of the three rails, and
    // widening the class on one platform alone would re-key every name holding
    // one. Pinned so the class cannot quietly grow.
    expect(normaliseExerciseName('Bench\u200bPress'), 'bench\u200bpress');
    expect(normaliseExerciseName('Bench\u180ePress'), 'bench\u180epress');
  });

  test('the case folds no runtime agrees on are applied by hand', () {
    // JS full-lowercases U+0130 to `i` + U+0307 where Dart and libc's towlower
    // both yield a bare `i`. Folding it by hand is what makes the stored key
    // identical on all three rails; the four titlecase digraphs are the same
    // shape. decisions.md § 790.
    expect(normaliseExerciseName('\u0130ncline Press'), 'incline press');
    expect(normaliseExerciseName('\u0130NCLINE PRESS'), 'incline press');
    expect(normaliseExerciseName('\u01c5em'), '\u01c6em');
    expect(normaliseExerciseName('\u01c8'), '\u01c9');
    expect(normaliseExerciseName('\u01cb'), '\u01cc');
    expect(normaliseExerciseName('\u01f2'), '\u01f3');
    // Ordinary folding is still the runtime's, and all three agree on it.
    expect(normaliseExerciseName('\u00c9l\u00e9vation'), '\u00e9l\u00e9vation');
  });
}
