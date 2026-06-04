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
}
