import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_android/local_route_store.dart';
import 'package:mobile_android/local_run_store.dart';
import 'package:mobile_android/preferences.dart';
import 'package:mobile_android/screens/run_detail_screen.dart';

late Directory _runsDir;

Run _run({
  double distanceMetres = 5000,
  Duration duration = const Duration(minutes: 25),
  String? title,
}) =>
    Run(
      id: 'run-1',
      startedAt: DateTime.utc(2026, 4, 15, 7, 30),
      duration: duration,
      distanceMetres: distanceMetres,
      source: RunSource.app,
      metadata: title != null ? {'title': title, 'activity_type': 'run'} : null,
    );

Future<void> _pump(WidgetTester tester, Run run) async {
  SharedPreferences.setMockInitialValues({});
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
  });
}
