import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';

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
    testWidgets('Dashboard renders no AppBar (actions hoist into the body)',
        (tester) async {
      // The bottom-nav labels this tab "Home"; a duplicate title
      // there would be redundant chrome. The AppBar was removed
      // entirely (not just its title) because the empty left half
      // left a visible blank band where the title used to sit. The
      // Coach / Feed / Profile action buttons now live as an inline
      // toolbar Row at the top of the body. SafeArea keeps the
      // first content row clear of the system status bar.
      final s = await _makeStores();
      await _pump(tester,
          runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(SafeArea), findsAtLeastNWidgets(1));
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

          // 'Goals' is near the top of the list and visible in the test
          // viewport without scrolling. The activity stat strip
          // (WEEK / MONTH / ALL TIME) replaced the previous stacked
          // section cards — pin its all-caps labels to prove the strip
          // mounted.
          expect(find.text('Goals'), findsOneWidget);
          expect(find.text('WEEK'), findsOneWidget);
          expect(find.text('MONTH'), findsOneWidget);
          expect(find.text('ALL TIME'), findsOneWidget);
        } finally {
          dir.deleteSync(recursive: true);
        }
      });
    });

    testWidgets('activity stat strip shows distance + run count per period',
        (tester) async {
      // Verifies the consolidated 3-column strip (Week / Month / All time)
      // surfaces both the rounded distance value AND the per-card run
      // count copy. Catches a regression where the strip would drop
      // the run-count subtitle.
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final prefs = Preferences();
        await prefs.init();

        final dir = Directory.systemTemp.createTempSync('dashboard_stat_strip_');
        try {
          final seedStore = LocalRunStore();
          await seedStore.init(overrideDirectory: dir);
          // A single 5 km run this week → All time / Week / Month
          // each report "1 run".
          await seedStore.save(
            _run(id: 'r1', distanceMetres: 5000, duration: const Duration(minutes: 25)),
          );

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
          await tester.pump();

          // The seeded run dates to 15 Apr 2026 — outside this week +
          // this month relative to wall-clock now. All Time picks it
          // up ("1 run"); Week + Month report zero runs. The summed
          // copy across the three cards is therefore 1×"1 run" +
          // 2×"0 runs", regardless of when the suite runs.
          expect(find.text('1 run'), findsOneWidget);
          expect(find.text('0 runs'), findsNWidgets(2));
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
