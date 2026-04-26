import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_android/local_route_store.dart';
import 'package:mobile_android/local_run_store.dart';
import 'package:mobile_android/preferences.dart';
import 'package:mobile_android/screens/runs_screen.dart';
import 'package:mobile_android/screens/add_run_screen.dart';

late Directory _runsDir;

Run _run({
  String id = 'run-1',
  double distanceMetres = 5000,
  Duration duration = const Duration(minutes: 25),
}) =>
    Run(
      id: id,
      startedAt: DateTime.utc(2026, 4, 15, 7, 30),
      duration: duration,
      distanceMetres: distanceMetres,
      source: RunSource.app,
    );

Future<({LocalRunStore runStore, LocalRouteStore routeStore, Preferences prefs})>
    _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  // LocalRouteStore used without init() — routes returns [] by default.
  final routeStore = LocalRouteStore();

  return (runStore: runStore, routeStore: routeStore, prefs: prefs);
}

Future<void> _pump(
  WidgetTester tester, {
  required LocalRunStore runStore,
  required LocalRouteStore routeStore,
  required Preferences prefs,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RunsScreen(
        apiClient: null,
        runStore: runStore,
        routeStore: routeStore,
        preferences: prefs,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('RunsScreen', () {
    testWidgets('renders Runs app-bar title', (tester) async {
      final s = await _makeStores();
      await _pump(tester, runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.text('Runs'), findsOneWidget);
    });

    testWidgets('shows empty state when store has no runs', (tester) async {
      final s = await _makeStores();
      await _pump(tester, runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      // The _EmptyRuns widget is rendered; no run tiles.
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('FAB is present with Add run label', (tester) async {
      final s = await _makeStores();
      await _pump(tester, runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Add run'), findsOneWidget);
    });

    testWidgets('FAB tap navigates to AddRunScreen', (tester) async {
      final s = await _makeStores();
      await _pump(tester, runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(AddRunScreen), findsOneWidget);
    });

    testWidgets('cloud_off icon shown when apiClient is null', (tester) async {
      final s = await _makeStores();
      await _pump(tester, runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });
}
