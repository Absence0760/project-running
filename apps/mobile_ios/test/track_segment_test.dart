// ignore_for_file: avoid_relative_lib_imports
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../lib/widgets/track_segment.dart';

const double _metresPerLatDegree = 111320;

/// Build a straight north-bound track of [n] waypoints, [stepM] apart,
/// stamped with timestamps that step by [stepS] seconds.
List<Waypoint> _track({
  required int n,
  required double stepM,
  required double stepS,
  double? eleStep,
  int? bpm,
}) {
  final out = <Waypoint>[];
  final t0 = DateTime.utc(2026, 1, 1);
  for (int i = 0; i < n; i++) {
    out.add(Waypoint(
      lat: i * stepM / _metresPerLatDegree,
      lng: 0,
      timestamp: t0.add(Duration(milliseconds: (i * stepS * 1000).round())),
      elevationMetres: eleStep == null ? null : i * eleStep,
      bpm: bpm,
    ));
  }
  return out;
}

void main() {
  group('buildCumulativeDistances', () {
    test('returns increasing distances starting at 0', () {
      final track = _track(n: 5, stepM: 100, stepS: 1);
      final cum = buildCumulativeDistances(track);
      expect(cum.length, 5);
      expect(cum.first, 0);
      for (int i = 1; i < cum.length; i++) {
        expect(cum[i], greaterThan(cum[i - 1]));
      }
      // 4 × 100 m segments → ~400 m total (haversine vs equirectangular
      // accounts for the small slack).
      expect(cum.last, closeTo(400, 5));
    });
  });

  group('nearestTrackIdx', () {
    test('returns the index of the closest waypoint', () {
      final track = _track(n: 11, stepM: 100, stepS: 1); // 0..1000 m
      // Tap at the midpoint, lat = 500 m / lat-degree.
      final tap = LatLng(500 / _metresPerLatDegree, 0);
      expect(nearestTrackIdx(tap, track), 5);
    });
  });

  group('buildSegmentAt', () {
    test('returns null for tracks under 2 points', () {
      expect(buildSegmentAt(const [], 0), isNull);
      expect(
        buildSegmentAt([
          const Waypoint(lat: 0, lng: 0),
        ], 0),
        isNull,
      );
    });

    test('expands to ±150 m around the click index', () {
      // 100 m steps for 21 points → 0..2000 m. Click at idx 10 (1000 m).
      final track = _track(n: 21, stepM: 100, stepS: 1);
      final seg = buildSegmentAt(track, 10)!;
      // Window is 850..1150 m. With 100 m steps that's idx 9..11 (or
      // 8..12 depending on how the boundary expansion lands).
      expect(seg.startIdx, lessThanOrEqualTo(10));
      expect(seg.endIdx, greaterThanOrEqualTo(10));
      // Distance ~300 m worth of segments around the centre.
      expect(seg.distanceMetres, inInclusiveRange(190, 320));
    });

    test('computes pace and duration from per-point timestamps', () {
      // 1 m/s pace → 1000 s/km exactly.
      final track = _track(n: 21, stepM: 100, stepS: 100);
      final seg = buildSegmentAt(track, 10)!;
      expect(seg.duration, isNotNull);
      expect(seg.paceSecondsPerKm, closeTo(1000, 5));
    });

    test('returns null pace when distance is below 10 m', () {
      // Two points only ~5 m apart — segment width ≤ 10 m, pace nulls.
      final track = [
        Waypoint(
          lat: 0,
          lng: 0,
          timestamp: DateTime.utc(2026, 1, 1),
        ),
        Waypoint(
          lat: 5 / _metresPerLatDegree,
          lng: 0,
          timestamp: DateTime.utc(2026, 1, 1, 0, 0, 1),
        ),
      ];
      final seg = buildSegmentAt(track, 0)!;
      expect(seg.distanceMetres, lessThan(10));
      expect(seg.paceSecondsPerKm, isNull);
    });

    test('aggregates avgBpm only over plausibly-valid samples', () {
      final track = _track(n: 21, stepM: 100, stepS: 1, bpm: 150);
      final seg = buildSegmentAt(track, 10)!;
      expect(seg.avgBpm, 150);
    });

    test('accumulates elevation gain only on positive deltas', () {
      // 21 points, +1 m per step → +20 m total in 2 km.
      final track = _track(n: 21, stepM: 100, stepS: 1, eleStep: 1);
      final seg = buildSegmentAt(track, 10)!;
      expect(seg.eleGainMetres, greaterThan(0));
      expect(seg.eleLossMetres, 0);
    });

    test('widens past a degenerate single-point selection at the edge', () {
      // Click at the very last index — buildSegment should expand
      // backwards by one neighbour so distance is non-zero.
      final track = _track(n: 5, stepM: 100, stepS: 1);
      final seg = buildSegmentAt(track, 4)!;
      expect(seg.startIdx, lessThan(seg.endIdx));
      expect(seg.distanceMetres, greaterThan(0));
    });
  });
}
