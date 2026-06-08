// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/runs_screen.dart';
import '../lib/widgets/activity_timeline_list.dart';

/// Fake client: signed in, no remote runs. The History timeline is now built
/// from the LOCAL stores (not `fetchActivities`), so the test seeds those
/// directly; the fake just keeps `_fetchRemote` from hitting the network.
class _FakeApi extends ApiClient {
  @override
  String? get userId => 'u1';

  @override
  Future<List<Run>> getRuns({
    int limit = 50,
    DateTime? before,
    DateTime? updatedSince,
  }) async =>
      const [];
}

/// Records whether History asked the server to hydrate the gym store on mount.
/// `fetchGymWorkoutsWithSets` throws after counting so no `replaceFromServer`
/// write fires — a store write would deadlock the fake-async test zone.
class _HydrationProbeApi extends ApiClient {
  int gymFetches = 0;

  @override
  String? get userId => 'u1';

  @override
  Future<List<Run>> getRuns({
    int limit = 50,
    DateTime? before,
    DateTime? updatedSince,
  }) async =>
      const [];

  @override
  Future<List<({Map<String, dynamic> workout, List<Map<String, dynamic>> sets})>>
      fetchGymWorkoutsWithSets({int limit = 50}) async {
    gymFetches++;
    throw StateError('probe: server unavailable');
  }
}

