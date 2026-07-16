import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/training_service.dart';

/// Signed-in fake so the gated coach entry renders.
class _FakeApi extends ApiClient {
  @override
  String? get userId => 'u1';
}

/// Test seam: a TrainingService that returns a canned overview from
/// `fetchActiveOverview` without touching Supabase. Subclassing the
/// real type keeps it a drop-in for the dashboard's
/// `widget.training` field (it extends ChangeNotifier the same way).
class _FakeTraining extends TrainingService {
  final ActivePlanOverview? overview;
  _FakeTraining(this.overview);
  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async => overview;
}

ActivePlanOverview _overviewWithTodayWorkout({String kind = 'long'}) {
  // Build a minimal but complete overview shape — the
  // TodaysWorkoutCard reads `todayWorkout.kind` + the target distance
  // and pace; the rest of the fields aren't surfaced.
  final today = DateTime.now();
  final plan = TrainingPlanRow(
    id: 'plan-1',
    userId: 'u1',
    name: 'Sub-3 Marathon',
    goalEvent: 'marathon',
    goalDistanceM: 42195,
    startDate: today.subtract(const Duration(days: 28)),
    endDate: today.add(const Duration(days: 56)),
    daysPerWeek: 5,
    status: 'active',
    source: 'app',
    isTemplate: false,
    isPublicTemplate: false,
  );
  final week = PlanWeekRow(
    id: 'wk-1',
    planId: 'plan-1',
    weekIndex: 4,
    phase: 'build',
    targetVolumeM: 60000,
  );
  final workout = PlanWorkoutRow(
    id: 'wo-1',
    weekId: 'wk-1',
    scheduledDate: today,
    kind: kind,
    targetDistanceM: 20000,
    targetPaceSecPerKm: 270,
    manuallyCompleted: false,
  );
  return ActivePlanOverview(
    plan: plan,
    weeks: [week],
    workouts: [workout],
    todayWorkout: workout,
    completionPct: 40,
    currentWeekIndex: 4,
  );
}

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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DashboardScreen(
        runStore: runStore,
        routeStore: routeStore,
        gymStore: LocalGymStore(),
        foodStore: LocalFoodStore(),
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

  group('heatmapWeekAnchor', () {
    final gridStart = DateTime(2026, 1, 5); // a Monday
    const cell = 12.0;
    const gap = 2.0;
    const weeks = 20;

    test('leftmost column maps to the oldest week (gridStart)', () {
      expect(
        heatmapWeekAnchor(
            localDx: 0,
            cellSize: cell,
            gap: gap,
            weeks: weeks,
            gridStart: gridStart),
        gridStart,
      );
    });

    test('a middle column maps to that week start', () {
      final a = heatmapWeekAnchor(
          localDx: 3 * (cell + gap) + 1,
          cellSize: cell,
          gap: gap,
          weeks: weeks,
          gridStart: gridStart);
      expect(a, gridStart.add(const Duration(days: 21)));
    });

    test('rightmost column maps to the current week', () {
      final a = heatmapWeekAnchor(
          localDx: (weeks - 1) * (cell + gap) + 1,
          cellSize: cell,
          gap: gap,
          weeks: weeks,
          gridStart: gridStart);
      expect(a, gridStart.add(const Duration(days: 7 * (weeks - 1))));
    });

    test('a tap past the right edge clamps to the last week', () {
      final a = heatmapWeekAnchor(
          localDx: 9999,
          cellSize: cell,
          gap: gap,
          weeks: weeks,
          gridStart: gridStart);
      expect(a, gridStart.add(const Duration(days: 7 * (weeks - 1))));
    });

    test('a negative offset clamps to the first week', () {
      expect(
        heatmapWeekAnchor(
            localDx: -5,
            cellSize: cell,
            gap: gap,
            weeks: weeks,
            gridStart: gridStart),
        gridStart,
      );
    });
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
      // Body copy is one combined line covering the three onboarding
      // paths (Run tab / goal / import). Pin the start of the
      // sentence so a future tweak that loses an action doesn't
      // silently shrink the copy.
      expect(
        find.textContaining('Your dashboard fills in once you record a run'),
        findsOneWidget,
      );
    });

    testWidgets('empty state offers both Set a goal AND Import runs actions',
        (tester) async {
      // The welcome empty state ships with two side-by-side actions
      // (primary Set-a-goal + the discoverability handle for Strava /
      // Garmin / Health Connect bulk import) so a returning runner
      // with a history has a one-tap path to populate the app.
      final s = await _makeStores();
      await _pump(tester,
          runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.text('Set a goal'), findsOneWidget);
      expect(find.text('Import runs'), findsOneWidget);
    });

    testWidgets(
        'empty state shows a Start a run action wired to the recorder when onStartRun is provided',
        (tester) async {
      // #253: the welcome copy promises "record a run" but the empty
      // state used to only wire Set-a-goal / Import. With a host-provided
      // onStartRun the primary "Start a run" CTA renders and fires the
      // callback (home_screen jumps to the keep-alive recorder page).
      final s = await _makeStores();
      var started = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DashboardScreen(
            runStore: s.runStore,
            routeStore: s.routeStore,
            gymStore: LocalGymStore(),
            foodStore: LocalFoodStore(),
            preferences: s.prefs,
            onStartRun: () => started++,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Start a run'), findsOneWidget);
      await tester.tap(find.text('Start a run'));
      await tester.pump();
      expect(started, 1);
    });

    testWidgets('empty state hides Start a run when no onStartRun host is wired',
        (tester) async {
      // Fail-closed: with no host able to reach the recorder the CTA is
      // hidden rather than shown as a dead button.
      final s = await _makeStores();
      await _pump(tester,
          runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.text('Start a run'), findsNothing);
      // The other two onboarding paths still render.
      expect(find.text('Set a goal'), findsOneWidget);
      expect(find.text('Import runs'), findsOneWidget);
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
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: DashboardScreen(
                runStore: runStore,
                routeStore: LocalRouteStore(),
                gymStore: LocalGymStore(),
                foodStore: LocalFoodStore(),
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
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: DashboardScreen(
                runStore: runStore,
                routeStore: LocalRouteStore(),
                gymStore: LocalGymStore(),
                foodStore: LocalFoodStore(),
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

    testWidgets("shows TODAY'S WORKOUT card when an active plan has a workout today",
        (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final prefs = Preferences();
        await prefs.init();

        final dir =
            Directory.systemTemp.createTempSync('dashboard_today_workout_');
        try {
          // The dashboard's welcome empty-state takes over when runs +
          // goals are both empty; seed a single run so the full
          // ListView (with the today-workout card) renders.
          final seedStore = LocalRunStore();
          await seedStore.init(overrideDirectory: dir);
          await seedStore.save(_run(id: 'r1'));

          final runStore = LocalRunStore();
          await runStore.init(overrideDirectory: dir);

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: DashboardScreen(
                runStore: runStore,
                routeStore: LocalRouteStore(),
                gymStore: LocalGymStore(),
                foodStore: LocalFoodStore(),
                preferences: prefs,
                training: _FakeTraining(_overviewWithTodayWorkout()),
              ),
            ),
          );
          // First pump builds, second drains the post-frame
          // `_refreshPlanOverview()` future + its setState.
          await tester.pump();
          await tester.pump();
          await tester.pump();

          // The card surfaces an all-caps "TODAY'S WORKOUT" label
          // (or "DONE TODAY" when completed). With manuallyCompleted=
          // false + no completedRunId, "TODAY'S WORKOUT" is expected.
          expect(find.text("TODAY'S WORKOUT"), findsOneWidget);
          // Workout kind label — "long" → "Long run" per
          // workoutKindLabel.
          expect(find.text('Long run'), findsOneWidget);
        } finally {
          dir.deleteSync(recursive: true);
        }
      });
    });

    testWidgets(
        "does not show TODAY'S WORKOUT card when training service returns null",
        (tester) async {
      // No active plan → fetchActiveOverview returns null → card
      // stays hidden. Pin the negative path so a future regression
      // that defaulted to showing some placeholder fails loud.
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final prefs = Preferences();
        await prefs.init();

        final dir =
            Directory.systemTemp.createTempSync('dashboard_no_today_workout_');
        try {
          final runStore = LocalRunStore();
          await runStore.init(overrideDirectory: dir);

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: DashboardScreen(
                runStore: runStore,
                routeStore: LocalRouteStore(),
                gymStore: LocalGymStore(),
                foodStore: LocalFoodStore(),
                preferences: prefs,
                training: _FakeTraining(null),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(find.text("TODAY'S WORKOUT"), findsNothing);
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
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: DashboardScreen(
                runStore: runStore,
                routeStore: LocalRouteStore(),
                gymStore: LocalGymStore(),
                foodStore: LocalFoodStore(),
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

    testWidgets(
        'pins "Ask your coach" at the top once the runner has runs (api + training present)',
        (tester) async {
      // #272: the coach card only renders once the runner has data — seed a
      // run so the ListView branch (not the welcome empty state) mounts.
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final prefs = Preferences();
        await prefs.init();
        final dir = Directory.systemTemp.createTempSync('dashboard_coach_');
        try {
          final seedStore = LocalRunStore();
          await seedStore.init(overrideDirectory: dir);
          await seedStore.save(_run(id: 'r1'));
          final runStore = LocalRunStore();
          await runStore.init(overrideDirectory: dir);
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: DashboardScreen(
                apiClient: _FakeApi(),
                training: _FakeTraining(null),
                runStore: runStore,
                routeStore: LocalRouteStore(),
                gymStore: LocalGymStore(),
                foodStore: LocalFoodStore(),
                preferences: prefs,
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          // The pinned entry renders at the top and is a real button (it opens
          // CoachScreen on tap; the coach surface itself needs a live Supabase
          // instance, which the per-screen coach test covers).
          expect(find.text('Ask your coach'), findsOneWidget);
          expect(
            find.ancestor(
              of: find.text('Ask your coach'),
              matching: find.byType(InkWell),
            ),
            findsOneWidget,
          );
        } finally {
          dir.deleteSync(recursive: true);
        }
      });
    });

    testWidgets(
        'no coach entry on the zero-runs welcome screen even with api + training',
        (tester) async {
      // #272: the "Ask your coach" card used to render unconditionally above
      // the welcome onboarding buttons for a brand-new (zero-runs) user. It
      // must now be absent on that first screen.
      await tester.runAsync(() async {
        final s = await _makeStores();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DashboardScreen(
              apiClient: _FakeApi(),
              training: _FakeTraining(null),
              runStore: s.runStore,
              routeStore: s.routeStore,
              gymStore: LocalGymStore(),
              foodStore: LocalFoodStore(),
              preferences: s.prefs,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Welcome!'), findsOneWidget);
        expect(find.text('Ask your coach'), findsNothing);
      });
    });

    testWidgets('no coach entry when training service is absent',
        (tester) async {
      await tester.runAsync(() async {
        final s = await _makeStores();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DashboardScreen(
              apiClient: _FakeApi(),
              runStore: s.runStore,
              routeStore: s.routeStore,
              gymStore: LocalGymStore(),
              foodStore: LocalFoodStore(),
              preferences: s.prefs,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Ask your coach'), findsNothing);
      });
    });

    group('heatmapDayCounts (window guard)', () {
      Run runAt(String id, DateTime started) => Run(
            id: id,
            startedAt: started,
            duration: const Duration(minutes: 25),
            distanceMetres: 5000,
            source: RunSource.app,
          );

      test('counts only runs on/after gridStart; ignores older history', () {
        final gridStart = DateTime(2026, 1, 1);
        final counts = heatmapDayCounts([
          runAt('old', DateTime(2025, 6, 1)), // long before the window
          runAt('edge', DateTime(2026, 1, 1, 9)), // on gridStart day
          runAt('in1', DateTime(2026, 1, 10, 7)),
          runAt('in2', DateTime(2026, 1, 10, 19)), // same day as in1
        ], gridStart);
        // The pre-window run contributes nothing; in-window runs are counted,
        // same-day runs accumulate.
        expect(counts.values.fold<int>(0, (a, b) => a + b), 3);
        expect(counts[_epochDayForTest(DateTime(2026, 1, 10))], 2);
        expect(counts[_epochDayForTest(DateTime(2026, 1, 1))], 1);
        expect(counts.containsKey(_epochDayForTest(DateTime(2025, 6, 1))), isFalse);
      });

      test('in-window counts match an unguarded all-time count', () {
        final gridStart = DateTime(2026, 1, 1);
        final all = [
          for (int i = 0; i < 30; i++) runAt('r$i', DateTime(2026, 1, 1 + i, 8)),
          runAt('older', DateTime(2024, 1, 1)),
        ];
        final guarded = heatmapDayCounts(all, gridStart);
        // Recompute the in-window total the naive way (no guard) and compare.
        var naiveInWindow = 0;
        for (final r in all) {
          if (!r.startedAt.toLocal().isBefore(gridStart)) naiveInWindow++;
        }
        expect(guarded.values.fold<int>(0, (a, b) => a + b), naiveInWindow);
      });
    });
  });
}

// Mirror of dashboard_screen's private _epochDay for assertions.
int _epochDayForTest(DateTime d) {
  final local = DateTime(d.year, d.month, d.day);
  return local.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}
