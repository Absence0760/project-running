import 'package:flutter_test/flutter_test.dart';
import '../lib/roadbook.dart';
import '../lib/live_cutoff_eta.dart';

List<RoadbookWaypoint> flatRoute(double metres, [int steps = 20]) {
  final totalDeg = metres / 111320;
  final out = <RoadbookWaypoint>[];
  for (var i = 0; i <= steps; i++) {
    out.add(RoadbookWaypoint(lat: 0, lng: totalDeg * i / steps));
  }
  return out;
}

List<RoadbookLeg> legsWithTwoCutoffs() {
  final waypoints = flatRoute(40000);
  final markers = <RoadbookMarker>[
    const RoadbookMarker(
        positionM: 20000,
        kind: 'cutoff',
        label: 'Halfway',
        meta: {'cutoff_elapsed_s': 7200}),
    const RoadbookMarker(
        positionM: 40000,
        kind: 'cutoff',
        label: 'Finish gate',
        meta: {'cutoff_elapsed_s': 18000}),
  ];
  return buildRoadbook(waypoints, markers,
          goalSeconds: 16000, model: PacingModel.even)
      .legs;
}

LiveCutoffEta call({
  double? distAlongRouteM = 10000,
  double elapsedS = 3600,
  double? recentPaceSecPerKm = 360,
  List<RoadbookLeg>? legs,
  bool stale = false,
}) =>
    nextCutoffEta(
      distAlongRouteM: distAlongRouteM,
      elapsedS: elapsedS,
      recentPaceSecPerKm: recentPaceSecPerKm,
      legs: legs ?? legsWithTwoCutoffs(),
      stale: stale,
    );

