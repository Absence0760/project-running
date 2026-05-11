import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/ghost_pacer.dart';

// Zürich-area coordinates with a known metre-per-degree scaling so
// the assertions can use easy round numbers. 1 m east at lat 47.37 is
// 1 / (111320 × cos(47.37°)) ≈ 1.3261e-5 degrees of longitude.
const lat = 47.37;
const _metrePerDegLng = 111320 * 0.6773;

Waypoint _wp(double metresEast) => Waypoint(
      lat: lat,
      lng: 8.54 + metresEast / _metrePerDegLng,
    );

void main() {
  group('ghostPacerPosition', () {
    test('returns null when path has fewer than two waypoints', () {
      expect(
        ghostPacerPosition(
          path: const <Waypoint>[],
          elapsed: const Duration(seconds: 30),
          targetPaceSecPerKm: 360,
        ),
        isNull,
      );
      expect(
        ghostPacerPosition(
          path: [_wp(0)],
          elapsed: const Duration(seconds: 30),
          targetPaceSecPerKm: 360,
        ),
        isNull,
      );
    });

    test('returns null when elapsed is zero or negative', () {
      final path = [_wp(0), _wp(1000)];
      expect(
        ghostPacerPosition(
          path: path,
          elapsed: Duration.zero,
          targetPaceSecPerKm: 360,
        ),
        isNull,
      );
      expect(
        ghostPacerPosition(
          path: path,
          elapsed: const Duration(seconds: -5),
          targetPaceSecPerKm: 360,
        ),
        isNull,
      );
    });

    test('returns null when targetPaceSecPerKm is zero or negative', () {
      final path = [_wp(0), _wp(1000)];
      expect(
        ghostPacerPosition(
          path: path,
          elapsed: const Duration(seconds: 30),
          targetPaceSecPerKm: 0,
        ),
        isNull,
      );
      expect(
        ghostPacerPosition(
          path: path,
          elapsed: const Duration(seconds: 30),
          targetPaceSecPerKm: -100,
        ),
        isNull,
      );
    });

    test('returns null when the ghost runs off the end of the path', () {
      // 100 m path; ghost at 6:00/km (~ 2.78 m/s) covers ~83 m in 30 s.
      // Stretch elapsed to 60 s → 167 m, past the 100 m end.
      final path = [_wp(0), _wp(100)];
      expect(
        ghostPacerPosition(
          path: path,
          elapsed: const Duration(seconds: 60),
          targetPaceSecPerKm: 360,
        ),
        isNull,
        reason: 'caller should hide the marker rather than pin it to '
            'path.last for the rest of the step',
      );
    });

    test('positions the ghost halfway down a single 1 km segment after '
        '3 min @ 6:00/km', () {
      // 6:00/km = 360 s/km → after 180 s the ghost covers 500 m.
      final path = [_wp(0), _wp(1000)];
      final ghost = ghostPacerPosition(
        path: path,
        elapsed: const Duration(seconds: 180),
        targetPaceSecPerKm: 360,
      );
      expect(ghost, isNotNull);
      // Latitude unchanged (we only moved east).
      expect(ghost!.lat, closeTo(lat, 1e-12));
      // 500 m east of path[0].
      final expectedLng = 8.54 + 500 / _metrePerDegLng;
      expect(ghost.lng, closeTo(expectedLng, 1e-6));
    });

    test('walks across a segment boundary when the target sits in the '
        'second leg', () {
      // Three-waypoint path of 200 m segments (total 600 m).
      final path = [_wp(0), _wp(200), _wp(400), _wp(600)];
      // 5:00/km = 300 s/km → 100 s covers 333.33 m, which is 133.33 m
      // into the second segment (path[1] → path[2]).
      final ghost = ghostPacerPosition(
        path: path,
        elapsed: const Duration(seconds: 100),
        targetPaceSecPerKm: 300,
      );
      expect(ghost, isNotNull);
      expect(ghost!.lat, closeTo(lat, 1e-12));
      // ~333.33 m east of path[0].
      final expectedLng = 8.54 + 333.333 / _metrePerDegLng;
      expect(ghost.lng, closeTo(expectedLng, 5e-6));
    });

    test('lands exactly on the second waypoint when target == segment '
        'length', () {
      // 4:00/km × 60 s = 250 m. Three 250-m segments → ghost on path[1].
      final path = [_wp(0), _wp(250), _wp(500), _wp(750)];
      final ghost = ghostPacerPosition(
        path: path,
        elapsed: const Duration(seconds: 60),
        targetPaceSecPerKm: 240,
      );
      expect(ghost, isNotNull);
      final expectedLng = 8.54 + 250 / _metrePerDegLng;
      expect(ghost!.lng, closeTo(expectedLng, 1e-6));
    });

    test('coincident consecutive waypoints in the middle of the path '
        'do not break the walk', () {
      // Defensive — a recorded route with two stacked points (rare but
      // possible) shouldn't divide by zero.
      final path = [_wp(0), _wp(100), _wp(100), _wp(500)];
      final ghost = ghostPacerPosition(
        path: path,
        // 300 s/km × 30 s = 100 m → lands exactly at the duplicate.
        elapsed: const Duration(seconds: 30),
        targetPaceSecPerKm: 300,
      );
      expect(ghost, isNotNull);
      // Should be at 100 m east — interpolating through coincident
      // points yields the same lat/lng either way.
      final expectedLng = 8.54 + 100 / _metrePerDegLng;
      expect(ghost!.lng, closeTo(expectedLng, 1e-6));
    });

    test('returns a position with only lat + lng (no ele / ts / bpm)',
        () {
      final path = [
        Waypoint(
          lat: lat,
          lng: 8.54,
          elevationMetres: 400,
          timestamp: DateTime(2026, 5, 11),
          bpm: 150,
        ),
        Waypoint(
          lat: lat,
          lng: 8.55,
          elevationMetres: 410,
          timestamp: DateTime(2026, 5, 11, 0, 1),
          bpm: 160,
        ),
      ];
      final ghost = ghostPacerPosition(
        path: path,
        elapsed: const Duration(seconds: 30),
        targetPaceSecPerKm: 360,
      );
      expect(ghost, isNotNull);
      expect(ghost!.elevationMetres, isNull,
          reason: 'ghost is a virtual marker, not a sample — ele '
              'must not be carried over from the source waypoints');
      expect(ghost.timestamp, isNull);
      expect(ghost.bpm, isNull);
    });
  });
}
