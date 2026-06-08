import 'package:flutter_test/flutter_test.dart';

import '../lib/gear_wear.dart';

void main() {
  test('gearWear: no target -> untracked, null fraction', () {
    expect(gearWear(500000, null).status, GearWearStatus.untracked);
    expect(gearWear(500000, null).fraction, isNull);
    expect(gearWear(500000, 0).status, GearWearStatus.untracked);
    expect(gearWear(500000, 0).fraction, isNull);
  });

  test('gearWear: well within target -> ok', () {
    final w = gearWear(300000, 800000); // 37.5%
    expect(w.status, GearWearStatus.ok);
    expect((w.fraction ?? 0) - 0.375, lessThan(1e-9));
  });

  test('gearWear: at the due threshold -> due', () {
    final w = gearWear((gearWearDueFraction * 800000).round(), 800000);
    expect(w.status, GearWearStatus.due);
  });

  test('gearWear: just below the due threshold -> ok', () {
    final w = gearWear(((gearWearDueFraction - 0.01) * 800000).round(), 800000);
    expect(w.status, GearWearStatus.ok);
  });

  test('gearWear: at target -> worn', () {
    expect(gearWear(800000, 800000).status, GearWearStatus.worn);
  });

  test('gearWear: over target -> worn, fraction > 1 (uncapped)', () {
    final w = gearWear(960000, 800000); // 120%
    expect(w.status, GearWearStatus.worn);
    expect(((w.fraction ?? 0) - 1.2).abs(), lessThan(1e-9));
  });

  test('gearWear: zero / negative / non-finite total clamps to 0 -> ok', () {
    expect(gearWear(0, 800000).status, GearWearStatus.ok);
    expect(gearWear(-100, 800000).status, GearWearStatus.ok);
    expect(gearWear(double.nan, 800000).status, GearWearStatus.ok);
  });

  test('gearWear: non-finite / negative target -> untracked', () {
    expect(gearWear(500000, double.nan).status, GearWearStatus.untracked);
    expect(gearWear(500000, -10).status, GearWearStatus.untracked);
  });
}
