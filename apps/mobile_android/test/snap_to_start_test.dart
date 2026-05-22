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

  group('isTooCloseToOtherWaypoints', () {
    test('empty existing list — never too close', () {
      expect(
        isTooCloseToOtherWaypoints(
          candidate: _w(0),
          existing: const [],
        ),
        isFalse,
      );
    });

    test('exact duplicate position is rejected', () {
      // Fat-finger same-spot tap: zero distance to the existing
      // waypoint, well under the 5 m threshold.
      expect(
        isTooCloseToOtherWaypoints(
          candidate: _w(0),
          existing: [_w(0)],
        ),
        isTrue,
      );
    });

    test('within the 5 m default tolerance is rejected', () {
      // A tap 3 m off an existing waypoint — visually distinct on
      // a phone screen but well below the smallest meaningful
      // OSRM edge.
      expect(
        isTooCloseToOtherWaypoints(
          candidate: _w(3),
          existing: [_w(0)],
        ),
        isTrue,
      );
    });

    test('just above the threshold is allowed (≥6 m clears the gate)', () {
      // Haversine + lng conversion both involve FP rounding, so
      // "exactly 5 m" varies by ~10⁻³ between construction and
      // round-trip — we use 6 m as the smallest unambiguous "above
      // threshold" value. Pin so a future sloppy `<=` change that
      // promotes 5 m exactly to "rejected" still gets caught here.
      expect(
        isTooCloseToOtherWaypoints(
          candidate: _w(6),
          existing: [_w(0)],
        ),
        isFalse,
      );
    });

    test('clearly distinct placements (≥10 m) are allowed', () {
      expect(
        isTooCloseToOtherWaypoints(
          candidate: _w(10),
          existing: [_w(0)],
        ),
        isFalse,
      );
      expect(
        isTooCloseToOtherWaypoints(
          candidate: _w(50),
          existing: [_w(0)],
        ),
        isFalse,
      );
    });

    test('check fires across ANY existing waypoint, not just neighbours',
        () {
      // The candidate is far from existing[0] (the start) and far
      // from existing[1] but close to existing[2]. Must still
      // reject — the OSRM segment to existing[2] would be the
      // problem.
      expect(
        isTooCloseToOtherWaypoints(
          candidate: _w(498),
          existing: [_w(0), _w(200), _w(500)],
        ),
        isTrue,
      );
    });

    test(
        'excludeIndex skips the waypoint being dragged — '
        'a drag landing back on its own spot is fine',
        () {
      // Drag handler: existing[1] is the waypoint being moved.
      // The "moved" position lands back on existing[1] itself —
      // that should be OK (the drag is essentially a no-op),
      // because the check excludes the source index.
      expect(
        isTooCloseToOtherWaypoints(
          candidate: _w(200),
          existing: [_w(0), _w(200), _w(500)],
          excludeIndex: 1,
        ),
        isFalse,
      );
    });

    test(
        'excludeIndex does NOT skip other waypoints — a drag '
        'onto a NEIGHBOUR is still rejected',
        () {
      // Drag handler: existing[1] being moved, but moved position
      // is right on existing[0] (the start). Must reject — the
      // excludeIndex only excludes the source pin, not others.
      expect(
        isTooCloseToOtherWaypoints(
          candidate: _w(2),
          existing: [_w(0), _w(200), _w(500)],
          excludeIndex: 1,
        ),
        isTrue,
        reason: 'Dragging waypoint #1 onto waypoint #0 must reject — '
            'excludeIndex only spares the source.',
      );
    });

    test('custom toleranceM overrides the default', () {
      // 8 m candidate against the default 5 m threshold — allowed.
      // Against a 10 m custom threshold — rejected.
      expect(
        isTooCloseToOtherWaypoints(
          candidate: _w(8),
          existing: [_w(0)],
        ),
        isFalse,
      );
      expect(
        isTooCloseToOtherWaypoints(
          candidate: _w(8),
          existing: [_w(0)],
          toleranceM: 10,
        ),
        isTrue,
      );
    });

    test('kMinWaypointSpacingM constant is pinned at 5 m', () {
      // The 5 m default is documented in source. Pin so a sloppy
      // refactor doesn\'t silently widen it (which would block
      // legitimate close placements) or tighten it (which would
      // let degenerate near-duplicates through).
      expect(kMinWaypointSpacingM, 5);
    });
  });
}
