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
    lastMinLng = minLng;
    lastMinLat = minLat;
    lastMaxLng = maxLng;
    lastMaxLat = maxLat;
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
  Future<Position?> Function()? backgroundLocateFn,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RoutesHeatmapScreen(
        api: api,
        geocodingFetcher: geocodingFetcher,
        locateFn: locateFn,
        backgroundLocateFn: backgroundLocateFn,
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
      final initialFetches = api.discoverCalls;

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(locateCalls, 1);
      expect(api.discoverCalls, greaterThan(initialFetches),
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

    testWidgets('typing surfaces place options from the Nominatim fallback',
        (tester) async {
      // With no MapTiler key (the protomaps-only dev default) searchPlaces
      // falls through to Nominatim, whose response is a JSON array. The
      // dropdown must surface as the user types — the production bug was a
      // missing User-Agent making Nominatim 403 into an empty list.
      final api = _FakeApiClient();
      Future<String> nominatimStub(Uri _) async => jsonEncode([
            {
              'display_name': 'London, Greater London, England',
              'lat': '51.5074',
              'lon': '-0.1276',
            },
          ]);
      await _pump(tester, api, geocodingFetcher: nominatimStub);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search places…'),
        'London',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('London, Greater London, England'), findsOneWidget);
    });

    testWidgets('mounts a FlutterMap with a TileLayer + a marker layer',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(TileLayer), findsAtLeastNWidgets(1));
      // Pins render in a MarkerLayer (even when empty). Heat is off by
      // default, so there is no heat CircleLayer on mount.
      expect(find.byType(MarkerLayer), findsAtLeastNWidgets(1));
    });

    testWidgets('opens centred on the user location when a fix is available',
        (tester) async {
      final api = _FakeApiClient();
      // New York City — far from the London default centre.
      await _pump(
        tester,
        api,
        backgroundLocateFn: () async => _fakePosition(
          lat: 40.7128,
          lng: -74.0060,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.lastMinLng, isNotNull);
      expect(api.lastMinLng! <= -74.0060 && api.lastMaxLng! >= -74.0060, isTrue,
          reason: 'the map must open centred on the user fix, so the '
              'discovery bbox brackets NYC longitude — not London.');
      expect(api.lastMinLat! <= 40.7128 && api.lastMaxLat! >= 40.7128, isTrue,
          reason: 'and the bbox brackets NYC latitude.');
    });

    testWidgets('fetches discovery on mount with a valid bbox; heat is off',
        (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.discoverCalls, greaterThanOrEqualTo(1));
      expect(api.lastMinLng, isNotNull);
      expect(api.lastMinLng!, lessThan(api.lastMaxLng!));
      expect(api.lastMinLat!, lessThan(api.lastMaxLat!));
      // Heat is off by default → no heat-points fetch on mount.
      expect(api.fetchCalls, 0,
          reason: 'the density heat layer is opt-in; we must not pay '
              'for heatmap points until the user enables Heat.');
    });

    testWidgets('enabling Heat fetches heat points + mounts the heat layer',
        (tester) async {
      final api = _FakeApiClient()
        ..nextPoints = const [HeatmapPoint(lat: 51.5074, lng: -0.1276)];
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.fetchCalls, 0);
      expect(find.byType(CircleLayer), findsNothing);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The Heat chip sits at the bottom of the scrollable sheet.
      await tester.ensureVisible(find.text('Heat density'));
      await tester.pump();
      await tester.tap(find.text('Heat density'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.fetchCalls, greaterThanOrEqualTo(1),
          reason: 'toggling Heat must fetch the density points');
    });

    testWidgets('RPC error path swallows + does not crash', (tester) async {
      final api = _FakeApiClient()..errorToThrow = Exception('rpc 500');
      await _pump(tester, api);
      expect(find.text('Search places…'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
    });
  });

  group('discovery pins + lens', () {
    testWidgets('fetches discoverable pins on mount + lists them via the pill',
        (tester) async {
      final api = _FakeApiClient()..nextPins = [_pin()];
      await _pump(tester, api);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.discoverCalls, greaterThanOrEqualTo(1));
      expect(api.lastFilter, 'popular',
          reason: 'the default lens is popular');
      // The map is clean by default: the count shows on the pill, the
      // route name only after the pill opens the modal results list.
      expect(find.text('1 route'), findsOneWidget);
      expect(find.text('Wash Park 5K Loop'), findsNothing);

      await tester.tap(find.text('1 route'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
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

      // Open the modal results list, then tap the row.
      await tester.tap(find.text('1 route'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Wash Park 5K Loop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The sheet pops; the selection card + previewed route line appear.
      expect(find.text('View route'), findsOneWidget);
      expect(find.byKey(const ValueKey('heatmap-selected-route')),
          findsOneWidget);
    });
  });

  // The keep-on-map / pin behaviour (pin a route -> its violet line persists
  // across pan + filter -> Clear removes it) is covered end-to-end by the web
  // Playwright suite (apps/web/tests-e2e/routes/heatmap-filters.spec.ts,
  // "Heatmap keep-on-map / pin"). The mobile screen is a direct mirror; a
  // widget test isn't added here because the pin controls live below the
  // collapsed DraggableScrollableSheet fold, which flutter_test can't tap
  // reliably (it matches the sheet's offstage measurement copy) — the same
  // limitation the existing sheet tests work around by tapping only the
  // top-of-list rows.
}
