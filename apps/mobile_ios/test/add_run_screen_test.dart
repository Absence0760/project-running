import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/local_run_store.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/add_run_screen.dart';

late Directory _runsDir;

Future<({LocalRunStore runs, LocalRouteStore routes, Preferences prefs})>
    _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('add_run_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  // LocalRouteStore has no overrideDirectory; construct without calling
  // init() so path_provider is never touched. routes getter returns []
  // by default, which is all AddRunScreen needs for the route-picker path.
  final routeStore = LocalRouteStore();

  return (runs: runStore, routes: routeStore, prefs: prefs);
}

Future<void> _pump(
  WidgetTester tester,
  LocalRunStore runStore,
  LocalRouteStore routeStore,
  Preferences prefs,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: AddRunScreen(
        runStore: runStore,
        routeStore: routeStore,
        preferences: prefs,
      ),
    ),
  );
}

void main() {
  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('AddRunScreen', () {
    testWidgets('renders When, Activity, and Distance section labels',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.pumpAndSettle();
      expect(find.text('When'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      // The distance label appears in the Duration/Distance section.
      expect(find.text('Distance'), findsAtLeastNWidgets(1));
    });

    testWidgets('Save action is present in the app bar', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('renders ChoiceChips for all four activity types',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Walk'), findsOneWidget);
      expect(find.text('Cycle'), findsOneWidget);
      // Picker label rebrand: Hike → Trail run. Enum stays `hike`.
      expect(find.text('Trail run'), findsOneWidget);
    });

    testWidgets('tapping Save without values does not save a run', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // Form validation blocks save — store remains empty.
      expect(s.runs.runs, isEmpty);
    });

    // Reason: the route-picker section was previously gated on
    // `routes.isNotEmpty`, so a user with zero saved routes saw no
    // indication that route-attachment exists. Field report: "I
    // don't see the attach route, for adding a new run." The fix
    // always renders the section header + an empty-state hint when
    // there are no routes yet. Pinning both halves of the contract.
    testWidgets('Route (optional) section renders even when routeStore is empty',
        (tester) async {
      final s = await _makeStores();
      // s.routes is a freshly-constructed LocalRouteStore — routes is empty.
      expect(s.routes.routes, isEmpty);
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.pumpAndSettle();

      expect(find.text('Route (optional)'), findsOneWidget,
          reason: 'Route section header must show so the affordance is '
              'discoverable before the user has built or imported any routes.');
      expect(
        find.text('No saved routes yet — build or import one to attach it here'),
        findsOneWidget,
        reason: 'Empty-state hint must render in place of the picker so '
            'users learn the feature exists.',
      );
    });

    // Positive-shape pin for the route-picker section: when the user
    // has saved routes, the empty-state hint goes away and the search
    // input appears. Pairs with the empty-state test above so a
    // refactor that swaps the two branches fails on the visible copy.
    testWidgets(
        'Route (optional) section renders the picker when routeStore has routes',
        (tester) async {
      final s = await _makeStores();
      s.routes.debugSeed([
        cm.Route(
          id: 'r-1',
          userId: 'test-user',
          name: 'River loop',
          waypoints: const [
            cm.Waypoint(lat: 47.37, lng: 8.54),
            cm.Waypoint(lat: 47.371, lng: 8.541),
          ],
          distanceMetres: 5000,
        ),
      ]);
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.pumpAndSettle();

      expect(find.text('Route (optional)'), findsOneWidget);
      expect(find.text('Search saved routes'), findsOneWidget,
          reason: 'Picker placeholder must surface when routes are '
              'available so the user can drill in to select one.');
      // The empty-state hint must NOT appear in this branch.
      expect(
        find.text(
            'No saved routes yet — build or import one to attach it here'),
        findsNothing,
        reason: 'Empty hint must be hidden once routes exist.',
      );
    });

    // Picker opens to a real list of routes. Drives one keystroke
    // through the search bar, verifies filtering, then taps a row to
    // round-trip a selection. The InputDecorator in AddRunScreen then
    // shows the picked route name + formatted distance, and the
    // search icon flips to a Clear (X) IconButton. Tap that to remove
    // the selection — the picker goes back to the search prompt.
    testWidgets('picker open → filter → select → clear round trip',
        (tester) async {
      final s = await _makeStores();
      s.routes.debugSeed([
        cm.Route(
          id: 'r-park',
          userId: 'test-user',
          name: 'Park loop',
          waypoints: const [
            cm.Waypoint(lat: 47.37, lng: 8.54),
            cm.Waypoint(lat: 47.371, lng: 8.541),
          ],
          distanceMetres: 4200,
        ),
        cm.Route(
          id: 'r-river',
          userId: 'test-user',
          name: 'River out-and-back',
          waypoints: const [
            cm.Waypoint(lat: 47.37, lng: 8.54),
            cm.Waypoint(lat: 47.378, lng: 8.55),
          ],
          distanceMetres: 8000,
        ),
      ]);
      await _pump(tester, s.runs, s.routes, s.prefs);
      await tester.pumpAndSettle();

      // Open the picker — tap the InputDecorator with the search prompt.
      await tester.tap(find.text('Search saved routes'));
      await tester.pumpAndSettle();

      // Both rows visible in the picker.
      expect(find.text('Park loop'), findsOneWidget);
      expect(find.text('River out-and-back'), findsOneWidget);

      // Filter to a single match.
      await tester.enterText(find.byType(TextField).first, 'river');
      await tester.pumpAndSettle();
      expect(find.text('River out-and-back'), findsOneWidget);
      expect(find.text('Park loop'), findsNothing);

      // Tap the surviving row → selection lands + picker pops.
      await tester.tap(find.text('River out-and-back'));
      await tester.pumpAndSettle();

      // Back on AddRunScreen: the InputDecorator now shows the route
      // name (the formatted distance follows the bullet separator).
      expect(find.textContaining('River out-and-back'), findsOneWidget);
      // Clear icon replaces the search icon when a route is selected.
      expect(find.byIcon(Icons.clear), findsOneWidget);
      expect(find.byIcon(Icons.search), findsNothing,
          reason: 'Search icon must flip to Clear once a route is picked.');

      // Tap Clear → selection cleared, search icon returns.
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('Search saved routes'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });
  });
}
