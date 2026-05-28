import 'package:flutter_test/flutter_test.dart';

import '../lib/calories.dart';

void main() {
  // Persona-hunt Round 3 finding Woman #5. Dart twin of
  // `apps/web/src/lib/calories.test.ts` — keep in lockstep.

  group('estimateRunCalories — defaults + weight scaling', () {
    test('no weight → uses kDefaultBodyWeightKg (70)', () {
      // 5 km × 70 kg × 1 (run) = 350 kcal
      expect(estimateRunCalories(distanceM: 5000), 350);
    });

    test('explicit weight scales output proportionally', () {
      final a = estimateRunCalories(distanceM: 5000, weightKg: 50);
      final b = estimateRunCalories(distanceM: 5000, weightKg: 100);
      expect(a, 250);
      expect(b, 500);
      expect(b / a, 2);
    });

    test('null / zero / negative weight falls back to default', () {
      final ref = estimateRunCalories(distanceM: 5000);
      expect(estimateRunCalories(distanceM: 5000, weightKg: null), ref);
      expect(estimateRunCalories(distanceM: 5000, weightKg: 0), ref);
      expect(estimateRunCalories(distanceM: 5000, weightKg: -10), ref);
    });
  });

  group('estimateRunCalories — activity coefficient', () {
    test('activity coefficient scales output', () {
      final run = estimateRunCalories(
        distanceM: 10000,
        weightKg: 70,
        activityKcalPerKgPerKm: kActivityKcalPerKgPerKm['run'],
      );
      final walk = estimateRunCalories(
        distanceM: 10000,
        weightKg: 70,
        activityKcalPerKgPerKm: kActivityKcalPerKgPerKm['walk'],
      );
      expect(run, 700);
      expect(walk, 350);
    });

    test('null / zero activity coefficient falls back to run', () {
      final explicit = estimateRunCalories(
        distanceM: 5000,
        weightKg: 70,
        activityKcalPerKgPerKm: kActivityKcalPerKgPerKm['run'],
      );
      expect(
        estimateRunCalories(
            distanceM: 5000, weightKg: 70, activityKcalPerKgPerKm: null),
        explicit,
      );
      expect(
        estimateRunCalories(
            distanceM: 5000, weightKg: 70, activityKcalPerKgPerKm: 0),
        explicit,
      );
    });
  });

  group('estimateRunCalories — gender calibration', () {
    test('omitting gender returns the unmodified (male-curve) value', () {
      final noGender = estimateRunCalories(distanceM: 5000, weightKg: 70);
      final explicitMale = estimateRunCalories(
          distanceM: 5000, weightKg: 70, gender: 'male');
      final explicitNull = estimateRunCalories(
          distanceM: 5000, weightKg: 70, gender: null);
      expect(noGender, 350);
      expect(explicitMale, noGender);
      expect(explicitNull, noGender);
    });

    test('female calibration is ~5% lower than the male curve', () {
      final male = estimateRunCalories(distanceM: 10000, weightKg: 70);
      final female = estimateRunCalories(
          distanceM: 10000, weightKg: 70, gender: 'female');
      expect(female < male, isTrue,
          reason: 'female ($female) must be < male ($male)');
      final ratio = female / male;
      expect(ratio > 0.94 && ratio < 0.96, isTrue,
          reason: 'female / male ratio out of expected band: $ratio');
    });

    test('nonbinary falls back to the unmodified curve', () {
      final male = estimateRunCalories(distanceM: 5000, weightKg: 70);
      final nb = estimateRunCalories(
          distanceM: 5000, weightKg: 70, gender: 'nonbinary');
      expect(nb, male);
    });
  });

  group('estimateRunCalories — edge cases', () {
    test('zero distance → 0 kcal', () {
      expect(estimateRunCalories(distanceM: 0, weightKg: 70), 0);
    });

    test('negative distance is clamped to 0 (not a crash)', () {
      expect(estimateRunCalories(distanceM: -5000, weightKg: 70), 0);
    });

    test('kDefaultBodyWeightKg is 70', () {
      expect(kDefaultBodyWeightKg, 70);
    });
  });
}
