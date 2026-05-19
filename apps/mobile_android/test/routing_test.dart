import 'dart:async';
import 'dart:convert';

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

    test('builds the URL with semicolon-joined lng,lat pairs', () async {
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
      // foot is the default profile, three lng,lat pairs separated by `;`.
      expect(
        stub.lastUrl!.path,
        '/route/v1/foot/8.54,47.37;8.55,47.38;8.56,47.39',
      );
      // overview + geometries query params survive the build.
      expect(stub.lastUrl!.queryParameters['overview'], 'full');
      expect(stub.lastUrl!.queryParameters['geometries'], 'geojson');
    });

    test('throws StateError when OSRM returns a non-Ok code', () async {
      final stub = _StubFetcher(jsonEncode({'code': 'NoRoute'}));
      expect(
        () => fetchRouteThrough(
          const [
            Waypoint(lat: 47.37, lng: 8.54),
            Waypoint(lat: 47.38, lng: 8.55),
          ],
          fetcher: stub.call,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when routes array is missing or empty',
        () async {
      final stub = _StubFetcher(jsonEncode({
        'code': 'Ok',
        'routes': [],
      }));
      expect(
        () => fetchRouteThrough(
          const [
            Waypoint(lat: 47.37, lng: 8.54),
            Waypoint(lat: 47.38, lng: 8.55),
          ],
          fetcher: stub.call,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws TimeoutException when the fetcher exceeds '
        'kOsrmRouteTimeout', () async {
      // No catch in fetchRouteThrough — the caller (route_builder_screen)
      // catches and shows a banner. The point of the timeout is that
      // the throw happens at ~8s, not after the network's eventual
      // 30s+ stall.
      Future<String> hangingFetcher(Uri _) async {
        await Future<void>.delayed(const Duration(seconds: 30));
        return '{}';
      }
      await expectLater(
        fetchRouteThrough(
          const [
            Waypoint(lat: 47.37, lng: 8.54),
            Waypoint(lat: 47.38, lng: 8.55),
          ],
          fetcher: hangingFetcher,
        ).timeout(
          const Duration(seconds: 12),
          onTimeout: () =>
              fail('fetchRouteThrough did not honour kOsrmRouteTimeout'),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
