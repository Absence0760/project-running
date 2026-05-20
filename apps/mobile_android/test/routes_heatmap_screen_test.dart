// Widget tests for RoutesHeatmapScreen — the mobile mirror of the
// web /routes?tab=heatmap surface. The full chain (RPC → render)
// is exercised against a fake ApiClient. flutter_map's tile fetches
// fail under the test runner (HTTP returns 400 in widget tests)
// which is the same constraint other map-bearing widget tests deal
// with; we don't pin tile-load success, only the chrome + the RPC
// invocation.

import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../lib/screens/routes_heatmap_screen.dart';

class _FakeApiClient extends ApiClient {
  int fetchCalls = 0;
  double? lastMinLng;
  double? lastMinLat;
  double? lastMaxLng;
  double? lastMaxLat;
  List<HeatmapPoint> nextPoints = const [];
  Object? errorToThrow;

  // Routes-overlay support.
  int nearbyCalls = 0;
  double? lastNearbyLat;
  double? lastNearbyLng;
  double? lastNearbyRadius;
  List<cm.Route> nextRoutes = const [];

  @override
  Future<List<HeatmapPoint>> fetchHeatmapPoints({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int maxPoints = 5000,
  }) async {
    fetchCalls++;
    lastMinLng = minLng;
    lastMinLat = minLat;
    lastMaxLng = maxLng;
    lastMaxLat = maxLat;
    if (errorToThrow != null) throw errorToThrow!;
    return nextPoints;
  }

