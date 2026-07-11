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
  double distAlongRouteM = 10000,
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
}
