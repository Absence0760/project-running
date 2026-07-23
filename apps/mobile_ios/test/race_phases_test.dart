import 'package:flutter_test/flutter_test.dart';
import '../lib/race_phases.dart';

const double tenMileFraction = 16093.44 / 42195;

double weightedMeanFactor(List<RacePhase> phases) {
  final total = phases.last.endM;
  var sum = 0.0;
  for (final p in phases) {
    sum += p.paceFactor * (p.endM - p.startM);
  }
  return sum / total;
}

void main() {
  test('even preset is one full-distance phase at factor 1', () {
    final plan = buildPhasePlan(10000, RacePhasePreset.even);
    expect(plan.length, 1);
    expect(plan[0].startM, 0);
    expect(plan[0].endM, 10000);
    expect(plan[0].intent, RacePhaseIntent.even);
    expect(plan[0].paceFactor, 1);
  });

  test('ten_ten_ten boundaries land on the generalised 10-mile fractions for a marathon', () {
    final plan = buildPhasePlan(42195, RacePhasePreset.tenTenTen);
    expect(plan.length, 3);
    expect(plan[0].startM, 0);
    expect(plan[1].startM, closeTo(16093.44, 1e-9));
    expect(plan[2].startM, closeTo(32186.88, 1e-9));
    expect(plan[2].endM, 42195);
    expect(plan[0].endM, plan[1].startM);
    expect(plan[1].endM, plan[2].startM);
  });

  test('ten_ten_ten intents and factors: hold back, settle, then a derived faster finish', () {
    final plan = buildPhasePlan(42195, RacePhasePreset.tenTenTen);
    expect(plan.map((p) => p.intent).toList(),
        [RacePhaseIntent.holdBack, RacePhaseIntent.settle, RacePhaseIntent.race]);
    expect(plan[0].paceFactor, 1.02);
    expect(plan[1].paceFactor, 1);
    const f = tenMileFraction;
    const derived = (1 - f * 1.02 - f * 1) / (1 - f - f);
    expect(plan[2].paceFactor, closeTo(derived, 1e-12));
    expect(plan[2].paceFactor > 0.96 && plan[2].paceFactor < 0.97, isTrue);
  });

  test('distance-weighted mean factor is 1 for ten_ten_ten at any distance', () {
    for (final distanceM in [42195.0, 10000.0, 160934.0]) {
      final plan = buildPhasePlan(distanceM, RacePhasePreset.tenTenTen);
      expect(weightedMeanFactor(plan), closeTo(1, 1e-9));
    }
  });

  test('negative_split is two halves: held back then a derived faster finish, mean 1', () {
    final plan = buildPhasePlan(21097.5, RacePhasePreset.negativeSplit);
    expect(plan.length, 2);
    expect(plan.map((p) => p.intent).toList(),
        [RacePhaseIntent.holdBack, RacePhaseIntent.race]);
    expect(plan[0].endM, 21097.5 / 2);
    expect(plan[1].startM, 21097.5 / 2);
    expect(plan[0].paceFactor, 1.02);
    expect(plan[1].paceFactor, closeTo((1 - 0.5 * 1.02) / 0.5, 1e-12));
    expect(weightedMeanFactor(plan), closeTo(1, 1e-9));
  });

  test('phaseAt: an exact boundary belongs to the next phase', () {
    final plan = buildPhasePlan(42195, RacePhasePreset.tenTenTen);
    expect(phaseAt(plan, 0), 0);
    expect(phaseAt(plan, plan[1].startM - 0.001), 0);
    expect(phaseAt(plan, plan[1].startM), 1);
    expect(phaseAt(plan, plan[2].startM), 2);
  });

  test('phaseAt clamps: past the end to last, negative to first, empty to -1', () {
    final plan = buildPhasePlan(42195, RacePhasePreset.tenTenTen);
    expect(phaseAt(plan, 42195), 2);
    expect(phaseAt(plan, 100000), 2);
    expect(phaseAt(plan, -5), 0);
    expect(phaseAt([], 1000), -1);
  });

  test('a non-positive or non-finite distance yields an empty plan', () {
    for (final distanceM in [0.0, -42195.0, double.nan, double.infinity]) {
      expect(buildPhasePlan(distanceM, RacePhasePreset.tenTenTen), isEmpty);
      expect(buildPhasePlan(distanceM, RacePhasePreset.negativeSplit), isEmpty);
      expect(buildPhasePlan(distanceM, RacePhasePreset.even), isEmpty);
    }
  });

  test('goalPaceSecPerKm divides the goal time over the km and rejects bad inputs', () {
    expect(goalPaceSecPerKm(10000, 3000), 300);
    expect(goalPaceSecPerKm(0, 3000), isNull);
    expect(goalPaceSecPerKm(-1, 3000), isNull);
    expect(goalPaceSecPerKm(10000, 0), isNull);
    expect(goalPaceSecPerKm(10000, -60), isNull);
    expect(goalPaceSecPerKm(double.nan, 3000), isNull);
    expect(goalPaceSecPerKm(10000, double.nan), isNull);
  });

  test('phaseTargetPaceSecPerKm scales the goal pace by the phase factor and rejects bad pace', () {
    final plan = buildPhasePlan(42195, RacePhasePreset.tenTenTen);
    expect(phaseTargetPaceSecPerKm(plan[0], 300), closeTo(306, 1e-9));
    expect(phaseTargetPaceSecPerKm(plan[1], 300), 300);
    expect(phaseTargetPaceSecPerKm(plan[0], null), isNull);
    expect(phaseTargetPaceSecPerKm(plan[0], 0), isNull);
    expect(phaseTargetPaceSecPerKm(plan[0], -300), isNull);
    expect(phaseTargetPaceSecPerKm(plan[0], double.nan), isNull);
  });

  test('preset and intent wire names are stable', () {
    expect(RacePhasePreset.values.map((p) => p.wire).toList(),
        ['ten_ten_ten', 'negative_split', 'even']);
    expect(RacePhaseIntent.values.map((i) => i.wire).toList(),
        ['hold_back', 'settle', 'race', 'even']);
  });
}
