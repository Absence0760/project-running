// `hr_coverage` had a writer and no reader, so a run whose average heart rate
// the Wear recorder SUPPRESSED (below 0.5 coverage, decisions § 1083) rendered
// exactly like a run recorded with no strap at all: nothing. These pin the
// three states apart — a trustworthy average, a suppressed one, and no heart
// rate on record (decisions § 1094).

import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/run_detail_screen.dart';

/// The secondary-stat grid is gated on the run carrying geometry
/// (`track.length >= 2 || _hasElevation`), so every fixture here needs a
/// track even though nothing these tests assert depends on one.
List<Waypoint> _track() {
  final t0 = DateTime.utc(2026, 4, 15, 7, 30);
  return [
    for (var i = 0; i <= 10; i++)
      Waypoint(
        lat: -37.8136 + i * 0.0009,
        lng: 144.9631,
        timestamp: t0.add(Duration(seconds: i * 30)),
      ),
  ];
}

Run _run(Map<String, Object?> metadata) => Run(
      id: 'run-hr',
      startedAt: DateTime.utc(2026, 4, 15, 7, 30),
      duration: const Duration(minutes: 23),
      distanceMetres: 5000,
      source: RunSource.app,
      metadata: {'activity_type': 'run', ...metadata},
      track: _track(),
    );

Future<void> _pump(WidgetTester tester, Run run) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  final dir = Directory.systemTemp.createTempSync('run_detail_hr_coverage_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: dir);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunDetailScreen(
        run: run,
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ),
  );
  // Timed pumps only — pumpAndSettle spins LiveRunMap's pulse animation.
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  testWidgets('a run with no heart rate on record says nothing about it',
      (tester) async {
    await _pump(tester, _run(const {}));

    expect(find.text('Avg HR'), findsNothing);
    expect(find.text('HR coverage'), findsNothing);
  });

  testWidgets('an average with no coverage record renders as it always did',
      (tester) async {
    await _pump(tester, _run(const {'avg_bpm': 142}));

    expect(find.text('Avg HR'), findsOneWidget);
    expect(find.text('142 bpm'), findsOneWidget);
    expect(find.text('HR coverage'), findsNothing);
  });

  testWidgets('a partly-covered average is qualified by its coverage',
      (tester) async {
    await _pump(tester, _run(const {'avg_bpm': 142, 'hr_coverage': 0.82}));

    expect(find.text('142 bpm'), findsOneWidget);
    expect(find.text('HR coverage'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
  });

  testWidgets('full coverage adds nothing, so it is not drawn',
      (tester) async {
    await _pump(tester, _run(const {'avg_bpm': 142, 'hr_coverage': 1.0}));

    expect(find.text('142 bpm'), findsOneWidget);
    expect(find.text('HR coverage'), findsNothing);
  });

  testWidgets('a suppressed average says how little the sensor covered',
      (tester) async {
    await _pump(tester, _run(const {'hr_coverage': 0.12}));

    // The average-heart-rate slot is occupied rather than empty: the reason
    // the number is missing is the whole point of the record.
    expect(find.text('Avg HR'), findsOneWidget);
    expect(find.text('12% covered'), findsOneWidget);
  });

  testWidgets('zero coverage is a measurement, not an absence',
      (tester) async {
    await _pump(tester, _run(const {'hr_coverage': 0}));

    expect(find.text('0% covered'), findsOneWidget);
  });

  testWidgets('a coverage value outside 0..1 is not a coverage',
      (tester) async {
    await _pump(tester, _run(const {'hr_coverage': 1.4}));

    expect(find.text('Avg HR'), findsNothing);
    expect(find.textContaining('covered'), findsNothing);
  });

  testWidgets('a non-numeric coverage is ignored rather than thrown on',
      (tester) async {
    await _pump(tester, _run(const {'hr_coverage': '0.5'}));

    expect(find.text('Avg HR'), findsNothing);
    expect(find.textContaining('covered'), findsNothing);
  });
}
