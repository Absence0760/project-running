import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/route_simplify.dart';

void main() {
  // Approximate conversions near the equator:
  //   1e-5 degrees latitude  ≈ 1.11 metres
  //   1e-4 degrees latitude  ≈ 11.1 metres
  //   1e-3 degrees latitude  ≈ 111 metres

  Waypoint wp(double lat, double lng, {double? ele}) =>
      Waypoint(lat: lat, lng: lng, elevationMetres: ele);

  group('simplifyTrack', () {
    test('returns input unchanged when fewer than 3 points', () {
      final track = [wp(0, 0), wp(0, 0.001)];
      expect(simplifyTrack(track).length, 2);
    });

    test('drops points that lie on a straight line', () {
      // 5 points along a perfect line east — simplification should keep
      // just the two endpoints.
      final track = [
        wp(0, 0),
        wp(0, 0.001),
        wp(0, 0.002),
        wp(0, 0.003),
        wp(0, 0.004),
      ];
      final out = simplifyTrack(track, epsilonMetres: 5);
      expect(out.length, 2);
      expect(out.first.lng, 0);
      expect(out.last.lng, 0.004);
    });

    test('keeps a sharp corner at higher than epsilon', () {
      // L-shaped path: east, then north. The corner point must be kept.
      final track = [
        wp(0, 0),
        wp(0, 0.001),
        wp(0, 0.002), // corner
        wp(0.001, 0.002),
        wp(0.002, 0.002),
      ];
      final out = simplifyTrack(track, epsilonMetres: 5);
      expect(out.length, 3);
      expect(out[1].lat, 0);
      expect(out[1].lng, 0.002);
    });

    test('smooths sub-epsilon GPS jitter around a straight path', () {
      // A mostly-east line with small random lateral wobble under ~3 m.
      final track = [
        wp(0, 0),
        wp(0.00001, 0.001), // ~1 m north of ideal
        wp(-0.00001, 0.002),
        wp(0.00002, 0.003),
        wp(0, 0.004),
      ];
      final out = simplifyTrack(track, epsilonMetres: 5);
      // Jitter is below the 5 m epsilon so only endpoints survive.
      expect(out.length, 2);
    });

    test('keeps deviations above epsilon', () {
      // 20 m detour south in the middle of an otherwise-straight line.
      final track = [
        wp(0, 0),
        wp(0, 0.001),
        wp(-0.00018, 0.002), // ~20 m south
        wp(0, 0.003),
        wp(0, 0.004),
      ];
      final out = simplifyTrack(track, epsilonMetres: 5);
      expect(out.length, greaterThanOrEqualTo(3));
      expect(out.any((w) => w.lat < -0.00001), isTrue);
    });
  });

  group('computeElevationGain', () {
    test('returns zero for flat or missing data', () {
      expect(
        computeElevationGain([wp(0, 0, ele: 10), wp(0, 0.001, ele: 10)]),
        0,
      );
      expect(
        computeElevationGain([wp(0, 0), wp(0, 0.001)]),
        0,
      );
    });

    test('accumulates only positive segments', () {
      final track = [
        wp(0, 0, ele: 10),
        wp(0, 0.001, ele: 15), // +5
        wp(0, 0.002, ele: 12), // -3, ignored
        wp(0, 0.003, ele: 20), // +8
      ];
      expect(computeElevationGain(track), 13);
    });

    test('skips segments where either end lacks an elevation reading', () {
      final track = [
        wp(0, 0, ele: 10),
        wp(0, 0.001), // no elevation
        wp(0, 0.002, ele: 20),
      ];
      // The middle segment can't contribute because one end is null.
      expect(computeElevationGain(track), 0);
    });
  });
}