void main() {
  test('on-pace projection grades the next cutoff "on"', () {
    final eta = call(recentPaceSecPerKm: 180);
    expect(eta.checkpoint?.label, 'Halfway');
    expect(eta.distanceToM, 10000);
    expect(eta.projectedArrivalElapsedS, 5400);
    expect(eta.marginS, 1800);
    expect(eta.status, LiveCutoffStatus.on);
    expect(eta.marginS! >= cutoffTightS, isTrue);
  });

  test('a margin just under the tight threshold grades "tight"', () {
    final eta = call(recentPaceSecPerKm: 180.1);
    expect(eta.status, LiveCutoffStatus.tight);
    expect(eta.marginS! > 0 && eta.marginS! < cutoffTightS, isTrue);
  });

  test('a negative margin grades "behind"', () {
    final eta = call(recentPaceSecPerKm: 540);
    expect(eta.status, LiveCutoffStatus.behind);
    expect(eta.projectedArrivalElapsedS, 9000);
    expect(eta.marginS, -1800);
  });

  test('a stale live fix returns unknown with no fabricated ETA', () {
    final eta = call(stale: true, recentPaceSecPerKm: 180);
    expect(eta.status, LiveCutoffStatus.unknown);
    expect(eta.projectedArrivalElapsedS, isNull);
    expect(eta.marginS, isNull);
    expect(eta.checkpoint?.label, 'Halfway');
    expect(eta.distanceToM, 10000);
  });

  test('null pace returns unknown', () {
    final eta = call(recentPaceSecPerKm: null);
    expect(eta.status, LiveCutoffStatus.unknown);
    expect(eta.projectedArrivalElapsedS, isNull);
    expect(eta.marginS, isNull);
  });

  test('zero (or negative) pace returns unknown', () {
    final eta = call(recentPaceSecPerKm: 0);
    expect(eta.status, LiveCutoffStatus.unknown);
    expect(eta.projectedArrivalElapsedS, isNull);
  });

  test('a non-finite pace returns unknown, never a fabricated on-pace ETA', () {
    for (final pace in [double.nan, double.infinity]) {
      final eta = call(recentPaceSecPerKm: pace);
      expect(eta.status, LiveCutoffStatus.unknown);
      expect(eta.projectedArrivalElapsedS, isNull);
    }
  });

  test('a runner past the last cutoff has no checkpoint and is unknown', () {
    final eta = call(distAlongRouteM: 40000);
    expect(eta.checkpoint, isNull);
    expect(eta.distanceToM, 0);
    expect(eta.projectedArrivalElapsedS, isNull);
    expect(eta.marginS, isNull);
    expect(eta.status, LiveCutoffStatus.unknown);
  });

  test('picks the NEAREST cutoff ahead when several remain', () {
    final eta = call(distAlongRouteM: 5000);
    expect(eta.checkpoint?.label, 'Halfway');
    expect(eta.distanceToM, 15000);
  });

  test('ignores cutoffs already behind the runner', () {
    final eta = call(distAlongRouteM: 25000);
    expect(eta.checkpoint?.label, 'Finish gate');
    expect((eta.distanceToM - 15000).abs() < 100, isTrue);
  });

  test('required pace is the remaining budget spread over the remaining distance', () {
    // 7200 limit - 3600 elapsed = 3600 s left over 10 km → 360 s/km.
    final eta = call();
    expect(eta.requiredPaceSecPerKm, 360);
  });

  test('no checkpoint means no required pace', () {
    final eta = call(distAlongRouteM: 40000);
    expect(eta.checkpoint, isNull);
    expect(eta.requiredPaceSecPerKm, isNull);
  });

  test('a cutoff under 50 m away has no meaningful required pace', () {
    // 20000 - 19960 = 40 m out; status is still graded from recent pace.
    final eta = call(distAlongRouteM: 19960);
    expect(eta.distanceToM, 40);
    expect(eta.requiredPaceSecPerKm, isNull);
    expect(eta.status, LiveCutoffStatus.on);
  });

  test('a limit already passed cannot be made at any pace', () {
    for (final elapsedS in [7200.0, 8000.0]) {
      final eta = call(elapsedS: elapsedS);
      expect(eta.requiredPaceSecPerKm, isNull);
      expect(eta.status, LiveCutoffStatus.behind);
    }
  });

  test('limitPassed separates an expired limit from a too-close projection',
      () {
    final expired = call(elapsedS: 8000);
    expect(expired.requiredPaceSecPerKm, isNull);
    expect(expired.limitPassed, isTrue);

    final close = call(distAlongRouteM: 19960);
    expect(close.requiredPaceSecPerKm, isNull);
    expect(close.limitPassed, isFalse);
  });

  test('a stale fix or unknown pace still reports the required pace', () {
    final staleEta = call(stale: true);
    expect(staleEta.status, LiveCutoffStatus.unknown);
    expect(staleEta.projectedArrivalElapsedS, isNull);
    expect(staleEta.requiredPaceSecPerKm, 360);

    final noPaceEta = call(recentPaceSecPerKm: null);
    expect(noPaceEta.status, LiveCutoffStatus.unknown);
    expect(noPaceEta.requiredPaceSecPerKm, 360);
  });

  test('an unlocated runner names no checkpoint rather than the first one', () {
    // The spectator screen cannot project a position onto the course until the
    // first fix arrives. Substituting 0 would name the 20 km cutoff and claim
    // the full 20 km still to go, from a runner who might be at km 39.
    for (final distAlongRouteM in <double?>[null, double.nan, double.infinity]) {
      final eta = call(distAlongRouteM: distAlongRouteM);
      expect(eta.checkpoint, isNull, reason: 'distAlongRouteM=$distAlongRouteM');
      expect(eta.distanceToM, 0);
      expect(eta.projectedArrivalElapsedS, isNull);
      expect(eta.marginS, isNull);
      expect(eta.requiredPaceSecPerKm, isNull);
      expect(eta.limitPassed, isFalse);
      expect(eta.status, LiveCutoffStatus.unknown);
    }
  });

  test('a located runner at the start line still names the first cutoff', () {
    // 0 is a legitimate position — the collapse is for null/non-finite only.
    final eta = call(distAlongRouteM: 0);
    expect(eta.checkpoint?.label, 'Halfway');
    expect(eta.distanceToM, 20000);
  });
}
