import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/snap_to_start.dart';

const _lat = 47.37;
const _metrePerDegLng = 111320 * 0.6773;

Waypoint _w(double metresEast) => Waypoint(
      lat: _lat,
      lng: 8.54 + metresEast / _metrePerDegLng,
    );

void main() {
  group('shouldSnapToStart', () {
    test('false when fewer than three existing waypoints', () {
      // No history → no loop to close.
      expect(
        shouldSnapToStart(tap: _w(0), existingWaypoints: const []),
        isFalse,
      );
      expect(
        shouldSnapToStart(tap: _w(0), existingWaypoints: [_w(0)]),
        isFalse,
      );
      expect(
        shouldSnapToStart(tap: _w(0), existingWaypoints: [_w(0), _w(100)]),
        isFalse,
      );
    });

    test('true when tap is within tolerance of the start (3+ waypoints)',
        () {
      // Three waypoints, tap is back near the start.
      final wps = [_w(0), _w(200), _w(400)];
      expect(
        shouldSnapToStart(tap: _w(5), existingWaypoints: wps),
        isTrue,
      );
    });

    test('false when tap is just outside the tolerance budget', () {
      final wps = [_w(0), _w(200), _w(400)];
      expect(
        shouldSnapToStart(tap: _w(100), existingWaypoints: wps),
        isFalse,
        reason: '100 m east of start is well outside the 30 m budget',
      );
    });

    test('false when tap is exactly at the start but the route is too short',
        () {
      // 2 waypoints + start-tap → no snap (would just append at index 2,
      // not close a loop).
      final wps = [_w(0), _w(200)];
      expect(
        shouldSnapToStart(tap: _w(0), existingWaypoints: wps),
        isFalse,
      );
    });

    test('respects a custom tolerance', () {
      final wps = [_w(0), _w(200), _w(400)];
      // 50 m east — outside default 30, inside custom 60.
      expect(
        shouldSnapToStart(tap: _w(50), existingWaypoints: wps),
        isFalse,
      );
      expect(
        shouldSnapToStart(
          tap: _w(50),
          existingWaypoints: wps,
          toleranceM: 60,
        ),
        isTrue,
      );
    });
  });
}
