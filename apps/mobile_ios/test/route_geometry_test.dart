import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter_test/flutter_test.dart';

import '../lib/route_geometry.dart';

/// Pure-helper coverage for `interpolateAlongRoute` — the math that
/// drives the route-detail screen's scrubber. Drag the slider 0 → 1
/// and this helper produces the lat/lng for the runner pulse so the
/// user can preview the direction of the route step-by-step.
///
/// All test routes anchor at lat=0 so equirectangular projection
/// math (cos(lat) = 1) makes the haversine + linear interpolation
/// predictable to a sub-metre precision.
void main() {
  // 1° longitude at the equator ≈ 111 320 m. Useful for converting
  // metres ↔ longitude in tests where lat = 0.
  const metresPerDegLngAtEquator = 111320.0;

  Waypoint wp(double lat, double lng) => Waypoint(lat: lat, lng: lng);

  group('interpolateAlongRoute — guard rails', () {
    test('null on empty waypoints', () {
      expect(interpolateAlongRoute(const [], 0.5), isNull);
    });

    test('null on single waypoint', () {
      expect(
        interpolateAlongRoute([wp(0, 0)], 0.5),
        isNull,
        reason: 'A single point isn\'t a polyline — nothing to '
            'interpolate. Caller (route_detail screen) hides the '
            'scrubber entirely when waypoints.length < 2.',
      );
    });

    test(
        'all-coincident waypoints (degenerate, zero total length) '
        'snap to the first waypoint',
        () {
      // Defence-in-depth: the route builder\'s 5 m dedupe should
      // make this impossible in practice, but if it ever surfaces
      // we return a valid answer rather than dividing by zero.
      final out = interpolateAlongRoute(
        [wp(1, 1), wp(1, 1), wp(1, 1)],
        0.5,
      );
      expect(out, isNotNull);
      expect(out!.lat, 1);
      expect(out.lng, 1);
    });

    test('fraction below 0 clamps to start', () {
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, 0.001)],
        -1.0,
      );
      expect(out!.lng, closeTo(0.0, 1e-9));
    });

    test('fraction above 1 clamps to end', () {
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, 0.001)],
        2.0,
      );
      expect(out!.lng, closeTo(0.001, 1e-9));
    });
  });

  group('interpolateAlongRoute — fraction → position', () {
    test('fraction = 0.0 returns the start waypoint exactly', () {
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, 0.005), wp(0, 0.010)],
        0.0,
      );
      expect(out!.lat, 0);
      expect(out.lng, closeTo(0, 1e-9));
    });

    test('fraction = 1.0 returns the end waypoint exactly', () {
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, 0.005), wp(0, 0.010)],
        1.0,
      );
      expect(out!.lat, 0);
      expect(out.lng, closeTo(0.010, 1e-9));
    });

    test('fraction = 0.5 on an even-spaced polyline lands at midpoint',
        () {
      // Two segments of equal length → fraction 0.5 lands exactly at
      // the middle waypoint.
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, 0.005), wp(0, 0.010)],
        0.5,
      );
      expect(out!.lng, closeTo(0.005, 1e-6));
    });

    test('distance-weighted — long-segment dominates the scrub range',
        () {
      // Two segments: short (1 unit) + long (9 units). Fraction 0.5
      // of total distance (5 units) lands INSIDE the long segment
      // — NOT at the corner waypoint — proving distance-weighted
      // interpolation. A naive index-based interpolation would
      // mistakenly snap to the corner here.
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, 0.001), wp(0, 0.010)],
        0.5,
      );
      // 50% of total 10-unit distance = position 5 → 4 units into
      // the long second segment → lng ≈ 0.001 + (4/9 * 0.009) ≈ 0.005.
      expect(out!.lng, closeTo(0.005, 1e-6));
    });

    test('fraction = 0.25 on a 4-equal-leg polyline lands at 1st corner',
        () {
      // Four equal segments, fraction 0.25 lands exactly at the
      // first interior waypoint (3 corners + start + end = 4 legs).
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, 0.001), wp(0, 0.002), wp(0, 0.003), wp(0, 0.004)],
        0.25,
      );
      expect(out!.lng, closeTo(0.001, 1e-6));
    });

    test('non-monotonic / out-and-back polyline interpolates by path '
        'distance, not chord', () {
      // Out + back along the same axis. Path distance: 2 units.
      // Fraction 0.5 lands at the "turn-around" point, NOT the
      // chord midpoint (which would be back at the start).
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, 0.001), wp(0, 0)],
        0.5,
      );
      expect(
        out!.lng,
        closeTo(0.001, 1e-6),
        reason: 'Path-distance interpolation: the runner has '
            'reached the turn-around halfway through an out-and-back, '
            'NOT averaged to the chord midpoint (which would erase '
            'the loop entirely).',
      );
    });
  });

  group('interpolateAlongRoute — elevation lerp', () {
    test('elevation interpolates linearly between adjacent waypoints',
        () {
      final out = interpolateAlongRoute(
        [
          Waypoint(lat: 0, lng: 0, elevationMetres: 100),
          Waypoint(lat: 0, lng: 0.001, elevationMetres: 200),
        ],
        0.5,
      );
      expect(
        out!.elevationMetres,
        closeTo(150, 0.01),
        reason: 'Halfway between 100 m and 200 m elevation should '
            'lerp to 150 m so the marker\'s tooltip / readout can '
            'show smooth elevation as the user drags.',
      );
    });

    test('elevation lerp tolerates one-sided null (a/null or null/b)',
        () {
      // Only the END waypoint carries elevation — interpolation
      // returns the populated value rather than crashing.
      final out = interpolateAlongRoute(
        [
          Waypoint(lat: 0, lng: 0),
          Waypoint(lat: 0, lng: 0.001, elevationMetres: 50),
        ],
        0.5,
      );
      expect(out!.elevationMetres, 50);
    });

    test('elevation lerp returns null when both sides are null', () {
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, 0.001)],
        0.5,
      );
      expect(out!.elevationMetres, isNull);
    });
  });

  group('polylineLengthMetres', () {
    test('empty / single-point polyline → 0', () {
      expect(polylineLengthMetres(const []), 0);
      expect(polylineLengthMetres([wp(0, 0)]), 0);
    });

    test('single 100-m segment → roughly 100 m at the equator', () {
      // 100 m / 111 320 m/° ≈ 8.98e-4° of longitude.
      final out = polylineLengthMetres([
        wp(0, 0),
        wp(0, 100 / metresPerDegLngAtEquator),
      ]);
      expect(out, closeTo(100, 1));
    });

    test('multi-segment lengths sum', () {
      // Two 100-m segments → 200 m total.
      final step = 100 / metresPerDegLngAtEquator;
      final out = polylineLengthMetres([
        wp(0, 0),
        wp(0, step),
        wp(0, 2 * step),
      ]);
      expect(out, closeTo(200, 1));
    });
  });

  group('interpolateAlongRoute — geographic + edge cases', () {
    test('southern-hemisphere polyline interpolates symmetrically '
        'to a northern-hemisphere mirror', () {
      // Pin that the helper isn\'t accidentally relying on a
      // positive-lat assumption (e.g. a sign error in the haversine).
      // South-of-equator interp at fraction=0.5 lands at -0.005°
      // exactly, mirroring the north case.
      final southOut = interpolateAlongRoute(
        [wp(0, 0), wp(-0.005, 0), wp(-0.010, 0)],
        0.5,
      );
      expect(southOut!.lat, closeTo(-0.005, 1e-6));
      expect(southOut.lng, 0);
    });

    test(
        'eastern + western longitude interp is symmetric (negative-lng safe)',
        () {
      // Same defence for negative longitudes — e.g. polylines in
      // the Americas. fraction=0.5 of [0,-0.010] → -0.005.
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, -0.005), wp(0, -0.010)],
        0.5,
      );
      expect(out!.lng, closeTo(-0.005, 1e-6));
    });

    test('2-waypoint polyline at fraction = 0.5 lands exactly at midpoint',
        () {
      // Minimal valid input — the scrubber should still work on a
      // 2-pin route (the route builder\'s minimum-renderable state).
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, 0.010)],
        0.5,
      );
      expect(out!.lng, closeTo(0.005, 1e-6));
    });

    test(
        'segments of zero length are skipped — adjacent duplicate '
        'waypoints don\'t poison interpolation',
        () {
      // After the 5-m dedupe guard fires in route_builder, a saved
      // route should never carry exact duplicates. But defensively
      // — if it does, the helper must skip the zero-length leg
      // (segLen <= 0 continue) and continue into the next real
      // segment. Otherwise fraction=0.5 on [(0,0), (0,0), (0,0.01)]
      // would return (0,0) (incorrect).
      final out = interpolateAlongRoute(
        [wp(0, 0), wp(0, 0), wp(0, 0.010)],
        0.5,
      );
      expect(
        out!.lng,
        closeTo(0.005, 1e-6),
        reason: 'Helper must skip the zero-length first leg and '
            'land at the midpoint of the real 0→0.010 leg.',
      );
    });

    test(
        'long polyline (200 waypoints) is O(n) — runs under 50 ms',
        () {
      // The recorder + route builder produce polylines bounded by
      // ~1000 points; pin the helper at 200 to catch a quadratic
      // regression early.
      final wps = [
        for (var i = 0; i <= 200; i++) wp(0, i * 0.0001),
      ];
      final sw = Stopwatch()..start();
      final out = interpolateAlongRoute(wps, 0.5);
      sw.stop();
      expect(out, isNotNull);
      expect(
        sw.elapsedMilliseconds,
        lessThan(50),
        reason: 'Linear scan over 200 points must finish well under '
            '50 ms — pin against a quadratic refactor.',
      );
    });
  });
}
