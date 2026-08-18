// ignore_for_file: avoid_relative_lib_imports
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/pace_analysis.dart';
import '../lib/run_stats.dart' show computeSplitDurations;

/// Mirror of `apps/web/src/lib/runs/pace_analysis.test.ts`. Keep in lockstep —
/// the pacing-halves card and the grade-adjusted split column render off this
/// on both platforms.

const double metresPerDegLng = 111320;
final DateTime startTs = DateTime.utc(2026, 4, 1, 7);

/// Equator-aligned synthetic track. [paces] is one seconds-per-km figure per
/// half; each half covers [halfM] metres in [stepM] steps, so the second entry's
/// pace applies from the halfway mark on. [elePerStep] shifts altitude by a
/// fixed amount per step within each half.
List<Waypoint> track({
  required double halfM,
  required double stepM,
  required List<double> paces,
  List<double>? elePerStep,
  double? startEle,
}) {
  final stepsPerHalf = (halfM / stepM).round();
  final out = <Waypoint>[];
  var tMs = startTs.millisecondsSinceEpoch;
  var ele = startEle;
  for (var half = 0; half < 2; half++) {
    final stepS = (paces[half] * stepM) / 1000;
    final eleStep = elePerStep?[half] ?? 0.0;
    for (var i = 0; i < stepsPerHalf; i++) {
      final idx = half * stepsPerHalf + i;
      out.add(Waypoint(
        lat: 0,
        lng: (idx * stepM) / metresPerDegLng,
        elevationMetres: ele,
        timestamp: DateTime.fromMillisecondsSinceEpoch(tMs.round(), isUtc: true),
      ));
      tMs += (stepS * 1000).round();
      if (ele != null) ele += eleStep;
    }
  }
  // Closing point so the final step is covered.
  out.add(Waypoint(
    lat: 0,
    lng: (2 * stepsPerHalf * stepM) / metresPerDegLng,
    elevationMetres: ele,
    timestamp: DateTime.fromMillisecondsSinceEpoch(tMs.round(), isUtc: true),
  ));
  return out;
}

