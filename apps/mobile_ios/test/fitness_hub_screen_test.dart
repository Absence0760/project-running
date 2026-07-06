// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

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
import '../lib/screens/fitness_hub_screen.dart';
import '../lib/screens/gym_screen.dart';
import '../lib/screens/nutrition_screen.dart';
import '../lib/training_service.dart';
import '../lib/widgets/activity_timeline_list.dart';

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
    String title,
  ) =>
      (
        workout: {
          'id': id,
          'title': title,
          'started_at': DateTime.now().toUtc().toIso8601String(),
        },
        sets: [
          {'exercise_name': 'Squat', 'set_index': 0, 'reps': 5, 'weight_kg': 100},
        ],
      );

  // api: null keeps Gym/Nutrition/Runs from hitting the (uninitialised)
  // Supabase server on mount — the timeline is assembled purely from the
  // seeded local stores, which is the offline-first contract.
  Future<void> pump(
    WidgetTester tester, {
    List<Run> runs = const [],
    List<({Map<String, dynamic> workout, List<Map<String, dynamic>> sets})> lifts =
        const [],
    List<Map<String, dynamic>> meals = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('hub_runs_'));
    final routeStore = LocalRouteStore();
    await routeStore.init(overrideDirectory: tmp('hub_routes_'));
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tmp('hub_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tmp('hub_food_'));

    // Store writes do real async file I/O that deadlocks the fake-async test
    // zone — seed inside runAsync (CLAUDE.md gotcha).
    await tester.runAsync(() async {
      if (runs.isNotEmpty) await runStore.saveManyFromRemote(runs);
      if (lifts.isNotEmpty) await gymStore.replaceFromServer(lifts);
      if (meals.isNotEmpty) {
        await foodStore.replaceFromServer(meals);
      }
    });

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FitnessHubScreen(
        apiClient: null,
        runStore: runStore,
        routeStore: routeStore,
        gymStore: gymStore,
        foodStore: foodStore,
        preferences: prefs,
        training: TrainingService(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the four sub-tabs All / Runs / Gym / Nutrition',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.tabs.length, 4);
    final labels = [
      for (final t in tabBar.tabs) (t as Tab).text,
    ];
    expect(labels, ['All', 'Runs', 'Gym', 'Nutrition']);
  });

  testWidgets('All tab shows the unified timeline when stores are seeded',
      (tester) async {
    await pump(tester,
        runs: [runRow('r1')], lifts: [liftRow('l1', 'Leg day')]);
    // The All tab hosts RunsScreen WITH the gym+food stores → the unified
    // cross-modal timeline (the absorbed History content), with its own kind
    // chips suppressed (the hub TabBar owns that axis).
    expect(find.byType(ActivityTimelineList), findsOneWidget);
    expect(find.text('Leg day'), findsOneWidget);
    // No in-screen kind chips — the hub TabBar is the single kind selector.
    expect(find.text('Lifts'), findsNothing);
  });

  testWidgets('Runs sub-tab surfaces the relocated Routes entry',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    // The run-management surface carries a Routes action (relocated out of
    // Social) — a route icon button in its AppBar.
    expect(find.byIcon(Icons.route), findsOneWidget);
  });

  testWidgets('Runs sub-tab hides the cloud sync slot; All keeps it',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    // All tab (api: null, signed out) renders the cloud slot's offline state.
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    // The Runs sub-tab passes showSyncActions: false — no cloud slot at all,
    // in any of its three states.
    expect(find.byIcon(Icons.cloud_off), findsNothing);
    expect(find.byIcon(Icons.cloud_upload), findsNothing);
    expect(find.byIcon(Icons.cloud_download), findsNothing);
  });

  testWidgets(
      'Runs sub-tab titles itself "Runs" and moves the range status into '
      'the filter header', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    // "Runs" appears twice: the hub's tab label + the sub-tab's static
    // AppBar title (matching the Gym / Nutrition siblings).
    expect(find.text('Runs'), findsNWidgets(2));
    // The range + count status the title otherwise carries renders as the
    // filter header's leading row instead (default range = This week).
    expect(find.text('This week · 1 run'), findsOneWidget);
  });

  testWidgets('Gym sub-tab hosts GymScreen with its empty-onboarding state',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Gym').first);
    await tester.pumpAndSettle();
    expect(find.byType(GymScreen), findsOneWidget);
  });

  testWidgets('Nutrition sub-tab hosts NutritionScreen', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Nutrition').first);
    await tester.pumpAndSettle();
    expect(find.byType(NutritionScreen), findsOneWidget);
  });
}
