import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/grade_adjusted_pace.dart';

/// Mirror of `apps/web/src/lib/runs/grade_adjusted_pace.test.ts`. Keep in
/// lockstep — the GAP figure shown on mobile run detail and on web run detail
/// (and the on-watch Connect IQ field) all derive from this Minetti model.

/// Build a straight east-west track at a constant horizontal speed and a
/// constant grade. [gradePct] is rise/run as a percentage.
List<Waypoint> gradedTrack({
  required int points,
  required double stepM,
  required double stepS,
  required double gradePct,
  double eleStart = 100,
  bool withEle = true,
  bool withTs = true,
}) {
  const lat = 40.0;
  final t0 = DateTime.utc(2026, 1, 1);
  final degPerM = 1 / (111320 * cos(lat * pi / 180));
  final out = <Waypoint>[];
  var ele = eleStart;
  for (var i = 0; i < points; i++) {
    out.add(Waypoint(
      lat: lat,
      lng: -100 + i * stepM * degPerM,
      elevationMetres: withEle ? ele : null,
      timestamp: withTs ? t0.add(Duration(milliseconds: (i * stepS * 1000).round())) : null,
    ));
    ele += (gradePct / 100) * stepM;
  }
  return out;
}

void main() {
  group('Minetti model', () {
    test('cost at flat is the cached flat constant', () {
      expect(minettiCostAtGrade(0), minettiFlatCost);
      expect(gradeFactor(0), 1);
    });

    test('uphill costs more than flat, downhill (gentle) costs less', () {
      expect(gradeFactor(0.1), greaterThan(1));
      expect(gradeFactor(-0.1), lessThan(1));
    });

    test('grade is clamped to Minetti valid range', () {
      expect(gradeFactor(0.9), gradeFactor(maxGrade));
      expect(gradeFactor(-0.9), gradeFactor(-maxGrade));
    });
  });

  group('gradeAdjustedPaceSecPerKm', () {
    test('flat run: GAP equals raw pace', () {
      final track = gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: 0);
      expect(gradeAdjustedPaceSecPerKm(track), 200);
    });

    test('uphill run: GAP is faster than raw pace', () {
      final track = gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: 10);
      final gap = gradeAdjustedPaceSecPerKm(track);
      expect(gap, isNotNull);
      expect(gap!, lessThan(200));
    });

    test('descent run: GAP is slower than raw pace', () {
      final track = gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: -10);
      final gap = gradeAdjustedPaceSecPerKm(track);
      expect(gap, isNotNull);
      expect(gap!, greaterThan(200));
    });

    test('no elevation data: GAP is null', () {
      final track =
          gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: 10, withEle: false);
      expect(gradeAdjustedPaceSecPerKm(track), isNull);
    });

    test('no timestamps: GAP is null', () {
      final track =
          gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: 10, withTs: false);
      expect(gradeAdjustedPaceSecPerKm(track), isNull);
    });

    test('too few points: GAP is null', () {
      expect(gradeAdjustedPaceSecPerKm([]), isNull);
      expect(
        gradeAdjustedPaceSecPerKm([
          Waypoint(lat: 40, lng: -100, elevationMetres: 100, timestamp: DateTime.utc(2026)),
        ]),
        isNull,
      );
    });

    test('mixed track with some missing elevation still computes', () {
      final track = gradedTrack(points: 60, stepM: 5, stepS: 1, gradePct: 10);
      // Null out elevation on a mid-run cluster — those segments fall back to
      // factor 1, but the run as a whole still has grade signal.
      for (var i = 20; i < 25; i++) {
        track[i] = Waypoint(lat: track[i].lat, lng: track[i].lng, timestamp: track[i].timestamp);
      }
      final gap = gradeAdjustedPaceSecPerKm(track);
      expect(gap, isNotNull);
      expect(gap!, lessThan(200));
    });
  });
}