void main() {
  test('analysePacing returns null without a track, or with one point', () {
    expect(analysePacing(null), isNull);
    expect(
        analysePacing([Waypoint(lat: 0, lng: 0, timestamp: startTs)]), isNull);
  });

  test('analysePacing returns null when the track covers no distance', () {
    final t = [
      Waypoint(lat: 0, lng: 0, timestamp: startTs),
      Waypoint(lat: 0, lng: 0, timestamp: DateTime.utc(2026, 4, 1, 7, 5)),
    ];
    expect(analysePacing(t), isNull);
  });

  test('analysePacing returns null when the track carries no timestamps', () {
    final t = track(halfM: 1000, stepM: 100, paces: [300, 300])
        .map((p) => Waypoint(lat: p.lat, lng: p.lng))
        .toList();
    expect(analysePacing(t), isNull);
  });

  test('analysePacing calls a steady run an even split', () {
    final a = analysePacing(track(halfM: 2000, stepM: 100, paces: [300, 300]));
    expect(a, isNotNull);
    expect(a!.raw.verdict, PacingVerdict.even);
    expect(a.raw.deltaSecPerKm, 0);
    expect(a.raw.first.paceSecPerKm, 300);
    expect(a.raw.second.paceSecPerKm, 300);
    // No elevation on the track, so GAP carries no information.
    expect(a.gradeAdjusted, isNull);
  });

  test('analysePacing splits the halves by distance, not by time', () {
    // A fading run: if halves were cut by time the slower second half would be
    // short of the halfway mark and both halves would report the same distance
    // only by accident. Cut by distance, they are equal.
    final a = analysePacing(track(halfM: 2000, stepM: 100, paces: [300, 400]));
    expect(a, isNotNull);
    expect((a!.raw.first.distanceM - a.raw.second.distanceM).abs(), lessThan(1));
    expect(a.raw.first.paceSecPerKm, 300);
    expect(a.raw.second.paceSecPerKm, 400);
  });

  test('analysePacing flags a faster second half as a negative split', () {
    final a = analysePacing(track(halfM: 2000, stepM: 100, paces: [300, 270]));
    expect(a, isNotNull);
    expect(a!.raw.verdict, PacingVerdict.negative);
    expect(a.raw.deltaSecPerKm, -30);
  });

  test('analysePacing flags a slower second half as a positive split', () {
    final a = analysePacing(track(halfM: 2000, stepM: 100, paces: [300, 330]));
    expect(a, isNotNull);
    expect(a!.raw.verdict, PacingVerdict.positive);
    expect(a.raw.deltaSecPerKm, 30);
  });

  test('a drift inside the even band still reads as even, just outside it does not',
      () {
    // 2 % of a 300 s/km first half is 6 s/km.
    expect(300 * evenBandPct, 6);
    final inside = analysePacing(track(halfM: 2000, stepM: 100, paces: [300, 305]));
    expect(inside?.raw.verdict, PacingVerdict.even);
    final outside =
        analysePacing(track(halfM: 2000, stepM: 100, paces: [300, 307]));
    expect(outside?.raw.verdict, PacingVerdict.positive);
  });

  test('a second half that climbs reads as a fade raw but even on effort', () {
    // Same 2 km halves; the second half slows by 24 % while climbing 4 m per
    // 100 m step (a sustained 4 % grade, whose Minetti cost factor is 1.2365 —
    // so 300 s/km of effort is run at 371 s/km). Raw pace fades, effort holds.
    final a = analysePacing(track(
      halfM: 2000,
      stepM: 100,
      paces: [300, 371],
      startEle: 100,
      elePerStep: [0, 4],
    ));
    expect(a, isNotNull);
    expect(a!.raw.verdict, PacingVerdict.positive);
    expect(a.gradeAdjusted, isNotNull);
    expect(a.gradeAdjusted!.verdict, PacingVerdict.even);
    expect(a.gradeAdjusted!.firstSecPerKm, 300);
    expect(a.gradeAdjusted!.secondSecPerKm, 300);
  });

  test('gradeAdjustedSplitPaces returns one aligned entry per split', () {
    final t = track(
        halfM: 2000,
        stepM: 100,
        paces: [300, 371],
        startEle: 100,
        elePerStep: [0, 4]);
    final splits = computeSplitDurations(t, 1000, startTs);
    final gap = gradeAdjustedSplitPaces(t, List.filled(splits.length, 1000.0));
    expect(gap.length, splits.length);
    expect(splits.length, 3);
    // Splits 1-2 are flat: GAP is the pace they were run at.
    expect(gap[0], splits[0].duration.inMilliseconds ~/ 1000);
    expect(gap[1], splits[1].duration.inMilliseconds ~/ 1000);
    // Split 3 climbs: GAP is faster than the raw pace it was run at.
    expect(gap[2], isNotNull);
    expect(gap[2]!, lessThan(splits[2].duration.inMilliseconds ~/ 1000));
  });

  test('gradeAdjustedSplitPaces is null for a split with no elevation', () {
    final t = track(halfM: 2000, stepM: 100, paces: [300, 300]);
    final splits = computeSplitDurations(t, 1000, startTs);
    expect(splits.length, 3);
    expect(gradeAdjustedSplitPaces(t, List.filled(splits.length, 1000.0)),
        List<int?>.filled(splits.length, null));
  });

  test('gradeAdjustedSplitPaces degenerates safely', () {
    expect(gradeAdjustedSplitPaces(null, const []), isEmpty);
    final splits = computeSplitDurations(
        track(halfM: 1000, stepM: 100, paces: [300, 300]), 1000, startTs);
    expect(splits.length, greaterThan(0));
    expect(gradeAdjustedSplitPaces(null, List.filled(splits.length, 1000.0)),
        List<int?>.filled(splits.length, null));
    expect(
        gradeAdjustedSplitPaces(
            [Waypoint(lat: 0, lng: 0)], List.filled(splits.length, 1000.0)),
        List<int?>.filled(splits.length, null));
  });

  test('halves stay sane across the antimeridian', () {
    // Four points straddling 180°: a plain longitude subtraction at the cut
    // would place the interpolated boundary point most of a turn away and
    // blow the two halves' distances apart.
    final t = [
      Waypoint(lat: 0, lng: 179.98, timestamp: DateTime.utc(2026, 4, 1, 7)),
      Waypoint(lat: 0, lng: 179.99, timestamp: DateTime.utc(2026, 4, 1, 7, 3)),
      Waypoint(lat: 0, lng: -179.99, timestamp: DateTime.utc(2026, 4, 1, 7, 9)),
      Waypoint(lat: 0, lng: -179.98, timestamp: DateTime.utc(2026, 4, 1, 7, 12)),
    ];
    final a = analysePacing(t);
    expect(a, isNotNull);
    expect((a!.raw.first.distanceM - a.raw.second.distanceM).abs(), lessThan(1));
    expect(a.raw.first.distanceM, lessThan(3000));
  });
}
