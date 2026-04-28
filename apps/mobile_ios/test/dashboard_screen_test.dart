import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_android/local_route_store.dart';
import 'package:mobile_android/local_run_store.dart';
import 'package:mobile_android/preferences.dart';
import 'package:mobile_android/screens/dashboard_screen.dart';

Directory? _runsDir;

// Minimal Run fixture — only fields that LocalRunStore.save() and the
// dashboard stats loop actually access.
Run _run({
  required String id,
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

  _runsDir = Directory.systemTemp.createTempSync('dashboard_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir!);

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
      home: DashboardScreen(
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
    final d = _runsDir;
    if (d != null && d.existsSync()) d.deleteSync(recursive: true);
    _runsDir = null;
  });

  group('DashboardScreen', () {
    testWidgets('renders Dashboard app-bar title', (tester) async {
      final s = await _makeStores();
      await _pump(tester,
          runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('shows welcome empty state when runs and goals are both empty',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester,
          runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.text('Welcome!'), findsOneWidget);
      expect(find.text('Start your first run from the Run tab'), findsOneWidget);
    });

    testWidgets('empty state has a Set a goal button', (tester) async {
      final s = await _makeStores();
      await _pump(tester,
          runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.text('Set a goal'), findsOneWidget);
    });

    testWidgets('shows section headers when store has runs', (tester) async {
      // Seed the store on disk before the screen sees it so the notifier
      // never fires during the pump.
      //
      // Notifier-loop hazard: do NOT save() into a store that the widget is
      // already listening to — that fires _onRunStoreChanged → setState →
      // rebuild inside pump and can cause pumpAndSettle to hang.
      //
      // tester.runAsync is used here because _loadAll() inside
      // LocalRunStore.init() uses Future.wait over real file I/O, and
      // pump() alone can leave those futures unresolved in the fake-async
      // zone, causing the test to hang.
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final prefs = Preferences();
        await prefs.init();

        final dir = Directory.systemTemp.createTempSync('dashboard_with_runs_');
        try {
          final seedStore = LocalRunStore();
          await seedStore.init(overrideDirectory: dir);
          await seedStore.save(
            _run(id: 'r1', distanceMetres: 5000, duration: const Duration(minutes: 25)),
          );

          // Fresh store reads from the same directory; _loadAll runs once
          // during init() so the screen starts with the run in memory.
          final runStore = LocalRunStore();
          await runStore.init(overrideDirectory: dir);

          await tester.pumpWidget(
            MaterialApp(
              home: DashboardScreen(
                runStore: runStore,
                routeStore: LocalRouteStore(),
                preferences: prefs,
              ),
            ),
          );
          // Two pumps: first processes the initial frame, second processes
          // any microtasks that the first frame scheduled (e.g. layout callbacks).
          await tester.pump();
          await tester.pump();

          // 'Goals' and 'This Week' are near the top of the list and should
          // be visible in the test viewport without scrolling.
          expect(find.text('Goals'), findsOneWidget);
          expect(find.text('This Week'), findsOneWidget);
        } finally {
          dir.deleteSync(recursive: true);
        }
      });
    });

    testWidgets('does not show Personal Bests section when runs have no track',
        (tester) async {
      // A run with distanceMetres == 0 has no GPS track, so fastestWindowOf
      // returns null and there is no longest-run candidate — hasAnyPb stays
      // false. Personal Bests section must therefore be absent.
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final prefs = Preferences();
        await prefs.init();

        final dir = Directory.systemTemp.createTempSync('dashboard_no_pb_');
        try {
          final seedStore = LocalRunStore();
          await seedStore.init(overrideDirectory: dir);
          await seedStore.save(_run(id: 'r2', distanceMetres: 0));

          final runStore = LocalRunStore();
          await runStore.init(overrideDirectory: dir);

          await tester.pumpWidget(
            MaterialApp(
              home: DashboardScreen(
                runStore: runStore,
                routeStore: LocalRouteStore(),
                preferences: prefs,
              ),
            ),
          );
          await tester.pump();

          expect(find.text('Personal Bests'), findsNothing);
        } finally {
          dir.deleteSync(recursive: true);
        }
      });
    });
  });
}
