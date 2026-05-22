import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter_test/flutter_test.dart';

import '../lib/routing.dart';

/// Capture-only fetcher — records the URL it was called with and
/// returns a canned body.
class _StubFetcher {
  final String body;
  Uri? lastUrl;
  int callCount = 0;
  _StubFetcher(this.body);

  Future<String> call(Uri url) async {
    lastUrl = url;
    callCount++;
    return body;
  }
}

void main() {
  group('snapToRoad', () {
    test('returns the snapped lat/lng on a successful response', () async {
      final stub = _StubFetcher(jsonEncode({
        'code': 'Ok',
        'waypoints': [
          {
            'location': [8.5418, 47.3768],
          },
        ],
      }));
      final snapped = await snapToRoad(
        const Waypoint(lat: 47.37, lng: 8.54),
        fetcher: stub.call,
      );
      expect(snapped.lat, closeTo(47.3768, 1e-9));
      expect(snapped.lng, closeTo(8.5418, 1e-9));
      // URL should hit /nearest/v1/foot/<lng>,<lat>.
      expect(stub.lastUrl!.path, '/nearest/v1/foot/8.54,47.37');
    });

    test('falls back to the input point when OSRM returns non-Ok', () async {
      final stub = _StubFetcher(jsonEncode({
        'code': 'NoSegment',
        'waypoints': null,
      }));
      const input = Waypoint(lat: 47.37, lng: 8.54);
      final snapped = await snapToRoad(input, fetcher: stub.call);
      expect(snapped.lat, input.lat);
      expect(snapped.lng, input.lng);
    });

    test('falls back to the input point when the fetcher throws', () async {
      Future<String> bomb(Uri url) async {
        throw StateError('network down');
      }

      const input = Waypoint(lat: 47.37, lng: 8.54);
      final snapped = await snapToRoad(input, fetcher: bomb);
      expect(snapped.lat, input.lat);
      expect(snapped.lng, input.lng);
    });

    test('uses /car path when profile is OsrmProfile.car', () async {
      final stub = _StubFetcher(jsonEncode({
        'code': 'Ok',
        'waypoints': [
          {
            'location': [8.0, 47.0],
          },
        ],
      }));
      await snapToRoad(
        const Waypoint(lat: 47.0, lng: 8.0),
        profile: OsrmProfile.car,
        fetcher: stub.call,
      );
      expect(stub.lastUrl!.path, contains('/car/'));
    });

    test('builds the URL with number=1 + radiuses=250 query params', () async {
      // Web-parity accuracy fix. Without `radiuses=` OSRM is free
      // to reach unbounded distance to find a road — a tap on a
      // stream / parking lot / private drive snaps to a road
      // 800m+ away. Pinned at 250 m to match
      // `apps/web/src/lib/routing_quality.ts:OSRM_SNAP_RADIUS_M`.
      final stub = _StubFetcher(jsonEncode({
        'code': 'Ok',
        'waypoints': [{'location': [8.5, 47.5]}],
      }));
      await snapToRoad(
        const Waypoint(lat: 47.0, lng: 8.0),
        fetcher: stub.call,
      );
      expect(stub.lastUrl!.queryParameters['number'], '1',
          reason: 'number=1 requests only the single nearest match — '
              'matches web `RouteBuilder.svelte` call shape.');
      expect(stub.lastUrl!.queryParameters['radiuses'], '500',
          reason: 'radiuses=500 caps OSRM snap distance — bumped '
              'from 250 m per user feedback that the tighter cap '
              'was too restrictive in rural / sparsely-mapped '
              'regions. 500 m still rejects absurd >1 km snaps.');
    });

    test('falls back to the input point when the fetcher exceeds '
        'kOsrmSnapTimeout', () async {
      // Stub that never resolves — without the inner .timeout() this
      // would hang the route-builder iteration forever. With it, the
      // catch-all in snapToRoad swallows TimeoutException and returns
      // the original point so the caller can fall through.
      Future<String> hangingFetcher(Uri _) async {
        await Future<void>.delayed(const Duration(seconds: 30));
        return '{}';
      }

      const input = Waypoint(lat: 47.37, lng: 8.54);
      final out = await snapToRoad(
        input,
        fetcher: hangingFetcher,
      ).timeout(
        // Outer guard so a regression doesn't have to wait the full
        // 30s before flutter_test kills the run.
        const Duration(seconds: 9),
        onTimeout: () => fail('snapToRoad did not honour kOsrmSnapTimeout'),
      );
      expect(out, input);
    });
  });

  group('fetchRouteThrough', () {
    test('returns empty result for fewer than two points', () async {
      final none = await fetchRouteThrough(
        const [],
        fetcher: (_) async => fail('fetcher must not be called'),
      );
      expect(none.coordinates, isEmpty);
      expect(none.distanceMetres, 0);

      final one = await fetchRouteThrough(
        const [Waypoint(lat: 47.37, lng: 8.54)],
        fetcher: (_) async => fail('fetcher must not be called'),
      );
      expect(one.coordinates, isEmpty);
    });

    test('parses the routes[0].geometry + distance', () async {
      final stub = _StubFetcher(jsonEncode({
        'code': 'Ok',
        'routes': [
          {
            'distance': 1234.5,
            'geometry': {
              'coordinates': [
                [8.54, 47.37],
                [8.541, 47.371],
                [8.542, 47.372],
              ],
            },
          },
        ],
      }));
      final result = await fetchRouteThrough(
        const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.372, lng: 8.542),
        ],
        fetcher: stub.call,
      );
      expect(result.distanceMetres, 1234.5);
      expect(result.coordinates, hasLength(3));
      expect(result.coordinates.first.lat, 47.37);
      expect(result.coordinates.first.lng, 8.54);
      expect(result.coordinates.last.lat, 47.372);
    });

    test(
        'builds one per-segment URL — radiuses + foot profile + lng,lat pair',
        () async {
      // Per-segment routing: each consecutive pair of waypoints
      // hits OSRM independently with radiuses=250;250. This is the
      // load-bearing accuracy fix vs the old single-call shape —
      // one unreachable waypoint no longer detours the entire
      // polyline through it.
      final stub = _StubFetcher(jsonEncode({
        'code': 'Ok',
        'routes': [
          {
            'distance': 0,
            'geometry': {'coordinates': []},
          },
        ],
      }));
      await fetchRouteThrough(
        const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
          Waypoint(lat: 47.39, lng: 8.56),
        ],
        fetcher: stub.call,
      );
      // Last segment that hit the stub — the previous segments
      // overwrote `lastUrl` so we assert on the final call shape.
      expect(stub.callCount, 2,
          reason: 'Three waypoints → two segments → two OSRM calls.');
      expect(
        stub.lastUrl!.path,
        '/route/v1/foot/8.55,47.38;8.56,47.39',
      );
      expect(stub.lastUrl!.queryParameters['overview'], 'full');
      expect(stub.lastUrl!.queryParameters['geometries'], 'geojson');
      // The new accuracy-fix parameter:
      expect(
        stub.lastUrl!.queryParameters['radiuses'],
        '500;500',
        reason: 'radiuses=500;500 caps how far OSRM can reach to '
            'find a road — bumped from 250 m per user feedback. '
            'Kept in lockstep with web `OSRM_SNAP_RADIUS_M`.',
      );
    });

    test('falls back to straight-line when OSRM returns a non-Ok code', () async {
      // Web-parity: a single bad segment used to throw the whole call.
      // Now each segment falls back to straight-line so unreachable
      // waypoints don't poison the rest of the polyline.
      final stub = _StubFetcher(jsonEncode({'code': 'NoRoute'}));
      final result = await fetchRouteThrough(
        const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
        ],
        fetcher: stub.call,
      );
      expect(result.coordinates.length, 2,
          reason: 'Straight-line fallback emits the two endpoints.');
      expect(result.okSegments, 0);
      expect(result.totalSegments, 1);
      expect(result.hadFallbacks, isTrue);
      expect(result.distanceMetres, greaterThan(0),
          reason: 'Haversine distance is computed for the straight line.');
    });

    test('falls back to straight-line when routes array is missing or empty',
        () async {
      final stub = _StubFetcher(jsonEncode({
        'code': 'Ok',
        'routes': [],
      }));
      final result = await fetchRouteThrough(
        const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
        ],
        fetcher: stub.call,
      );
      expect(result.okSegments, 0);
      expect(result.hadFallbacks, isTrue);
    });

    test(
        'transient failure retries and recovers — segment marked ok',
        () async {
      // Web-parity retry contract: a transient fetcher failure
      // (timeout / network blip / parse error) shouldn't immediately
      // burn the segment into a straight-line fallback. The first
      // 2 attempts can fail and the 3rd recover; result is ok=true.
      var call = 0;
      Future<String> flakyFetcher(Uri _) async {
        call++;
        if (call < 3) throw const SocketException('temporary');
        return jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'distance': 100.0,
              'geometry': {
                'coordinates': [[8.54, 47.37], [8.55, 47.38]],
              },
            },
          ],
        });
      }
      final result = await fetchRouteThrough(
        const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
        ],
        fetcher: flakyFetcher,
      );
      expect(call, 3,
          reason: 'Initial attempt + 2 retries until recovery.');
      expect(result.okSegments, 1);
      expect(result.hadFallbacks, isFalse);
      expect(result.coordinates.length, 2);
    });

    test(
        'permanent OSRM verdict (NoRoute) short-circuits — no retries',
        () async {
      // Retry only on TRANSIENT failures. A `NoRoute` / `NoSegment`
      // verdict from OSRM is permanent — burning retries on it
      // would just keep getting the same answer + delay the
      // straight-line fallback the user sees.
      var call = 0;
      Future<String> noRouteFetcher(Uri _) async {
        call++;
        return jsonEncode({'code': 'NoRoute'});
      }
      final result = await fetchRouteThrough(
        const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
        ],
        fetcher: noRouteFetcher,
      );
      expect(call, 1,
          reason: 'NoRoute is permanent — must not retry.');
      expect(result.hadFallbacks, isTrue);
      expect(result.okSegments, 0);
    });

    test(
        'batches segments — 5 waypoints (4 segments) hit OSRM in '
        'two parallel batches of 3 + 1',
        () async {
      // Web-parity concurrency: 4 segments at batch-size 3 = 2 batches.
      // The first batch runs 3 parallel, the second 1. Without
      // batching, the same 4 segments would have hit OSRM serially.
      var maxConcurrent = 0;
      var inFlight = 0;
      Future<String> trackingFetcher(Uri _) async {
        inFlight++;
        if (inFlight > maxConcurrent) maxConcurrent = inFlight;
        // Hold for a tick so the parallel batch overlaps in flight.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        inFlight--;
        return jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'distance': 100.0,
              'geometry': {
                'coordinates': [[8.5, 47.5], [8.51, 47.51]],
              },
            },
          ],
        });
      }
      final result = await fetchRouteThrough(
        const [
          Waypoint(lat: 47.50, lng: 8.50),
          Waypoint(lat: 47.51, lng: 8.51),
          Waypoint(lat: 47.52, lng: 8.52),
          Waypoint(lat: 47.53, lng: 8.53),
          Waypoint(lat: 47.54, lng: 8.54),
        ],
        fetcher: trackingFetcher,
      );
      expect(maxConcurrent, 3,
          reason: 'Batch size pinned at 3 parallel calls per wave.');
      expect(result.totalSegments, 4);
      expect(result.okSegments, 4);
    });

    test(
        'partial success — one good segment + one bad — stitches the '
        'polyline with straight-line for the bad segment',
        () async {
      // The load-bearing accuracy property: a 3-waypoint route
      // where the middle waypoint is unreachable should still
      // render a road-snapped polyline for the good segment plus
      // a straight line for the bad one. Pre-fix, the single
      // OSRM call would detour the whole route to hit the bad
      // waypoint OR fail entirely.
      var call = 0;
      Future<String> alternatingFetcher(Uri _) async {
        call++;
        if (call == 1) {
          // First segment: real polyline.
          return jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 100.0,
                'geometry': {
                  'coordinates': [
                    [8.54, 47.37],
                    [8.545, 47.375],
                    [8.55, 47.38],
                  ],
                },
              },
            ],
          });
        }
        // Second segment: NoRoute.
        return jsonEncode({'code': 'NoRoute'});
      }

      final result = await fetchRouteThrough(
        const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
          Waypoint(lat: 47.39, lng: 8.60),
        ],
        fetcher: alternatingFetcher,
      );
      expect(result.totalSegments, 2);
      expect(result.okSegments, 1);
      expect(result.hadFallbacks, isTrue);
      // Stitched polyline: 3 points from segment 1 + 1 endpoint
      // from the straight-line segment 2 (the shared waypoint
      // between the two segments is dedup'd).
      expect(result.coordinates.length, 4);
      // Stitched endpoints survived.
      expect(result.coordinates.first.lat, closeTo(47.37, 1e-9));
      expect(result.coordinates.last.lng, closeTo(8.60, 1e-9));
    });

    test(
        'cancellation gate aborts between segments — newer pin '
        'placement drops the older route in flight',
        () async {
      // Web-parity cancellation: when the user rapidly places /
      // moves pins, the older routing pass should abort instead of
      // racing the newer one. The result returned has
      // `wasCancelled=true` and the caller (route_builder_screen)
      // discards it without touching state.
      var call = 0;
      var generation = 0;
      Future<String> trackingFetcher(Uri _) async {
        call++;
        // After the first segment, "the user" placed a new pin.
        if (call == 1) generation = 1;
        return jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'distance': 100.0,
              'geometry': {
                'coordinates': [[8.5, 47.5], [8.51, 47.51]],
              },
            },
          ],
        });
      }
      final result = await fetchRouteThrough(
        const [
          // 5 waypoints → 4 segments → two batches of 3+1. The
          // cancellation should fire between the two batches.
          Waypoint(lat: 47.50, lng: 8.50),
          Waypoint(lat: 47.51, lng: 8.51),
          Waypoint(lat: 47.52, lng: 8.52),
          Waypoint(lat: 47.53, lng: 8.53),
          Waypoint(lat: 47.54, lng: 8.54),
        ],
        fetcher: trackingFetcher,
        cancelled: () => generation != 0,
      );
      expect(result.wasCancelled, isTrue);
      expect(call, lessThan(4),
          reason: 'Cancellation gate must abort BEFORE the 4th '
              'segment fires — proves cancellation stops further work.');
      // The cancelled result carries empty polyline so a buggy
      // caller that forgot to check wasCancelled at least doesn\'t
      // commit a partial polyline to the UI.
      expect(result.coordinates, isEmpty);
      expect(result.distanceMetres, 0);
    });

    test(
        'cancellation gate skips retries on an in-flight failing segment',
        () async {
      // Worst case: a segment is in its retry loop (transient
      // failure) when the user places a new pin. Without the gate
      // inside the retry loop, the user waits ~25 s before the
      // cancellation can take effect at the inter-batch boundary.
      // With the gate, the next retry's pre-check fires and the
      // attempt short-circuits.
      var attemptCount = 0;
      var cancelled = false;
      Future<String> alwaysFails(Uri _) async {
        attemptCount++;
        // Once we've tried once, "the user" places a new pin.
        if (attemptCount == 1) cancelled = true;
        throw const SocketException('persistent');
      }
      final result = await fetchRouteThrough(
        const [
          Waypoint(lat: 47.50, lng: 8.50),
          Waypoint(lat: 47.51, lng: 8.51),
        ],
        fetcher: alwaysFails,
        cancelled: () => cancelled,
      );
      // The first attempt fires; the cancellation gate then trips
      // before the retry, so attemptCount stays at 1 (no retries
      // burned on a cancelled pass).
      expect(attemptCount, 1,
          reason: 'Gate inside the retry loop must short-circuit '
              'instead of burning all 2 retries.');
      expect(result.wasCancelled, isTrue);
    });

    test(
        'exhausted retries (every attempt throws) falls back to '
        'straight-line — final transient error path',
        () async {
      // Per-segment retry contract: if all `kOsrmRetries + 1`
      // attempts throw, the segment falls back to straight-line
      // rather than propagating the exception. Pre-fix, the
      // single attempt threw and the route_builder caught + showed
      // a banner; now the polyline still renders (with a soft
      // warning) so the user can drag the bad pin without losing
      // everything.
      var call = 0;
      Future<String> alwaysFails(Uri _) async {
        call++;
        throw const SocketException('persistent network failure');
      }
      final result = await fetchRouteThrough(
        const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
        ],
        fetcher: alwaysFails,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            fail('fetchRouteThrough did not exit the retry loop'),
      );
      // kOsrmRetries = 2 → 3 attempts total per segment.
      expect(call, 3);
      expect(result.okSegments, 0);
      expect(result.totalSegments, 1);
      expect(result.hadFallbacks, isTrue);
    });
  });
}
