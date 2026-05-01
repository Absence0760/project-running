import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/routes_screen.dart';

List<cm.Route> _makeRoutes(int count) {
  return [
    for (int i = 0; i < count; i++)
      cm.Route(
        id: 'route-${i.toString().padLeft(3, '0')}',
        name: 'Route $i',
        waypoints: const [
          cm.Waypoint(lat: 51.5, lng: -0.12),
          cm.Waypoint(lat: 51.51, lng: -0.13),
        ],
        distanceMetres: 5000,
        elevationGainMetres: 50,
      ),
  ];
}

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(WidgetTester tester, {required Preferences prefs}) {
  return tester.pumpWidget(
    MaterialApp(
      home: RoutesScreen(
        apiClient: null,
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ),
  );
}

void main() {
  group('RoutesScreen — initial render', () {
    testWidgets('renders the Routes app-bar title', (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.text('Routes'), findsOneWidget);
    });

    testWidgets('renders the Explore action in the app bar',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byIcon(Icons.explore), findsOneWidget);
    });

    testWidgets('hides the cloud-sync icon when apiClient is null',
        (tester) async {
      // Reason: without a signed-in user the cloud_download icon must
      // not appear — there is nothing to sync.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byIcon(Icons.cloud_download), findsNothing);
    });

    testWidgets('renders the Import FAB with the upload icon',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
      expect(find.byIcon(Icons.upload_file), findsOneWidget);
    });

    testWidgets('shows the empty state when there are no routes',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.text('No routes yet'), findsOneWidget);
      expect(find.text('Tap Import to add a GPX or KML file'), findsOneWidget);
    });
  });

  group('RoutesScreen pagination', () {
    test('shouldShowRoutesLoadMore — local rows beyond visibleCount', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 25,
          remoteHasMore: false,
          apiSignedIn: false,
        ),
        isTrue,
      );
    });

    test('shouldShowRoutesLoadMore — exhausted local + signed-in cloud', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 20,
          remoteHasMore: true,
          apiSignedIn: true,
        ),
        isTrue,
      );
    });

    test('shouldShowRoutesLoadMore — exhausted local + cloud says done', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 20,
          remoteHasMore: false,
          apiSignedIn: true,
        ),
        isFalse,
      );
    });

    test('shouldShowRoutesLoadMore — signed out, no local extras', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 20,
          remoteHasMore: true,
          apiSignedIn: false,
        ),
        isFalse,
      );
    });

    testWidgets('shows first page + Load more when 25 routes cached',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()..debugSeed(_makeRoutes(25));
      await tester.pumpWidget(
        MaterialApp(
          home: RoutesScreen(
            apiClient: null,
            routeStore: routeStore,
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();

      // First page = 20 routes; remaining 5 hidden behind the footer.
      // ListView.builder is lazy; scroll to materialise the footer.
      await tester.scrollUntilVisible(
        find.text('Load 20 more'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Load 20 more'), findsOneWidget);
    });

    testWidgets('Load more hidden when fewer routes than page size',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()..debugSeed(_makeRoutes(5));
      await tester.pumpWidget(
        MaterialApp(
          home: RoutesScreen(
            apiClient: null,
            routeStore: routeStore,
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Load 20 more'), findsNothing);
    });

    testWidgets('tapping Load more reveals the next local page',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()..debugSeed(_makeRoutes(25));
      await tester.pumpWidget(
        MaterialApp(
          home: RoutesScreen(
            apiClient: null,
            routeStore: routeStore,
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Load 20 more'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Load 20 more'), findsOneWidget);
      await tester.tap(find.text('Load 20 more'));
      await tester.pump();

      // 25 ≤ 40 (next page) + apiClient null → no further button.
      expect(find.text('Load 20 more'), findsNothing);
    });
  });
}
