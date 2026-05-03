// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../lib/widgets/track_decorations.dart';

const double _metresPerLatDegree = 111320;

/// Build a straight north-bound track of [n] waypoints, [stepM] apart,
/// anchored at lat0 / lng0.
List<LatLng> _straight({
  required int n,
  required double stepM,
  double lat0 = 0,
  double lng0 = 0,
}) {
  final out = <LatLng>[];
  for (int i = 0; i < n; i++) {
    out.add(LatLng(lat0 + i * stepM / _metresPerLatDegree, lng0));
  }
  return out;
}

void main() {
  group('computeDistanceMarkers', () {
    test('emits one marker per km on a 5 km straight track', () {
      final track = _straight(n: 51, stepM: 100); // 5000 m
      final markers = computeDistanceMarkers(track, useMiles: false);
      // Markers at 1, 2, 3, 4 km; the 5 km mark coincides with the end
      // cap so it's optional — accept 4 or 5.
      expect(markers.length, inInclusiveRange(4, 5));
      expect(markers.first.label, 1);
      expect(markers[1].label, 2);
      expect(markers[2].label, 3);
      expect(markers[3].label, 4);
    });

    test('returns empty for tracks under 2 points', () {
      expect(computeDistanceMarkers(const [], useMiles: false), isEmpty);
      expect(
        computeDistanceMarkers([const LatLng(0, 0)], useMiles: false),
        isEmpty,
      );
    });

    test('returns empty when the track is shorter than one step', () {
      final track = _straight(n: 5, stepM: 100); // 400 m, less than 1 km
      expect(computeDistanceMarkers(track, useMiles: false), isEmpty);
    });

    test('miles produces fewer markers than km on the same track', () {
      final track = _straight(n: 51, stepM: 100); // 5000 m
      final km = computeDistanceMarkers(track, useMiles: false).length;
      final mi = computeDistanceMarkers(track, useMiles: true).length;
      expect(mi, lessThan(km), reason: '5 km is only ~3.1 mi');
      expect(mi, inInclusiveRange(2, 3));
    });

    test('totalDistanceM rescales markers when polyline is sparse', () {
      // 1 km of polyline geometry but the authoritative route distance
      // is 5 km — markers should still cover 1..5 along the polyline.
      final track = _straight(n: 11, stepM: 100); // 1000 m polyline
      final markers = computeDistanceMarkers(
        track,
        useMiles: false,
        totalDistanceM: 5000,
      );
      expect(markers.length, inInclusiveRange(4, 5));
      expect(markers.last.label, inInclusiveRange(4, 5));
    });

    test('marker positions interpolate within segments', () {
      // Two-point track, ~2 km long via haversine. The 1 km marker
      // should land at roughly the midpoint — within 5 m, which is
      // GPS noise floor.
      final track = [
        const LatLng(0, 0),
        LatLng(2000 / _metresPerLatDegree, 0),
      ];
      final markers = computeDistanceMarkers(track, useMiles: false);
      expect(markers.length, 1);
      // 5 m / 111_320 m per lat degree ≈ 4.5e-5 degrees of slack.
      expect(
        (markers.first.position.latitude - 1000 / _metresPerLatDegree).abs(),
        lessThan(5e-5),
      );
    });
  });

  group('computeChevrons', () {
    test('emits chevrons every stepMetres along the track', () {
      final track = _straight(n: 21, stepM: 100); // 2000 m
      final chevrons = computeChevrons(track, stepMetres: 500);
      // 500, 1000, 1500 — 1750 cap is past 2000 - 250.
      expect(chevrons.length, inInclusiveRange(3, 4));
    });

    test('returns empty for tracks shorter than stepMetres', () {
      final short = _straight(n: 3, stepM: 100); // 200 m
      expect(computeChevrons(short, stepMetres: 500), isEmpty);
    });

    test('north-bound chevrons rotate to point up', () {
      final track = _straight(n: 11, stepM: 100); // 1 km north
      final chevrons = computeChevrons(track, stepMetres: 500);
      // Screen-y grows downward; a north-bound segment maps to angle
      // -π/2 (the chevron icon points right at angle 0 and rotates
      // counter-clockwise to point up).
      expect(chevrons.first.angleRadians, closeTo(-pi / 2, 0.05));
    });

    test('returns empty for invalid stepMetres', () {
      final track = _straight(n: 11, stepM: 100);
      expect(computeChevrons(track, stepMetres: 0), isEmpty);
      expect(computeChevrons(track, stepMetres: -10), isEmpty);
    });
  });
}
