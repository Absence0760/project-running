import 'package:flutter_test/flutter_test.dart';

import '../lib/nutrition_targets.dart';

BodyMetricsInput baseWith({
  double? weightKg = 70,
  double? heightCm = 178,
  int? ageYears = 35,
  String? sex = 'male',
  String activityLevel = 'moderate',
  String goal = 'maintain',
}) {
  return BodyMetricsInput(
    weightKg: weightKg,
    heightCm: heightCm,
    ageYears: ageYears,
    sex: sex,
    activityLevel: activityLevel,
    goal: goal,
  );
}

void main() {
  test('mifflinStJeorBmr — male offset is +5', () {
    // 10*70 + 6.25*178 - 5*35 + 5 = 1642.5
    expect(mifflinStJeorBmr(70, 178, 35, 'male'), 1642.5);
  });

  test('mifflinStJeorBmr — female offset is -161', () {
    expect(mifflinStJeorBmr(70, 178, 35, 'female'), 1642.5 - 5 - 161);
  });

  test('mifflinStJeorBmr — neutral offset (-78) for nonbinary / withheld / unknown',
      () {
    final neutral = 10 * 70 + 6.25 * 178 - 5 * 35 - 78;
    expect(mifflinStJeorBmr(70, 178, 35, 'nonbinary'), neutral);
    expect(mifflinStJeorBmr(70, 178, 35, 'prefer_not_to_say'), neutral);
    expect(mifflinStJeorBmr(70, 178, 35, null), neutral);
  });

  test('computeNutritionTargets — applies the moderate activity factor', () {
    final t = computeNutritionTargets(baseWith())!;
    // 1642.5 * 1.55 = 2545.875 -> round/10 = 2550
    expect(t.calories, 2550);
  });

  test('computeNutritionTargets — protein is 1.8 g/kg, fat is 30% of kcal', () {
    final t = computeNutritionTargets(baseWith())!;
    expect(t.proteinG, (1.8 * 70).round()); // 126
    expect(t.fatG, ((0.3 * 2550) / 9).round()); // 85
  });

  test('computeNutritionTargets — carbs fill the remaining calorie budget', () {
    final t = computeNutritionTargets(baseWith())!;
    final remaining = 2550 - t.proteinG * 4 - t.fatG * 9;
    expect(t.carbsG, (remaining / 4).round());
  });

  test('computeNutritionTargets — goal delta lowers/raises calories', () {
    final lose = computeNutritionTargets(baseWith(goal: 'lose'))!;
    final gain = computeNutritionTargets(baseWith(goal: 'gain'))!;
    expect(lose.calories, 2550 + goalKcalDelta['lose']!.round());
    expect(gain.calories, 2550 + goalKcalDelta['gain']!.round());
  });

  test('computeNutritionTargets — sedentary < very_active for the same body',
      () {
    final sed = computeNutritionTargets(baseWith(activityLevel: 'sedentary'))!;
    final va = computeNutritionTargets(baseWith(activityLevel: 'very_active'))!;
    expect(va.calories > sed.calories, true);
  });

  test('computeNutritionTargets — calorie floor protects against a too-low default',
      () {
    final t = computeNutritionTargets(BodyMetricsInput(
      weightKg: 40,
      heightCm: 150,
      ageYears: 80,
      sex: 'female',
      activityLevel: 'sedentary',
      goal: 'lose',
    ))!;
    expect(t.calories, minCalorieTarget);
  });

  test('computeNutritionTargets — null on missing or non-physical metrics', () {
    expect(computeNutritionTargets(baseWith(weightKg: null)), null);
    expect(computeNutritionTargets(baseWith(heightCm: null)), null);
    expect(computeNutritionTargets(baseWith(ageYears: null)), null);
    expect(computeNutritionTargets(baseWith(weightKg: 0)), null);
    expect(computeNutritionTargets(baseWith(weightKg: 600)), null);
    expect(computeNutritionTargets(baseWith(heightCm: 400)), null);
  });

  test('ageFromDob — whole-year age, decremented before the birthday', () {
    final now = DateTime.utc(2026, 6, 4).millisecondsSinceEpoch;
    expect(ageFromDob('1990-06-04', now), 36); // birthday today
    expect(ageFromDob('1990-06-05', now), 35); // birthday tomorrow
    expect(ageFromDob('1990-06-03', now), 36); // birthday yesterday
  });

  test('ageFromDob — null on missing / malformed / out-of-range', () {
    final now = DateTime.utc(2026, 6, 4).millisecondsSinceEpoch;
    expect(ageFromDob(null, now), null);
    expect(ageFromDob('', now), null);
    expect(ageFromDob('not-a-date', now), null);
    expect(ageFromDob('1850-01-01', now), null); // > 120
  });

  test('activityLevels is ordered least -> most active with rising factors',
      () {
    for (var i = 1; i < activityLevels.length; i++) {
      expect(activityLevels[i].factor > activityLevels[i - 1].factor, true);
    }
  });
}
