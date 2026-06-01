// Widget tests for RoutesHeatmapScreen — the mobile mirror of the web
// route-discovery browser. The full chain (RPC → render) is exercised
// against a fake ApiClient. flutter_map's tile fetches fail under the
// test runner (HTTP 400 in widget tests) which is the same constraint
// other map-bearing widget tests deal with; we pin the chrome + the RPC
// invocation + the discovery UI, not tile-load success.

import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import '../lib/screens/routes_heatmap_screen.dart';

class _FakeApiClient extends ApiClient {
  int fetchCalls = 0;
  double? lastMinLng;
  double? lastMinLat;
  double? lastMaxLng;
  double? lastMaxLat;
  List<HeatmapPoint> nextPoints = const [];
  Object? errorToThrow;

  // Discovery support.
  int discoverCalls = 0;
  String? lastFilter;
  List<double>? lastDistMin;
  List<cm.DiscoverableRoutePin> nextPins = const [];
  List<cm.ClubPin> nextClubs = const [];
  cm.Route? nextRouteById;

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
  Future<List<cm.DiscoverableRoutePin>> fetchDiscoverableRoutesInBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int limit = 100,
    String filter = 'popular',
    List<double>? distMin,
    List<double?>? distMax,
  }) async {
    discoverCalls++;
    lastFilter = filter;
    lastDistMin = distMin;
    return nextPins;
  }

  @override
  Future<List<cm.ClubPin>> fetchClubsInBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int limit = 100,
  }) async =>
      nextClubs;

  @override
  Future<({cm.Route? route, String? ownerId})> fetchRouteById(
    String routeId,
  ) async =>
      (route: nextRouteById, ownerId: 'u');
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

cm.DiscoverableRoutePin _pin({
  String id = 'a',
  String name = 'Wash Park 5K Loop',
  bool featured = false,
  double distanceM = 5000,
  int runCount = 6,
  double lat = 39.74,
  double lng = -105.0,
}) =>
    cm.DiscoverableRoutePin(
      id: id,
      name: name,
      featured: featured,
      distanceM: distanceM,
      surface: 'road',
      runCount: runCount,
      lat: lat,
      lng: lng,
    );

Position _fakePosition({double lat = 40.7128, double lng = -74.0060}) =>
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
    dotenv.loadFromString(isOptional: true);
  });

  group('RoutesHeatmapScreen', () {
    testWidgets('AppBar hosts a place-search field + a Filters button',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      expect(find.text('Search places…'), findsOneWidget);
      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(find.textContaining('Where people run'), findsNothing);
    });

    testWidgets('shows the Locate-me FAB with my_location icon',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('tapping the Locate FAB calls locateFn + refetches',
        (tester) async {
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
      await tester.pump(const Duration(milliseconds: 100));
      final initialFetches = api.fetchCalls;

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(locateCalls, 1);
      expect(api.fetchCalls, greaterThan(initialFetches),
          reason: 'Locate must schedule a refresh so discovery '
              "repopulates around the user's location.");
    });

    testWidgets('search degrades silently when MapTiler is unconfigured',
        (tester) async {
      final api = _FakeApiClient();
      Future<String> stubFetcher(Uri _) async => jsonEncode({
            'features': [
              {
                'place_name': 'Tokyo, Japan',
                'center': [139.6917, 35.6895],
              },
            ],
          });
      await _pump(tester, api, geocodingFetcher: stubFetcher);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search places…'),
        'Tokyo',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Tokyo, Japan'), findsNothing,
          reason: 'searchPlaces short-circuits to empty when the '
              'MapTiler key is unset; the dropdown must not surface.');
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
      final api = _FakeApiClient()
        ..nextPoints = const [HeatmapPoint(lat: 51.5074, lng: -0.1276)];
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.fetchCalls, greaterThanOrEqualTo(1));
      expect(api.lastMinLng, isNotNull);
      expect(api.lastMinLng!, lessThan(api.lastMaxLng!));
      expect(api.lastMinLat!, lessThan(api.lastMaxLat!));
    });

    testWidgets('RPC error path swallows + does not crash', (tester) async {
      final api = _FakeApiClient()..errorToThrow = Exception('rpc 500');
      await _pump(tester, api);
      expect(find.text('Search places…'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
    });
  });

  group('discovery pins + lens', () {
    testWidgets('fetches discoverable pins on mount + lists them',
        (tester) async {
      final api = _FakeApiClient()..nextPins = [_pin()];
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.discoverCalls, greaterThanOrEqualTo(1));
      expect(api.lastFilter, 'popular',
          reason: 'the default lens is popular');
      // The bottom-sheet results list renders the route by name.
      expect(find.text('Wash Park 5K Loop'), findsOneWidget);
    });

    testWidgets('the Filters sheet swaps the lens + refetches',
        (tester) async {
      // No pins → no band badges, so the only "Featured" text is the
      // sheet's lens chip.
      final api = _FakeApiClient();
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Featured'), findsOneWidget);

      await tester.tap(find.text('Featured'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.lastFilter, 'featured');
    });

    testWidgets('picking a distance band threads the bounds to the RPC',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('5K'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.lastDistMin, [4000],
          reason: 'the 5K band lower bound must reach the RPC');
    });
  });

  group('tap-to-preview', () {
    testWidgets('tapping a route row previews its line + a View action',
        (tester) async {
      final api = _FakeApiClient()
        ..nextPins = [_pin()]
        ..nextRouteById = cm.Route(
          id: 'a',
          userId: 'u',
          name: 'Wash Park 5K Loop',
          waypoints: const [
            Waypoint(lat: 39.740, lng: -105.000),
            Waypoint(lat: 39.745, lng: -105.005),
          ],
          distanceMetres: 5000,
        );
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));

      // No route line drawn until something is selected.
      expect(find.byKey(const ValueKey('heatmap-selected-route')),
          findsNothing);

      await tester.tap(find.text('Wash Park 5K Loop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The selection card + the previewed route line both appear.
      expect(find.text('View route'), findsOneWidget);
      expect(find.byKey(const ValueKey('heatmap-selected-route')),
          findsOneWidget);
    });
  });
}
