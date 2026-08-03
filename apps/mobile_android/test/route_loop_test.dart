// Dart port of the parity-helper test suite at
// `apps/web/src/lib/route_loop.test.ts`. The math has had two
// field-reported bugs around degenerate inputs (near-equal
// start/end, NaN target). Keeping the test surface in sync with
// the web side means a regression on either platform fails loud.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../lib/route_loop.dart';
import '../lib/run_stats.dart' show haversineMetres;

void main() {
  // Richmond, VA area — matches the field-bug screenshot used on web.
  const start = LatLng(37.652, -77.3612);

  group('generateLoopWaypoints — loop branch', () {
    test('no end provided returns radial waypoints around start', () {
      final wps = generateLoopWaypoints(
        start: start,
        targetDistanceMetres: 5000,
        radialSeedRad: 0,
      );
      // numPoints (default 4) + start + closing = 6.
      expect(wps.length, 6);
      expect(wps.first.latitude, start.latitude);
      expect(wps.first.longitude, start.longitude);
      expect(wps.last.latitude, start.latitude);
      expect(wps.last.longitude, start.longitude);

      // Interior waypoints lie on a circle of expected radius.
      final expectedRadiusM = (5000 * kDefaultScaleFactor) / (2 * 3.14159265);
      for (var i = 1; i < wps.length - 1; i++) {
        final d = haversineMetres(
          start.latitude,
          start.longitude,
          wps[i].latitude,
          wps[i].longitude,
        );
        expect(
          (d - expectedRadiusM).abs(),
          lessThan(expectedRadiusM * 0.05),
          reason:
              'waypoint $i expected ~${expectedRadiusM}m from start, got ${d}m',
        );
      }
    });

    test('null end is treated as a loop', () {
      final wps = generateLoopWaypoints(
        start: start,
        end: null,
        targetDistanceMetres: 5000,
        radialSeedRad: 0,
      );
      expect(wps.last.latitude, start.latitude);
      expect(wps.last.longitude, start.longitude);
    });

    test('end within kNearPointMetres of start is treated as a loop', () {
      // 11m apart — the field-bug coordinates.
      const end = LatLng(37.6519, -77.3612);
      final dist = haversineMetres(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      expect(dist, lessThan(kNearPointMetres));

      final wps = generateLoopWaypoints(
        start: start,
        end: end,
        targetDistanceMetres: 5000,
        radialSeedRad: 0,
      );
      // Closing waypoint snaps back to start, not the near-equal end.
      expect(wps.last.latitude, start.latitude);
      expect(wps.last.longitude, start.longitude);
    });

    test('radialSeedRad rotates the scaffolding', () {
      // Same target, same start, different seed → different waypoints.
      // Pin so a regression that ignored the seed (and always seeded
      // at angle=0) would fail.
      final wps0 = generateLoopWaypoints(
        start: start,
        targetDistanceMetres: 5000,
        radialSeedRad: 0,
      );
      final wpsPi = generateLoopWaypoints(
        start: start,
        targetDistanceMetres: 5000,
        radialSeedRad: 3.14159265,
      );
      // At seed=π the first interior waypoint is ~opposite the seed=0
      // version (angle shifted by π). Their latitudes should differ
      // by more than the radius if the rotation took effect.
      final dLat = (wps0[1].latitude - wpsPi[1].latitude).abs();
      expect(dLat, greaterThan(0.001));
    });

    test('numPoints=6 emits 8 total waypoints (6 inner + 2 endpoints)', () {
      final wps = generateLoopWaypoints(
        start: start,
        targetDistanceMetres: 5000,
        numPoints: 6,
      );
      expect(wps.length, 8);
    });
  });

  group('generateLoopWaypoints — point-to-point branch', () {
    test('distant end produces a curved point-to-point', () {
      const end = LatLng(37.7, -77.40);
      final wps = generateLoopWaypoints(
        start: start,
        end: end,
        targetDistanceMetres: 10000,
      );
      // numPoints (default 4) + start + end = 6.
      expect(wps.length, 6);
      expect(wps.first.latitude, start.latitude);
      expect(wps.last.latitude, end.latitude);
      expect(wps.last.longitude, end.longitude);
    });

    test('curve makes the route longer than the straight-line', () {
      // The whole point of the perpendicular offset: the snaked path
      // should be longer than the direct chord. Sum the segment
      // lengths and verify they exceed the direct distance.
      const end = LatLng(37.7, -77.40);
      final wps = generateLoopWaypoints(
        start: start,
        end: end,
        targetDistanceMetres: 20000,
      );
      var pathLen = 0.0;
      for (var i = 1; i < wps.length; i++) {
        pathLen += haversineMetres(
          wps[i - 1].latitude,
          wps[i - 1].longitude,
          wps[i].latitude,
          wps[i].longitude,
        );
      }
      final directDist = haversineMetres(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      expect(pathLen, greaterThan(directDist));
    });

    test('point-to-point across the antimeridian keeps the curve local', () {
      // ~1.9 km apart, across 180°. The raw longitude delta read
      // -359.98°, which flung the interior waypoints thousands of km
      // away (and, in a debug build, tripped LatLng's range assert).
      const p2pStart = LatLng(38.9, 179.99);
      const p2pEnd = LatLng(38.9, -179.99);
      final wps = generateLoopWaypoints(
        start: p2pStart,
        end: p2pEnd,
        targetDistanceMetres: 5000,
      );
      expect(wps.first.longitude, p2pStart.longitude);
      expect(wps.last.longitude, p2pEnd.longitude);
      for (final w in wps) {
        expect(w.longitude, inInclusiveRange(-180, 180));
        final d = haversineMetres(
          p2pStart.latitude,
          p2pStart.longitude,
          w.latitude,
          w.longitude,
        );
        expect(d, lessThan(10000), reason: 'waypoint flung ${d.round()}m');
      }
    });

    test('a loop seeded beside the antimeridian emits in-range longitudes', () {
      const loopStart = LatLng(38.9, 179.9999);
      final wps = generateLoopWaypoints(
        start: loopStart,
        targetDistanceMetres: 5000,
        radialSeedRad: 0,
      );
      final expectedRadiusM = (5000 * kDefaultScaleFactor) / (2 * math.pi);
      for (final w in wps) {
        expect(w.longitude, inInclusiveRange(-180, 180));
      }
      for (var i = 1; i < wps.length - 1; i++) {
        final d = haversineMetres(
          loopStart.latitude,
          loopStart.longitude,
          wps[i].latitude,
          wps[i].longitude,
        );
        expect(
          (d - expectedRadiusM).abs(),
          lessThan(expectedRadiusM * 0.05),
          reason: 'waypoint $i expected ~${expectedRadiusM}m, got ${d}m',
        );
      }
    });
  });

  group('bisectScale', () {
    test('actual > target narrows the upper bound + picks midpoint', () {
      final r = bisectScale(
        range: initScaleRange(),
        currentScale: 1.0,
        targetDistanceMetres: 5000,
        actualDistanceMetres: 6000,
      );
      // upper was 2, now capped at currentScale=1 → next is mid of
      // [0.05, 1] = 0.525.
      expect(r.range.upper, 1.0);
      expect(r.scale, closeTo(0.525, 0.001));
    });

    test('actual < target narrows the lower bound', () {
      final r = bisectScale(
        range: initScaleRange(),
        currentScale: 0.5,
        targetDistanceMetres: 5000,
        actualDistanceMetres: 3000,
      );
      // lower was 0.05, now raised to currentScale=0.5 → next is mid
      // of [0.5, 2] = 1.25.
      expect(r.range.lower, 0.5);
      expect(r.scale, closeTo(1.25, 0.001));
    });

    test('clamps next scale within [kScaleFactorMin, kScaleFactorMax]', () {
      // Defensive: even if the bracket would compute outside the
      // bounds, the next scale stays inside.
      final r = bisectScale(
        range: const ScaleRange(0.01, 0.04),
        currentScale: 0.01,
        targetDistanceMetres: 5000,
        actualDistanceMetres: 4000,
      );
      expect(r.scale, greaterThanOrEqualTo(kScaleFactorMin));
      expect(r.scale, lessThanOrEqualTo(kScaleFactorMax));
    });
  });

  group('isWithinAcceptBand', () {
    test('target 5000 / actual 5000 is within band', () {
      expect(
        isWithinAcceptBand(
          targetDistanceMetres: 5000,
          actualDistanceMetres: 5000,
        ),
        isTrue,
      );
    });

    test('target 5000 / actual 6000 (5/6 = 0.83) is BELOW band', () {
      expect(
        isWithinAcceptBand(
          targetDistanceMetres: 5000,
          actualDistanceMetres: 6000,
        ),
        isFalse,
      );
    });

    test('target 5000 / actual 4500 (5/4.5 = 1.11) is within band', () {
      expect(
        isWithinAcceptBand(
          targetDistanceMetres: 5000,
          actualDistanceMetres: 4500,
        ),
        isTrue,
      );
    });

    test('zero actual is never accepted (defensive)', () {
      expect(
        isWithinAcceptBand(
          targetDistanceMetres: 5000,
          actualDistanceMetres: 0,
        ),
        isFalse,
      );
    });
  });

  group('isValidTargetDistance', () {
    test('null / NaN / Infinity / non-positive / over-cap all rejected', () {
      expect(isValidTargetDistance(null), isFalse);
      expect(isValidTargetDistance(double.nan), isFalse);
      expect(isValidTargetDistance(double.infinity), isFalse);
      expect(isValidTargetDistance(0), isFalse);
      expect(isValidTargetDistance(-100), isFalse);
      expect(isValidTargetDistance(kMaxTargetDistanceMetres + 1), isFalse);
    });

    test('typical run distances are accepted', () {
      expect(isValidTargetDistance(5000), isTrue);
      expect(isValidTargetDistance(42195), isTrue);
      expect(isValidTargetDistance(kMaxTargetDistanceMetres), isTrue);
    });
  });

  group('selectLoopAnchors', () {
    test('emits start + 2 midpoints + close for a 10-point polyline', () {
      final poly = [
        for (var i = 0; i < 10; i++) LatLng(37.6 + i * 0.001, -77.4),
      ];
      final close = const LatLng(37.6, -77.4);
      final anchors = selectLoopAnchors(
        polyline: poly,
        start: start,
        close: close,
      );
      // start + mid1 + mid2 + close = 4
      expect(anchors.length, 4);
      expect(anchors.first.latitude, start.latitude);
      expect(anchors.last.latitude, close.latitude);
    });

    test('emits start + close only for a degenerate <4-point polyline', () {
      final poly = [
        const LatLng(37.6, -77.4),
        const LatLng(37.61, -77.4),
      ];
      final close = const LatLng(37.6, -77.4);
      final anchors = selectLoopAnchors(
        polyline: poly,
        start: start,
        close: close,
      );
      expect(anchors.length, 2);
      expect(anchors.first.latitude, start.latitude);
      expect(anchors.last.latitude, close.latitude);
    });
  });
}
