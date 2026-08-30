import 'package:flutter_test/flutter_test.dart';
import '../lib/numeric_limits.dart';
import '../lib/preferences.dart';

// That each bound EQUALS the CHECK it names is proved by
// `scripts/check_shared_constants.mjs`, which reads the migrations. What is
// left to pin here is the shape of the registry and the grading around it.

void main() {
  test('every limit names the column it is enforced by', () {
    expect(kNumericLimits.keys.toSet(), kNumericLimitColumns.keys.toSet());
    for (final qualified in kNumericLimitColumns.values) {
      expect(RegExp(r'^[a-z_]+\.[a-z_]+$').hasMatch(qualified), isTrue);
    }
  });

  test('a value inside the bound, and each edge, is ok', () {
    final limit = kNumericLimits['checkpointBodyWeightKg']!;
    expect(checkNumericLimit(limit, 70), NumericLimitVerdict.ok);
    expect(checkNumericLimit(limit, limit.min), NumericLimitVerdict.ok);
    expect(checkNumericLimit(limit, limit.max), NumericLimitVerdict.ok);
  });

  test('a value outside the bound says WHICH side it fell off', () {
    final limit = kNumericLimits['checkpointBodyWeightKg']!;
    expect(checkNumericLimit(limit, 19.99), NumericLimitVerdict.below);
    expect(checkNumericLimit(limit, 400.01), NumericLimitVerdict.above);
  });

  // The defect this registry exists for: 600 kg, and the same weight typed as
  // 1200 lb, both reached the column and came back as a raw 23514.
  test('the body-metrics ceiling rejects 600 kg and the pounds that convert past it', () {
    final limit = kNumericLimits['bodyMetricsWeightKg']!;
    expect(checkNumericLimit(limit, 600), NumericLimitVerdict.above);
    expect(checkNumericLimit(limit, WeightFormat.toKg(1200, WeightUnit.lbs)), NumericLimitVerdict.above);
    expect(checkNumericLimit(limit, 90), NumericLimitVerdict.ok);
  });

  // A bare `> 0` guard against a `> 0` CHECK admitted nothing extra, but a
  // form offering "0" offers exactly the one value the CHECK rejects.
  test('zero is below the bound of a column whose CHECK is exclusive', () {
    expect(checkNumericLimit(kNumericLimits['bodyMetricsWeightKg']!, 0), NumericLimitVerdict.below);
    expect(checkNumericLimit(kNumericLimits['profileHeightCm']!, 0), NumericLimitVerdict.below);
    expect(checkNumericLimit(kNumericLimits['gymSetRpe']!, 0), NumericLimitVerdict.ok);
  });

  test('a non-finite value is invalid rather than silently in range', () {
    expect(checkNumericLimit(kNumericLimits['gymSetRpe']!, double.nan), NumericLimitVerdict.invalid);
    expect(checkNumericLimit(kNumericLimits['gymSetRpe']!, double.infinity), NumericLimitVerdict.invalid);
  });

  test('a bound restated in another unit rounds inward, so the shown number is itself legal', () {
    final limit = kNumericLimits['checkpointBodyWeightKg']!;
    final inLbs = numericBoundsIn(limit, toDisplay: (kg) => WeightFormat.toDisplay(kg, WeightUnit.lbs));
    // 20 kg is 44.0924 lbs and 400 kg is 881.849 lbs.
    expect(inLbs.min, 44.1);
    expect(inLbs.max, 881.8);
    expect(checkNumericLimit(limit, WeightFormat.toKg(inLbs.min, WeightUnit.lbs)), NumericLimitVerdict.ok);
    expect(checkNumericLimit(limit, WeightFormat.toKg(inLbs.max, WeightUnit.lbs)), NumericLimitVerdict.ok);
  });

  test('with no conversion the display bound is the bound', () {
    final shown = numericBoundsIn(kNumericLimits['routineRestS']!);
    expect(shown.min, 0);
    expect(shown.max, 3600);
  });

  // The narrowing rule: a field may show something tighter than the column,
  // never looser.
  test('the plausible human body-weight range sits inside the column bound', () {
    final limit = kNumericLimits['bodyMetricsWeightKg']!;
    expect(checkNumericLimit(limit, kBodyWeightRangeKg.min), NumericLimitVerdict.ok);
    expect(checkNumericLimit(limit, kBodyWeightRangeKg.max), NumericLimitVerdict.ok);
  });
}
