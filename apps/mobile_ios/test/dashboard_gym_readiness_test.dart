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
import '../lib/screens/dashboard_screen.dart';

Run _run(String id) => Run(
      id: id,
      startedAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      source: RunSource.app,
    );

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets(
      'a recent lift shows the gym-readiness note (factored in by default)',
      (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();

      final runDir = Directory.systemTemp.createTempSync('dash_readiness_run_');
      final gymDir = Directory.systemTemp.createTempSync('dash_readiness_gym_');
      try {
        final runStore = LocalRunStore();
        await runStore.init(overrideDirectory: runDir);
        await runStore.save(_run('r1'));

        final gymStore = LocalGymStore();
        await gymStore.init(overrideDirectory: gymDir);
        // A lift two days ago is inside the ~14-day fatigue window, so the note
        // (default: "factored in") must render.
        await gymStore.createLocal(
          startedAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
          sets: const [(exerciseName: 'Squat', reps: 5, weightKg: 140.0, rpe: null, durationS: null, exerciseId: null)],
        );

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DashboardScreen(
              runStore: runStore,
              routeStore: LocalRouteStore(),
              gymStore: gymStore,
              foodStore: LocalFoodStore(),
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final note = find.text('Recent gym sessions are factored into your fatigue.');
        // The note lives below the training-load chart deep in the scroll view.
        await tester.scrollUntilVisible(note, 300,
            scrollable: find.byType(Scrollable).first);
        expect(note, findsOneWidget);
      } finally {
        runDir.deleteSync(recursive: true);
        gymDir.deleteSync(recursive: true);
      }
    });
  });
}