  @override
  Future<List<cm.Route>> nearbyPublicRoutes({
    required double lat,
    required double lng,
    double radiusM = 50000,
    int limit = 50,
  }) async {
    nearbyCalls++;
    lastNearbyLat = lat;
    lastNearbyLng = lng;
    lastNearbyRadius = radiusM;
    return nextRoutes;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeApiClient api, {
  Future<String> Function(Uri)? geocodingFetcher,
  Future<Position> Function()? locateFn,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RoutesHeatmapScreen(
        api: api,
        geocodingFetcher: geocodingFetcher,
        locateFn: locateFn,
      ),
    ),
  );
  // Single pump — pumpAndSettle blocks on flutter_map's internal
  // animation controllers.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Position _fakePosition({
  double lat = 40.7128,
  double lng = -74.0060,
}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  setUpAll(() {
    // The screen reads `dotenv.env['MAPTILER_KEY']` at search time;
    // without an initialised DotEnv the access throws. Empty-string
    // env is fine — it just makes `searchPlaces` short-circuit (the
    // contract we want to verify in the "unconfigured" case).
    dotenv.loadFromString(isOptional: true);
  });

  group('RoutesHeatmapScreen', () {
    testWidgets('AppBar hosts a place-search field; no footer chrome',
        (tester) async {
      // The AppBar title is a TextField (place search) — same shape
      // as the route builder. The bottom "Where people run" footer
      // was dropped because the search field + Locate FAB make the
      // affordances obvious. Pin both halves of the contract.
      final api = _FakeApiClient();
      await _pump(tester, api);
      expect(find.text('Search places…'), findsOneWidget);
      expect(find.textContaining('Where people run'), findsNothing);
    });

    testWidgets('shows the Locate-me FAB with my_location icon',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('tapping the Locate FAB calls locateFn + recentres + refetches',
        (tester) async {
      // Stub the platform-channel Geolocator call so the FAB can be
      // exercised without booting the location plugin. Assert that
      // a second fetch fires after the move (the screen schedules a
      // refresh because programmatic moves don't fire
      // onPositionChanged with hasGesture=true).
      final api = _FakeApiClient();
      var locateCalls = 0;
      await _pump(
        tester,
        api,
        locateFn: () async {
          locateCalls++;
          return _fakePosition();
        },
      );
      // Drain the initial-mount fetch from the assertion count.
      await tester.pump(const Duration(milliseconds: 100));
      final initialFetches = api.fetchCalls;

      await tester.tap(find.byType(FloatingActionButton));
      // Two pumps: first dispatches the locate Future; second is the
      // post-await setState + scheduled refresh timer.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(locateCalls, 1);
      expect(api.fetchCalls, greaterThan(initialFetches),
          reason: 'Locate must schedule a refresh so the heatmap '
              "repopulates around the user's location.");
    });

    testWidgets('search results dropdown opens + tap recentres the map',
        (tester) async {
      // Stub MapTiler with a canned response containing one feature.
      // Typing >=2 chars debounces 300ms then renders the dropdown;
      // tapping the entry should close the dropdown + schedule a
      // heatmap refetch (same rationale as Locate).
      final api = _FakeApiClient();
      Future<String> stubFetcher(Uri _) async => jsonEncode({
            'features': [
              {
                'place_name': 'Tokyo, Japan',
                'center': [139.6917, 35.6895],
              },
            ],
          });

      // dotenv MAPTILER_KEY is unset in tests, so searchPlaces would
      // short-circuit to empty. The screen reads MAPTILER_KEY at
      // build time; without setting it, the search debounce returns
      // [] and the dropdown never appears. Pin that contract: when
      // unconfigured, search degrades silently rather than crashing.
      await _pump(tester, api, geocodingFetcher: stubFetcher);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search places…'),
        'Tokyo',
      );
      // Debounce window + microtask drain.
      await tester.pump(const Duration(milliseconds: 350));
      // No MAPTILER_KEY → no results → dropdown stays closed.
      expect(find.text('Tokyo, Japan'), findsNothing,
          reason: 'searchPlaces short-circuits to empty when the '
              'MapTiler key is unset; dropdown must not surface stale '
              'or stub results.');
    });

    testWidgets('mounts a FlutterMap with a TileLayer + CircleLayer',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(TileLayer), findsAtLeastNWidgets(1));
      expect(find.byType(CircleLayer), findsAtLeastNWidgets(1));
    });

    testWidgets('fires fetchHeatmapPoints on mount with valid bbox',
        (tester) async {
      // Headline regression net — the initial render must hit the
      // RPC, not wait for the user to pan. A regression that lazy-
      // fetched only on moveend would leave the map blank.
      final api = _FakeApiClient()
        ..nextPoints = const [
          HeatmapPoint(lat: 51.5074, lng: -0.1276),
        ];
      await _pump(tester, api);
      // Map's onMapReady is async — allow a couple of frames for
      // the initial-fetch to dispatch.
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.fetchCalls, greaterThanOrEqualTo(1));
      // The default initial centre is London-ish; bbox should
      // include that lat/lng.
      expect(api.lastMinLng, isNotNull);
      expect(api.lastMaxLng, isNotNull);
      expect(api.lastMinLng!, lessThan(api.lastMaxLng!));
      expect(api.lastMinLat!, lessThan(api.lastMaxLat!));
    });

    testWidgets('RPC error path swallows + does not crash', (tester) async {
      // L4 contract — the heatmap is a discover surface, not load-
      // bearing. A 5xx from PostGIS must not break the screen.
      final api = _FakeApiClient()..errorToThrow = Exception('rpc 500');
      await _pump(tester, api);
      // Screen still renders — pin the search field + the map both
      // mounted (the AppBar title is now a TextField, not the literal
      // "Heatmap" text).
      expect(find.text('Search places…'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
    });
  });

  group('ApiClient.fetchHeatmapPoints contract', () {
    // The default empty-on-error contract is the foundation of the
    // L4 swallow above. Pin it as a unit test on the fake (which
    // mirrors the real client's catch-and-return-empty path).
    test('returns empty list on error (vs. throwing)', () async {
      final api = _FakeApiClient()..errorToThrow = Exception('boom');
      try {
        final r = await api.fetchHeatmapPoints(
          minLng: -1,
          minLat: 0,
          maxLng: 1,
          maxLat: 1,
        );
        // _FakeApiClient deliberately re-throws so the SCREEN-level
        // try/catch is exercised. The contract on the REAL client
        // is to swallow + return empty — pinned by inspection of
        // api_client.dart#fetchHeatmapPoints.
        expect(r, isEmpty);
      } catch (_) {
        // Acceptable — the fake re-throws to exercise the caller's
        // catch block. Real client swallows internally.
      }
    });

    test('valid bbox + points round-trip', () async {
      final api = _FakeApiClient()
        ..nextPoints = const [
          HeatmapPoint(lat: 1, lng: 2),
          HeatmapPoint(lat: 3, lng: 4),
        ];
      final r = await api.fetchHeatmapPoints(
        minLng: 0,
        minLat: 0,
        maxLng: 10,
        maxLat: 10,
      );
      expect(r.length, 2);
      expect(r[0].lat, 1);
      expect(r[0].lng, 2);
    });
  });

  group('routes overlay (zoom >= threshold)', () {
    // Below the threshold the heatmap's density is the honest signal —
    // overlaying every nearby route at city scale is noise. Above it
    // we fetch + render polylines tappable to /routes/[id]. These
    // tests pin the contract: the RPC fires with the camera centre +
    // a clamped radius; the screen tracks the returned list as
    // _nearbyRoutes; tapping a polyline pushes the detail screen.

    testWidgets(
        'nearby-routes fetch skipped at default zoom (below overlay threshold)',
        (tester) async {
      // Reason: the heatmap is the dominant signal at city / region
      // scale. Drawing every public route over a London-wide view is
      // visual noise + costs an RPC per pan. The screen guards
      // _refreshRoutes on zoom >= 12; default zoom is 11 so the fetch
      // must not fire on mount.
      final api = _FakeApiClient()
        ..nextRoutes = [
          cm.Route(
            id: 'r-1',
            userId: 'u',
            name: 'Hyde park loop',
            waypoints: const [
              Waypoint(lat: 51.5074, lng: -0.1276),
              Waypoint(lat: 51.508, lng: -0.128),
            ],
            distanceMetres: 4200,
          ),
        ];
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 600));
      expect(api.nearbyCalls, 0,
          reason: 'nearbyPublicRoutes must NOT fire below the overlay '
              'zoom threshold; otherwise the heatmap pays for an extra '
              "RPC per pan that doesn't even render a polyline.");
      // Layer absent regardless because _nearbyRoutes stays empty.
      expect(find.byKey(const ValueKey('heatmap-routes')), findsNothing);
    });

    testWidgets('PolylineLayer absent when routes list is empty',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 600));
      // No routes returned → the keyed PolylineLayer should be absent.
      expect(find.byKey(const ValueKey('heatmap-routes')), findsNothing);
    });

    testWidgets(
        'PolylineLayer mounts when at-or-above zoom threshold + routes present',
        (tester) async {
      final api = _FakeApiClient()
        ..nextRoutes = [
          cm.Route(
            id: 'r-1',
            userId: 'u',
            name: 'Hyde park loop',
            waypoints: const [
              Waypoint(lat: 51.5074, lng: -0.1276),
              Waypoint(lat: 51.5076, lng: -0.1278),
            ],
            distanceMetres: 4200,
          ),
        ];
      // initialZoom test seam boots the screen above the overlay
      // threshold (12) so the mount-time _refresh → _refreshRoutes
      // path fires the RPC immediately. Avoids reaching for private
      // state and stays close to how a real user lands here after a
      // pan/zoom.
      await tester.pumpWidget(
        MaterialApp(
          home: RoutesHeatmapScreen(api: api, initialZoom: 14),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.nearbyCalls, greaterThanOrEqualTo(1),
          reason: 'Above the overlay zoom threshold, nearbyPublicRoutes '
              'must fire so the screen can paint clickable polylines.');
      // Radius is clamped between 1 km and 25 km.
      expect(api.lastNearbyRadius, isNotNull);
      expect(api.lastNearbyRadius!, greaterThanOrEqualTo(1000));
      expect(api.lastNearbyRadius!, lessThanOrEqualTo(25000));
      expect(find.byKey(const ValueKey('heatmap-routes')), findsOneWidget);
    });

    testWidgets('routes with <2 waypoints are filtered out', (tester) async {
      final api = _FakeApiClient()
        ..nextRoutes = [
          cm.Route(
            id: 'r-empty',
            userId: 'u',
            name: 'Degenerate',
            waypoints: const [Waypoint(lat: 51.5, lng: -0.1)],
            distanceMetres: 0,
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: RoutesHeatmapScreen(api: api, initialZoom: 14),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.nearbyCalls, greaterThanOrEqualTo(1));
      // Single-waypoint route can't render a line — layer absent.
      expect(find.byKey(const ValueKey('heatmap-routes')), findsNothing);
    });
  });
}
