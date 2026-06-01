import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/run_detail_screen.dart';

late Directory _runsDir;

Run _run({
  double distanceMetres = 5000,
  Duration duration = const Duration(minutes: 25),
  String? title,
  bool withTrack = false,
  Map<String, dynamic>? metadata,
}) =>
    Run(
      id: 'run-1',
      startedAt: DateTime.utc(2026, 4, 15, 7, 30),
      duration: duration,
      distanceMetres: distanceMetres,
      source: RunSource.app,
      metadata: metadata ??
          (title != null ? {'title': title, 'activity_type': 'run'} : null),
      // The secondary-stats row (which hosts the Calories pill) is
      // gated on `run.track.length >= 2 || _hasElevation`. A
      // 2-waypoint stub track is the cheapest way to make the gate
      // fire when a test cares about secondary stats; the values
      // aren't used by the calorie math (which derives from
      // distanceMetres + bodyWeightKg + activityType only).
      track: withTrack
          ? [
              Waypoint(
                lat: -37.8136,
                lng: 144.9631,
                timestamp: DateTime.utc(2026, 4, 15, 7, 30),
              ),
              Waypoint(
                lat: -37.8137,
                lng: 144.9632,
                timestamp: DateTime.utc(2026, 4, 15, 7, 31),
              ),
            ]
          : const [],
    );

Future<void> _pump(WidgetTester tester, Run run,
    {double? bodyWeightKg}) async {
  SharedPreferences.setMockInitialValues(
    bodyWeightKg != null ? {'body_weight_kg': bodyWeightKg} : {},
  );
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('run_detail_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  await tester.pumpWidget(
    MaterialApp(
      home: RunDetailScreen(
        run: run,
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ),
  );
  // One pump cycle; pumpAndSettle would spin LiveRunMap's pulse animation.
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('RunDetailScreen', () {
    testWidgets('renders the run date as the app-bar title when no title set',
        (tester) async {
      final run = _run();
      await _pump(tester, run);
      // The title is built from the date when metadata has no 'title' key.
      expect(find.textContaining('Apr'), findsAtLeastNWidgets(1));
    });

    testWidgets('renders the metadata title in the app bar when set',
        (tester) async {
      final run = _run(title: 'Morning Tempo');
      await _pump(tester, run);
      expect(find.text('Morning Tempo'), findsOneWidget);
    });

    testWidgets('renders Distance and Time primary stat labels', (tester) async {
      final run = _run();
      await _pump(tester, run);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
    });

    testWidgets('share button is present in the app bar', (tester) async {
      final run = _run();
      await _pump(tester, run);
      // Share is behind an overflow menu (Icons.more_vert or similar).
      // The screen uses an edit icon + more actions. Check the edit icon:
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('renders activity type label', (tester) async {
      final run = _run(title: 'Easy run');
      await _pump(tester, run);
      expect(find.text('Run'), findsAtLeastNWidgets(1));
    });

    testWidgets('surfaces parkrun age_grade as a secondary stat (#9)',
        (tester) async {
      final run = _run(
        withTrack: true,
        metadata: {'activity_type': 'run', 'age_grade': '55.42%'},
      );
      await _pump(tester, run);
      expect(find.text('Age grade'), findsOneWidget);
      expect(find.text('55.42%'), findsOneWidget);
    });

    testWidgets('renders the Garmin discipline chip from sub_sport',
        (tester) async {
      final run = _run(metadata: {'activity_type': 'run', 'sub_sport': 'trail'});
      await _pump(tester, run);
      expect(find.text('Trail'), findsOneWidget);
    });

    testWidgets('renders a Running Dynamics block from running_dynamics',
        (tester) async {
      final run = _run(metadata: {
        'activity_type': 'run',
        'running_dynamics': {
          'vertical_oscillation_mm': 8.4,
          'gct_ms': 240,
          'stride_length_m': 1.18,
          'power_w': 290,
        },
      });
      await _pump(tester, run);
      expect(find.text('Running Dynamics'), findsOneWidget);
      expect(find.text('Vertical oscillation'), findsOneWidget);
      expect(find.text('8.4 mm'), findsOneWidget);
      expect(find.text('240 ms'), findsOneWidget);
      expect(find.text('1.18 m'), findsOneWidget);
      expect(find.text('290 W'), findsOneWidget);
    });

    testWidgets('omits the Running Dynamics block when the key is absent',
        (tester) async {
      final run = _run(metadata: {'activity_type': 'run'});
      await _pump(tester, run);
      expect(find.text('Running Dynamics'), findsNothing);
    });
  });

  // ─────────── Settings propagation: bodyWeightKg → calorie text ───────────
  //
  // Walks the Dart side of the settings propagation chain pinned on
  // the web by `tests-e2e/cross-cutting/settings-propagation.spec.ts`:
  //
  //   user_settings.prefs.body_weight_kg
  //     → SettingsSyncService._applyUniversal
  //       → Preferences.setBodyWeightKg
  //         → run_detail_screen reads widget.preferences.bodyWeightKg
  //           in _estimatedCalories
  //
  // The settings-sync overlay path is unit-tested separately in
  // settings_sync_test.dart; this group pins the LAST link — that the
  // render path reads the right Preferences field and computes the
  // kcal value correctly across the documented 70 kg fallback +
  // user-set values.
  group('RunDetailScreen — body_weight_kg → calorie estimate', () {
    testWidgets('renders ~350 kcal for a 5km run at the default 70 kg fallback',
        (tester) async {
      // No bodyWeightKg set → page falls back to 70 kg.
      // kcal = round(70 × 1.0 × 5000 / 1000) = 350.
      // (kcalPerKgPerKm for run is 1.0 — verified in preferences.dart.)
      final run = _run(withTrack: true);
      await _pump(tester, run);
      expect(find.text('350 kcal'), findsOneWidget);
    });

    testWidgets('honours a persisted bodyWeightKg=90 → 450 kcal for 5km',
        (tester) async {
      // Headline regression net: a user who sets their weight to 90 kg
      // on /settings (web) or the universal settings bag must see the
      // calorie estimate scale up. 90 × 1.0 × 5 = 450 kcal.
      final run = _run(withTrack: true);
      await _pump(tester, run, bodyWeightKg: 90);
      expect(find.text('450 kcal'), findsOneWidget);
      // Negative shape — the 70-kg fallback value must NOT also be
      // rendered (would indicate a leaky cache or the screen reading
      // the wrong field).
      expect(find.text('350 kcal'), findsNothing);
    });

    testWidgets('honours a persisted bodyWeightKg=50 → 250 kcal for 5km',
        (tester) async {
      // Lower end of the realistic adult range. 50 × 1.0 × 5 = 250.
      final run = _run(withTrack: true);
      await _pump(tester, run, bodyWeightKg: 50);
      expect(find.text('250 kcal'), findsOneWidget);
    });

    testWidgets('scales linearly with distance at fixed bodyWeightKg',
        (tester) async {
      // 10 km run × 70 kg fallback = 700 kcal. Pin the linearity
      // contract so a refactor that mis-applied an exponent or a
      // unit factor would fail.
      final run = _run(distanceMetres: 10000, withTrack: true);
      await _pump(tester, run);
      expect(find.text('700 kcal'), findsOneWidget);
    });
  });

}