void main() {
  setUpAll(() => initializeDateFormatting());

  final tmpDirs = <Directory>[];
  tearDown(() {
    for (final d in tmpDirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    tmpDirs.clear();
  });

  Directory tmp(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    tmpDirs.add(d);
    return d;
  }

  Run runRow(String id, {double dist = 5000, int dur = 1500}) => Run(
        id: id,
        startedAt: DateTime.now(),
        duration: Duration(seconds: dur),
        distanceMetres: dist,
        source: RunSource.app,
      );

  ({Map<String, dynamic> workout, List<Map<String, dynamic>> sets}) liftRow(
    String id,
    String title, {
    int sets = 1,
  }) =>
      (
        workout: {'id': id, 'title': title, 'started_at': DateTime.now().toUtc().toIso8601String()},
        sets: [
          for (var i = 0; i < sets; i++)
            {'exercise_name': 'Squat', 'set_index': i, 'reps': 5, 'weight_kg': 100},
        ],
      );

  Map<String, dynamic> mealRow(String id, String name, {num cal = 500}) => {
        'id': id,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'item_name': name,
        'calories': cal,
      };

  /// Mount RunsScreen as the History tab, seeding the local stores (the
  /// timeline's data source). `withGym: false` mounts it run-only (no gym/food
  /// store) — the graceful-degradation path that stays the inline run list.
  Future<void> pump(
    WidgetTester tester, {
    List<Run> runs = const [],
    List<({Map<String, dynamic> workout, List<Map<String, dynamic>> sets})> lifts = const [],
    List<Map<String, dynamic>> meals = const [],
    bool withGym = true,
    ApiClient? api,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('runs_tl_'));
    LocalGymStore? gymStore;
    LocalFoodStore? foodStore;
    if (withGym) {
      gymStore = LocalGymStore();
      await gymStore.init(overrideDirectory: tmp('gym_tl_'));
      foodStore = LocalFoodStore();
      await foodStore.init(overrideDirectory: tmp('food_tl_'));
    }
    // Store writes do real async file I/O that deadlocks the fake-async test
    // zone — seed inside runAsync (see CLAUDE.md gotcha).
    await tester.runAsync(() async {
      if (runs.isNotEmpty) await runStore.saveManyFromRemote(runs);
      if (lifts.isNotEmpty) await gymStore!.replaceFromServer(lifts);
      if (meals.isNotEmpty) await foodStore!.replaceFromServer(meals);
    });

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunsScreen(
        apiClient: api ?? _FakeApi(),
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
        gymStore: gymStore,
        foodStore: foodStore,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('chips appear once a second modality has data (from local stores)',
      (tester) async {
    await pump(tester, runs: [runRow('r1')], lifts: [liftRow('l1', 'Push day')], meals: [
      mealRow('m1', 'Oats'),
    ]);
    expect(find.text('Lifts'), findsOneWidget);
    expect(find.text('Meals'), findsOneWidget);
    // The lift shows on the timeline in the default All view.
    expect(find.text('Push day'), findsOneWidget);
  });

  testWidgets('every chip stays on the unified timeline, filtered by kind',
      (tester) async {
    // The Runs chip is a timeline filtered to runs (mirroring web), NOT the
    // inline run list — so the ActivityTimelineList stays mounted on every
    // chip and each chip shows only its kind.
    await pump(tester,
        runs: [runRow('r1')],
        lifts: [liftRow('l1', 'Leg day')],
        meals: [mealRow('m1', 'Rice bowl')]);
    // Default All view shows all three kinds.
    expect(find.byType(ActivityTimelineList), findsOneWidget);
    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('Rice bowl'), findsOneWidget);

    // Tap Runs → STILL the timeline, filtered to runs (lift + meal drop out).
    await tester.tap(find.text('Runs'));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityTimelineList), findsOneWidget);
    expect(find.text('Leg day'), findsNothing);
    expect(find.text('Rice bowl'), findsNothing);

    // Tap Lifts → only the lift shows.
    await tester.tap(find.text('Lifts'));
    await tester.pumpAndSettle();
    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('Rice bowl'), findsNothing);
  });

  testWidgets('a single-modality tab shows a "View all" link; All does not',
      (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await pump(tester,
        runs: [runRow('r1')],
        lifts: [liftRow('l1', 'Leg day')],
        meals: [mealRow('m1', 'Rice bowl')]);
    // All view is cross-modal — no single destination, so no View-all link.
    expect(find.text(l10n.historyViewAll), findsNothing);
    // Each single-modality tab surfaces the View-all link (→ its full page).
    for (final chip in ['Runs', 'Lifts', 'Meals']) {
      await tester.tap(find.text(chip));
      await tester.pumpAndSettle();
      expect(find.text(l10n.historyViewAll), findsOneWidget,
          reason: 'View all should show under the $chip tab');
    }
  });

  testWidgets('add FAB follows the active chip: All picker, then per-modality',
      (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await pump(tester,
        runs: [runRow('r1')],
        lifts: [liftRow('l1', 'Leg day')],
        meals: [mealRow('m1', 'Rice bowl')]);

    // All view → a generic "Log" FAB (mirrors web's run/lift/meal picker).
    final fab = find.byType(FloatingActionButton);
    expect(find.descendant(of: fab, matching: find.text(l10n.logSheetTitle)),
        findsOneWidget);

    // Tapping it opens the run/lift/meal picker sheet.
    await tester.tap(fab);
    await tester.pumpAndSettle();
    expect(find.text(l10n.logRun), findsOneWidget);
    expect(find.text(l10n.logLift), findsOneWidget);
    expect(find.text(l10n.logFood), findsOneWidget);
    // Dismiss the sheet without picking.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // Runs chip → the manual Add-run FAB.
    await tester.tap(find.text('Runs'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: fab, matching: find.text(l10n.historyAddRun)),
        findsOneWidget);

    // Lifts chip → adds a lift straight away.
    await tester.tap(find.text('Lifts'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: fab, matching: find.text(l10n.logLift)),
        findsOneWidget);

    // Meals chip → logs food.
    await tester.tap(find.text('Meals'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: fab, matching: find.text(l10n.logFood)),
        findsOneWidget);
  });

  testWidgets('run-only history keeps the plain Add-run FAB', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await pump(tester, runs: [runRow('r1')], withGym: false);
    expect(
        find.descendant(
            of: find.byType(FloatingActionButton),
            matching: find.text(l10n.historyAddRun)),
        findsOneWidget);
  });

  testWidgets('no chips when gym store is absent (run-only history)',
      (tester) async {
    // gymStore omitted → the screen stays the run-only inline history (the
    // offline-first / non-multi-modal graceful-degradation path).
    await pump(tester, runs: [runRow('r1')], withGym: false);
    expect(find.text('Lifts'), findsNothing);
    expect(find.byType(ActivityTimelineList), findsNothing);
  });

  testWidgets('History hydrates the gym store on mount (regression: no Lifts tab)',
      (tester) async {
    // Regression guard: History is now a first-class consumer of the local
    // gym/food stores, so it must hydrate them itself rather than assume the
    // dashboard / gym screen did. Without this the Lifts tab never appeared
    // when History was the entry point. Assert it pulls the gym store fresh.
    final api = _HydrationProbeApi();
    await pump(tester, withGym: true, api: api);
    expect(api.gymFetches, greaterThan(0),
        reason: 'History should hydrate the gym store on mount');
  });
}
