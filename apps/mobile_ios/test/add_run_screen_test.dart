import 'dart:io';

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
      expect(find.text('Hike'), findsOneWidget);
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
  });
}
