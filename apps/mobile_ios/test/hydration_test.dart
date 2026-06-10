import 'package:flutter_test/flutter_test.dart';

import '../lib/hydration.dart';

void main() {
  test('hydrationTargetMl: bodyweight baseline at 35 ml/kg, rounded to 50', () {
    // 70 kg → 2450 ml, already a multiple of 50.
    expect(hydrationTargetMl(70, 0), 70 * baselineMlPerKg);
    // 68 kg → 2380 → rounds to 2400.
    expect(hydrationTargetMl(68, 0), 2400);
  });

  test('hydrationTargetMl: missing/non-physical bodyweight falls back to flat baseline', () {
    for (final w in <num?>[null, 0, -5]) {
      expect(hydrationTargetMl(w, 0), defaultBaselineMl);
    }
  });

  test('hydrationTargetMl: exercise minutes raise the goal (~480 ml/hr)', () {
    // 70 kg baseline 2450 + 60 min × 8 = 2930 → rounds to 2950.
    expect(hydrationTargetMl(70, 60) > hydrationTargetMl(70, 0), true);
    expect(hydrationTargetMl(70, 60), 2950);
    // Exercise add applies on the flat baseline too: 2000 + 240 = 2240 → 2250.
    expect(hydrationTargetMl(null, 30), 2250);
  });

  test('hydrationTargetMl: missing/zero exercise adds nothing', () {
    for (final e in <num?>[null, 0, -10]) {
      expect(hydrationTargetMl(70, e), 2450);
    }
  });

  test('hydrationBudget: under goal reports remaining, not reached', () {
    final b = hydrationBudget(1000, 2450);
    expect(b.remainingMl, 1450);
    expect(b.reached, false);
    expect((b.fraction - 1000 / 2450).abs() < 1e-9, true);
  });

  test('hydrationBudget: reaching the goal flags reached, remaining floors at 0', () {
    final b = hydrationBudget(2450, 2450);
    expect(b.remainingMl, 0);
    expect(b.reached, true);
    expect(b.fraction, 1);
  });

  test('hydrationBudget: over the goal stays reached, fraction clamps to 1', () {
    final b = hydrationBudget(3000, 2450);
    expect(b.remainingMl, 0);
    expect(b.reached, true);
    expect(b.fraction, 1);
  });

  test('hydrationBudget: a zero target never reads as reached or divides', () {
    final b = hydrationBudget(0, 0);
    expect(b.reached, false);
    expect(b.fraction, 0);
    expect(b.remainingMl, 0);
  });

  test('hydrationBudget: rounds and floors negative consumed', () {
    final b = hydrationBudget(-50, 2000);
    expect(b.consumedMl, 0);
    expect(b.remainingMl, 2000);
  });
}
