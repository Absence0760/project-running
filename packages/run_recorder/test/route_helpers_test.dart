import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

void main() {
  Route route(List<List<double>> latLngs) {
    return Route(
      id: 'test',
      name: 'fixture',
      waypoints: latLngs
          .map((p) => Waypoint(lat: p[0], lng: p[1]))
          .toList(growable: false),
      distanceMetres: 0,
    );
  }

  Waypoint at(double lat, double lng) => Waypoint(lat: lat, lng: lng);

  group('_routeRemaining', () {
    test('returns null when no route is loaded', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      expect(r.debugRouteRemaining(at(0, 0)), isNull);
    });

    test('returns null when the route has fewer than 2 waypoints', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
        ]));
      expect(r.debugRouteRemaining(at(0, 0)), isNull);
    });

    test('at the route start, remaining equals the full route length', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugRouteRemaining(at(0, 0)), closeTo(111.195, 0.5));
    });

    test('at segment midpoint, remaining is the unwalked tail', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0, 0.002],
        ]));
      expect(
        r.debugRouteRemaining(at(0, 0.0005)),
        closeTo(111.195 * 1.5, 1.0),
      );
    });

    test('on the boundary between segments, remaining = total - first leg',
        () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0, 0.002],
        ]));
      expect(r.debugRouteRemaining(at(0, 0.001)), closeTo(111.195, 0.5));
    });

    test('at the route end, remaining is approximately zero', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugRouteRemaining(at(0, 0.001)), closeTo(0, 0.5));
    });

    test('past the route end clamps to zero (t=1 on the last segment)', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugRouteRemaining(at(0, 0.005)), closeTo(0, 0.5));
    });

    test('perpendicular offset projects onto the nearest segment', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0, 0.002],
        ]));
      final remaining = r.debugRouteRemaining(at(0.0001, 0.0005));
      expect(remaining, isNotNull);
      expect(remaining, closeTo(111.195 * 1.5, 1.0));
    });

    test('multi-segment route sums correctly when at start', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0, 0.002],
          [0, 0.003],
        ]));
      expect(r.debugRouteRemaining(at(0, 0)), closeTo(3 * 111.195, 1.0));
    });

    test('remaining never increases around a self-revisiting loop', () {
      // A rectangular loop that finishes back at its start. As the runner
      // comes down the closing (left) edge toward [0,0], the
      // perpendicular-closest segment is the opening edge [0,0]->[0,0.001]
      // already walked at the start, so a non-monotonic search would reset
      // remaining toward the full perimeter. The monotonic floor must keep
      // remaining non-increasing all the way round.
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0.001, 0.001],
          [0.001, 0],
          [0, 0],
        ]));
      final probes = [
        at(0, 0), // start, opening edge
        at(0, 0.0005),
        at(0, 0.001), // first corner
        at(0.0005, 0.001), // top edge
        at(0.001, 0.001), // second corner
        at(0.001, 0.0005), // right edge
        at(0.001, 0), // third corner
        at(0.0005, 0), // closing edge — perpendicular-near the opening edge
        at(0, 0), // back at the finish
      ];
      double? previous;
      for (final p in probes) {
        final remaining = r.debugRouteRemaining(p)!;
        if (previous != null) {
          expect(remaining, lessThanOrEqualTo(previous + 1e-6),
              reason: 'remaining jumped up at (${p.lat}, ${p.lng})');
        }
        previous = remaining;
      }
      // And it has genuinely wound down to ~0 by the finish.
      expect(previous, closeTo(0, 1.0));
    });
  });

  group('_offRouteDistance', () {
    test('returns null when no route is loaded', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      expect(r.debugOffRouteDistance(at(0, 0)), isNull);
    });

    test('returns null when the route has fewer than 2 waypoints', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
        ]));
      expect(r.debugOffRouteDistance(at(0, 0)), isNull);
    });

    test('on a route waypoint returns ~0', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugOffRouteDistance(at(0, 0)), closeTo(0, 0.01));
    });

    test('inline along the route returns ~0', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugOffRouteDistance(at(0, 0.0005)), closeTo(0, 0.01));
    });

    test('perpendicular offset returns the perpendicular distance', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(
        r.debugOffRouteDistance(at(0.0001, 0.0005)),
        closeTo(11.132, 0.05),
      );
    });

    test('past the route end returns distance to the last waypoint', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(
        r.debugOffRouteDistance(at(0, 0.002)),
        closeTo(111.32, 0.5),
      );
    });

    test('multi-segment route picks the closest segment, not the first', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0.001, 0.001],
        ]));
      expect(
        r.debugOffRouteDistance(at(0.0005, 0.001)),
        closeTo(0, 0.05),
      );
    });

    test('zero-length segment is tolerated (degenerate waypoint pair)', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugOffRouteDistance(at(0, 0)), closeTo(0, 0.01));
      expect(
        r.debugOffRouteDistance(at(0.0001, 0)),
        closeTo(11.132, 0.05),
      );
    });
  });

  group('_routeProgress (single-pass)', () {
    test('returns null when no route is loaded', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      expect(r.debugRouteProgress(at(0, 0)), isNull);
    });

    test('equals the separate off-route + remaining calcs across probes', () {
      // A multi-segment out-and-back so the closest segment isn't trivially
      // the first; the combined pass must match the two functions exactly.
      final r = RunRecorder()
        ..debugPrepareWithoutStream(
            route: route([
          [0, 0],
          [0, 0.001],
          [0.001, 0.001],
          [0.001, 0],
          [0.0005, 0],
        ]));
      final probes = [
        at(0, 0),
        at(0.0001, 0.0005),
        at(0.001, 0.0005),
        at(0.0007, 0.0001),
      ];
      for (final p in probes) {
        final prog = r.debugRouteProgress(p)!;
        expect(prog.offRoute, closeTo(r.debugOffRouteDistance(p)!, 1e-6));
        expect(prog.remaining, closeTo(r.debugRouteRemaining(p)!, 1e-6));
      }
    });

    test('O(1) suffix-sum remaining matches the inline sum as the matched '
        'segment advances down a long route', () {
      // A long straight north-bound route (40 segments). The optimized
      // _routeProgress resolves the remaining-route distance from a
      // precomputed suffix array; it must equal the inline per-fix sum
      // (_routeRemaining) at every advancing probe, exercising many distinct
      // suffix indices — the guard against the suffix array drifting from the
      // segment lengths.
      final pts = <List<double>>[];
      for (int i = 0; i <= 40; i++) {
        pts.add([i * 0.001, 0]);
      }
      final r = RunRecorder()..debugPrepareWithoutStream(route: route(pts));
      for (int i = 0; i <= 40; i += 3) {
        final p = at(i * 0.001, 0);
        final prog = r.debugRouteProgress(p)!;
        expect(prog.remaining, closeTo(r.debugRouteRemaining(p)!, 1e-6),
            reason: 'mismatch at waypoint $i');
      }
    });
  });
}
