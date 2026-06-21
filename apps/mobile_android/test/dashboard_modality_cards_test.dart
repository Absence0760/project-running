import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/goals.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/widgets/gym_summary_card.dart';
import '../lib/widgets/nutrition_rings_card.dart';

late Directory _runsDir;
late Directory _gymDir;
late Directory _foodDir;

Future<({
  LocalRunStore runStore,
  LocalRouteStore routeStore,
  LocalGymStore gymStore,
  LocalFoodStore foodStore,
  Preferences prefs,
})> _stores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  // Seed a goal so the dashboard renders its card stack instead of the
  // run-less welcome empty state.
  await prefs.upsertGoal(
      const RunGoal(id: 'g1', period: GoalPeriod.week, distanceMetres: 5000));

  _runsDir = Directory.systemTemp.createTempSync('dash_runs_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);
  final routeStore = LocalRouteStore();
  _gymDir = Directory.systemTemp.createTempSync('dash_gym_');
  final gymStore = LocalGymStore();
  await gymStore.init(overrideDirectory: _gymDir);
  _foodDir = Directory.systemTemp.createTempSync('dash_food_');
  final foodStore = LocalFoodStore();
  await foodStore.init(overrideDirectory: _foodDir);

  return (
    runStore: runStore,
    routeStore: routeStore,
    gymStore: gymStore,
    foodStore: foodStore,
    prefs: prefs,
  );
}

Future<void> _pump(WidgetTester tester, dynamic s) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DashboardScreen(
        apiClient: null,
        training: null,
        runStore: s.runStore,
        routeStore: s.routeStore,
        gymStore: s.gymStore,
        foodStore: s.foodStore,
        preferences: s.prefs,
        settingsSync: null,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() {
    for (final d in [_runsDir, _gymDir, _foodDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  group('Dashboard today-modality cards', () {
    testWidgets('self-hide when nothing logged today', (tester) async {
      final s = await _stores();
      await _pump(tester, s);
      expect(find.byType(GymSummaryCard), findsNothing);
      expect(find.byType(NutritionRingsCard), findsNothing);
    });

    testWidgets("a lift logged today surfaces the gym summary card",
        (tester) async {
      final s = await _stores();
      await tester.runAsync(() async {
        await s.gymStore.createLocal(
          title: 'Push day',
          startedAt: DateTime.now(),
          sets: const [
            (exerciseName: 'Bench', reps: 8, weightKg: 60.0, rpe: null, setType: null, durationS: null, exerciseId: null),
          ],
        );
      });
      await _pump(tester, s);
      await tester.pump();
      expect(find.byType(GymSummaryCard), findsOneWidget);
      // No food logged → nutrition card still hidden.
      expect(find.byType(NutritionRingsCard), findsNothing);
    });
  });
}
