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

  group('fastestWindowOf', () {
    const lat = 47.37;
    const lngBase = 8.54;
    final metrePerDeg = 111320 * 0.6773;

    Waypoint wp({
      required double metresEast,
      required int secondsFromStart,
    }) {
      final lng = lngBase + metresEast / metrePerDeg;
      return Waypoint(
        lat: lat,
        lng: lng,
        timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
      );
    }

    test('returns null for empty or short tracks', () {
      expect(fastestWindowOf(const [], 5000), isNull);
      expect(
        fastestWindowOf([wp(metresEast: 0, secondsFromStart: 0)], 5000),
        isNull,
      );
    });

    test('returns null when track covers less than the window', () {
      // 4 km straight line in 20 min — not enough for a 5 km window.
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 4000, secondsFromStart: 20 * 60),
      ];
      expect(fastestWindowOf(track, 5000), isNull);
    });

    test('even-paced 10 km gives half-time for fastest 5 km', () {
      // 10 km in 50:00 at constant pace — fastest 5 km must be 25:00.
      // Use 50 waypoints at 200 m apart, 60 s apart.
      final track = <Waypoint>[
        for (var i = 0; i <= 50; i++)
          wp(metresEast: i * 200.0, secondsFromStart: i * 60),
      ];
      final best = fastestWindowOf(track, 5000);
      expect(best, isNotNull);
      // Allow 1-second interpolation slack.
      expect(best!.inSeconds, closeTo(25 * 60, 1));
    });

    test('picks the fast middle 5 km out of a slow → fast → slow run', () {
      // 3 km warmup at 300 s/km (slow)
      // 5 km fast at 240 s/km (the PB window)
      // 3 km cooldown at 300 s/km
      // 11 km total. Best 5k should be 1200 s = 20:00.
      final track = <Waypoint>[];
      var distance = 0.0;
      var seconds = 0;
      track.add(wp(metresEast: distance, secondsFromStart: seconds));

      // 3 km warmup: 30 segments of 100 m at 30 s each
      for (var i = 0; i < 30; i++) {
        distance += 100;
        seconds += 30;
        track.add(wp(metresEast: distance, secondsFromStart: seconds));
      }
      // 5 km fast: 50 segments of 100 m at 24 s each
      for (var i = 0; i < 50; i++) {
        distance += 100;
        seconds += 24;
        track.add(wp(metresEast: distance, secondsFromStart: seconds));
      }
      // 3 km cooldown: 30 segments of 100 m at 30 s each
      for (var i = 0; i < 30; i++) {
        distance += 100;
        seconds += 30;
        track.add(wp(metresEast: distance, secondsFromStart: seconds));
      }

      final best = fastestWindowOf(track, 5000);
      expect(best, isNotNull);
      expect(best!.inSeconds, closeTo(20 * 60, 2));
    });

    test('does not project: a 10 km at even pace stays at its real 5k time', () {
      // Regression for the "Fastest 5k" scaled-pace bug. A 10 km in
      // 1:14:34 (4474 s) at perfectly even pace → fastest 5 km is 37:17.
      // Build 100 segments of 100 m each, total 4474 s.
      final track = <Waypoint>[
        for (var i = 0; i <= 100; i++)
          wp(
            metresEast: i * 100.0,
            secondsFromStart: (i * 4474 / 100).round(),
          ),
      ];
      final best = fastestWindowOf(track, 5000);
      expect(best, isNotNull);
      // 37:17 ± small interpolation slack
      expect(best!.inSeconds, closeTo(2237, 2));
    });
  });
}
