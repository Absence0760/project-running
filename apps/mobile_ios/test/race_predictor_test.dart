// Mirror of apps/web/src/lib/training/race_predictor.test.ts — keep the case
// set + count in lockstep.

import 'package:flutter_test/flutter_test.dart';

import '../lib/race_predictor.dart';
import '../lib/training.dart'
    show riegelPredict, PredictionConfidence, PredictionReason;

void main() {
  test('empty pool returns null', () {
    expect(predictRaceLadder([]), isNull);
  });

  test('non-finite / non-positive efforts are filtered out, empty -> null', () {
    final bad = [
      const EffortForPrediction(distanceM: 0, durationS: 1200, ageDays: 1),
      const EffortForPrediction(distanceM: 5000, durationS: 0, ageDays: 1),
      EffortForPrediction(distanceM: 5000, durationS: 1200, ageDays: double.nan),
    ];
    expect(predictRaceLadder(bad), isNull);
  });

  test('one effort produces a full ladder with all four rungs', () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 5000, durationS: 1200, ageDays: 3)]);
    expect(out, isNotNull);
    expect(out!.rungs.length, kRaceLadderM.length);
    expect(out.rungs.map((r) => r.distanceM).toList(), kRaceLadderM);
  });

  test('rungs project from the chosen anchor via Riegel (numbers match the engine)',
      () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 5000, durationS: 1200, ageDays: 0)]);
    expect(out, isNotNull);
    for (final r in out!.rungs) {
      final expected = riegelPredict(5000, 1200, r.distanceM);
      expect((r.predictedSec - expected).abs() < 1e-6, isTrue);
    }
  });

  test('pace is finish-time over distance in km', () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 10000, durationS: 2400, ageDays: 1)]);
    expect(out, isNotNull);
    final tenK = out!.rungs.firstWhere((r) => r.distanceM == 10000);
    expect((tenK.paceSecPerKm - 240).abs() < 1e-6, isTrue);
  });

  test('a recent effort out-anchors a faster-but-stale PR', () {
    const stalePr = EffortForPrediction(
        distanceM: 10000, durationS: 2400, ageDays: 2 * kAnchorRecencyHalflifeDays);
    const fresh =
        EffortForPrediction(distanceM: 10000, durationS: 2700, ageDays: 0);
    final out = predictRaceLadder([stalePr, fresh]);
    expect(out, isNotNull);
    expect(out!.anchor.durationS, 2700);
    expect(out.anchor.ageDays, 0);
  });

  test('a recent PR still wins when it is also the fastest', () {
    const recentPr =
        EffortForPrediction(distanceM: 10000, durationS: 2400, ageDays: 1);
    const slower =
        EffortForPrediction(distanceM: 10000, durationS: 3000, ageDays: 1);
    final out = predictRaceLadder([slower, recentPr]);
    expect(out, isNotNull);
    expect(out!.anchor.durationS, 2400);
  });

  test('qualifyingCount reflects the filtered pool size', () {
    final out = predictRaceLadder([
      const EffortForPrediction(distanceM: 5000, durationS: 1200, ageDays: 1),
      const EffortForPrediction(distanceM: 10000, durationS: 2700, ageDays: 5),
      const EffortForPrediction(distanceM: 0, durationS: 999, ageDays: 1),
    ]);
    expect(out, isNotNull);
    expect(out!.qualifyingCount, 2);
  });

  test('a 10K anchor grades the marathon rung lower than the 10K rung', () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 10000, durationS: 2400, ageDays: 1)]);
    expect(out, isNotNull);
    final tenK = out!.rungs.firstWhere((r) => r.distanceM == 10000);
    final marathon = out.rungs.firstWhere((r) => r.distanceM == 42195);
    expect(marathon.quality.confidence, PredictionConfidence.low);
    expect(tenK.quality.confidence, isNot(PredictionConfidence.low));
  });

  test('a stale-only pool still produces a prediction (no null-out)', () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 10000, durationS: 2700, ageDays: 5000)]);
    expect(out, isNotNull);
    expect(out!.rungs.length, kRaceLadderM.length);
    final tenK = out.rungs.firstWhere((r) => r.distanceM == 10000);
    expect(tenK.quality.confidence, PredictionConfidence.low);
    expect(tenK.quality.reason, PredictionReason.stale);
  });

  test('future-dated effort (clock skew) is treated as weight 1, not amplified',
      () {
    final out = predictRaceLadder(
        [const EffortForPrediction(distanceM: 5000, durationS: 1200, ageDays: -3)]);
    expect(out, isNotNull);
    expect(out!.anchor.ageDays, -3);
  });
}
