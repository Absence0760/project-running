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
import '../lib/screens/global_segments_screen.dart';
import '../lib/screens/gym_screen.dart';
import '../lib/screens/nutrition_screen.dart';
import '../lib/screens/plans_screen.dart';
import '../lib/screens/races_screen.dart';
import '../lib/screens/routes_screen.dart';
import '../lib/training_service.dart';
import '../lib/widgets/activity_timeline_list.dart';
import '../lib/widgets/surface_peer_strip.dart';

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
    FitnessTab initialTab = FitnessTab.history,
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
        initialTab: initialTab,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the four sub-tabs History / Runs / Gym / Nutrition',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.tabs.length, 4);
    final labels = [
      for (final t in tabBar.tabs) (t as Tab).text,
    ];
    // The first tab used to read "All" over a child AppBar reading "History"
    // — two names for one surface, stacked (#666 I9). Every tab now agrees
    // with the screen it mounts.
    expect(labels, ['History', 'Runs', 'Gym', 'Nutrition']);
  });

  testWidgets('History tab shows the unified timeline when stores are seeded',
      (tester) async {
    await pump(tester,
        runs: [runRow('r1')], lifts: [liftRow('l1', 'Leg day')]);
    // The All tab hosts RunsScreen WITH the gym+food stores → the unified
    // cross-modal timeline (the absorbed History content), with its own kind
    // chips suppressed (the hub TabBar owns that axis).
    expect(find.byType(ActivityTimelineList), findsOneWidget);
    expect(find.text('Leg day'), findsOneWidget);
    // The tab and the AppBar 48dp below it now say the same thing. This is
    // the mount where the contradiction showed: the timeline title only
    // renders once a second modality has data (#666 I9).
    expect(find.text('History'), findsNWidgets(2));
    // No in-screen kind chips — the hub TabBar is the single kind selector.
    expect(find.text('Lifts'), findsNothing);
  });

  testWidgets('Runs sub-tab renders the labelled peer strip',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    // Every run-planning surface is a named peer, not a tooltip-only glyph.
    final strip = find.byType(SurfacePeerStrip);
    expect(strip, findsOneWidget);
    for (final label in ['Runs', 'Routes', 'Segments', 'Plans', 'Races']) {
      expect(find.descendant(of: strip, matching: find.text(label)),
          findsOneWidget);
    }
  });

  testWidgets('the Races peer opens the race calendar with no provider key',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(SurfacePeerStrip), matching: find.text('Races')));
    await tester.pumpAndSettle();
    // No RunSignUp / ChronoTrack key and no signed-in client: the calendar is
    // still reachable, it just has nothing to list.
    expect(find.byType(RacesScreen), findsOneWidget);
  });

  testWidgets('the Routes peer opens the relocated route library',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(SurfacePeerStrip), matching: find.text('Routes')));
    await tester.pumpAndSettle();
    expect(find.byType(RoutesScreen), findsOneWidget);
  });

  testWidgets('the Segments peer opens the famous-segment catalogue',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    final peer = find.descendant(
        of: find.byType(SurfacePeerStrip), matching: find.text('Segments'));
    await tester.ensureVisible(peer);
    await tester.tap(peer);
    await tester.pumpAndSettle();
    expect(find.byType(GlobalSegmentsScreen), findsOneWidget);
  });

  testWidgets('the Plans peer opens the training plan library', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(SurfacePeerStrip), matching: find.text('Plans')));
    await tester.pumpAndSettle();
    expect(find.byType(PlansScreen), findsOneWidget);
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
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    expect(find.byIcon(Icons.cloud_download), findsNothing);
  });

  testWidgets(
      'Runs sub-tab titles itself "Runs" and moves the range status into '
      'the filter header', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    // "Runs" appears three times: the hub's tab label, the sub-tab's static
    // AppBar title (matching the Gym / Nutrition siblings), and the current
    // peer in the surface strip.
    expect(find.text('Runs'), findsNWidgets(3));
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

  // `initialTab` was a raw int documented in a comment. No production caller
  // passed a non-default value, so the § 490 bug was not live here — but the
  // seam was the same shape that produced it, where a stale literal stays in
  // range after the tab set changes and the wrong tab opens in silence. With an
  // enum, out of range is unrepresentable; what is worth pinning instead is the
  // property no clamp could give.
  testWidgets('every FitnessTab opens its own tab, and the strip is exactly as '
      'long as the enum', (tester) async {
    for (final tab in FitnessTab.values) {
      // Unmount first — see the SocialTab twin: pumping another hub over the
      // previous one reuses the element and keeps its TabController.
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester, runs: [runRow('r1')], initialTab: tab);
      final tabBar = tester.widget<TabBar>(find.byType(TabBar).first);
      expect(tabBar.controller!.index, tab.index,
          reason: '$tab did not open its own tab');
      expect(tabBar.tabs.length, FitnessTab.values.length,
          reason: 'the strip and the enum disagree on how many tabs exist');
    }
    // Assert the population: an empty enum would satisfy the loop above.
    expect(FitnessTab.values.length, greaterThan(1));
  });
}
