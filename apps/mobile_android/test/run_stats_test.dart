import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/run_stats.dart';

void main() {
  group('movingTimeOf', () {
    // Zürich coordinates, moving eastward. ~0.00001 degree of longitude at
    // 47.37°N is ~0.75 m — usable for constructing realistic short segments.
    const lat = 47.37;
    const lngBase = 8.54;

    Waypoint wp({
      required double metresEast,
      required int secondsFromStart,
    }) {
      // 1 metre east ≈ 1 / (111320 * cos(lat)) degrees of longitude.
      final metrePerDeg = 111320 * 0.6773; // cos(47.37°)
      final lng = lngBase + metresEast / metrePerDeg;
      return Waypoint(
        lat: lat,
        lng: lng,
        timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
      );
    }

    test('returns zero for empty or single-point tracks', () {
      expect(movingTimeOf(const []), Duration.zero);
      expect(
        movingTimeOf([wp(metresEast: 0, secondsFromStart: 0)]),
        Duration.zero,
      );
    });

    test('includes fast segments (running pace)', () {
      // 12 m in 4 s → 3 m/s → running
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 12, secondsFromStart: 4),
      ];
      expect(movingTimeOf(track), const Duration(seconds: 4));
    });

    test('excludes slow segments below the default 0.5 m/s threshold', () {
      // 1 m in 5 s → 0.2 m/s → standing still / GPS jitter
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 1, secondsFromStart: 5),
      ];
      expect(movingTimeOf(track), Duration.zero);
    });

    test('mixed: running then long stop then running', () {
      // 10 m in 5 s (2 m/s, moving)
      // 0.5 m in 90 s (0.006 m/s, stopped at a light)
      // 10 m in 5 s (2 m/s, moving again)
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 10, secondsFromStart: 5),
        wp(metresEast: 10.5, secondsFromStart: 95),
        wp(metresEast: 20.5, secondsFromStart: 100),
      ];
      // Moving = 5 + 5 = 10s. Elapsed = 100s. Stop segment excluded.
      expect(movingTimeOf(track), const Duration(seconds: 10));
    });

    test('custom threshold can include slower walks', () {
      // 1.5 m in 5 s → 0.3 m/s → below default, above custom 0.2
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 1.5, secondsFromStart: 5),
      ];
      expect(movingTimeOf(track), Duration.zero); // default threshold
      expect(
        movingTimeOf(track, minSpeedMps: 0.2),
        const Duration(seconds: 5),
      );
    });

    test('skips segments with missing timestamps', () {
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        Waypoint(lat: lat, lng: lngBase + 0.0001), // no timestamp
        wp(metresEast: 10, secondsFromStart: 5),
      ];
      // First segment skipped (no timestamp on either end); second segment
      // is counted because both endpoints have timestamps. But wait — the
      // second segment compares point[1] (no ts) to point[2]. That one is
      // also skipped. So nothing counted.
      expect(movingTimeOf(track), Duration.zero);
    });

    test('skips segments with zero or negative dt', () {
      // Two points with the same timestamp → dt = 0
      final ts = DateTime(2026, 4, 10, 10, 0, 0);
      final track = [
        Waypoint(lat: lat, lng: lngBase, timestamp: ts),
        Waypoint(lat: lat, lng: lngBase + 0.0001, timestamp: ts),
      ];
      expect(movingTimeOf(track), Duration.zero);
    });

    test('sums across many fast segments', () {
      // Ten 3-second segments at 3 m/s each → 30s moving
      final track = <Waypoint>[];
      for (var i = 0; i <= 10; i++) {
        track.add(wp(metresEast: i * 9.0, secondsFromStart: i * 3));
      }
      expect(movingTimeOf(track), const Duration(seconds: 30));
    });
  });
}
