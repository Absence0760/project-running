import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show StatGrid;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/run_detail_screen.dart';

/// A climbing track, so the three geometry-dependent cells (elevation gain,
/// elevation loss, grade-adjusted pace) all have a value.
List<Waypoint> _hillyTrack() {
  final t0 = DateTime.utc(2026, 4, 15, 7, 30);
  return [
    for (var i = 0; i <= 40; i++)
      Waypoint(
        lat: -37.8136 + i * 0.0009,
        lng: 144.9631,
        elevationMetres: i <= 20 ? 10.0 + i * 6 : 10.0 + (40 - i) * 6,
        timestamp: t0.add(Duration(seconds: i * 30)),
      ),
  ];
}

Run _run({
  required List<Waypoint> track,
  Map<String, dynamic> metadata = const {'activity_type': 'run'},
  double distanceMetres = 5000,
  Duration duration = const Duration(minutes: 23),
}) =>
    Run(
      id: 'run-secondary-stats',
      startedAt: DateTime.utc(2026, 4, 15, 7, 30),
      duration: duration,
      distanceMetres: distanceMetres,
      source: RunSource.app,
      metadata: metadata,
      track: track,
    );

Future<void> _pump(WidgetTester tester, Run run) async {
  SharedPreferences.setMockInitialValues({'body_weight_kg': 72.0});
  final prefs = Preferences();
  await prefs.init();

  final dir = Directory.systemTemp.createTempSync('run_detail_secondary_');
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

const _geometryLabels = ['Elev Gain', 'Elev Loss', 'Grade-Adj. Pace'];
const _rowLabels = ['Calories', 'Steps', 'Cadence', 'Avg HR', 'Age grade'];

void main() {
  group('run detail secondary stats', () {
    testWidgets('a run with a track and full data renders every cell',
        (tester) async {
      tester.view.physicalSize = const Size(360, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(
        tester,
        _run(
          track: _hillyTrack(),
          metadata: const {
            'activity_type': 'run',
            'steps': 5432,
            'cadence_spm': 172,
            'avg_bpm': 142,
            'age_grade': '68.4%',
          },
        ),
      );
      tester.takeException();

      for (final label in [..._geometryLabels, ..._rowLabels]) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
    });

    testWidgets(
        'a track-less Health Connect import still renders heart rate, steps, '
        'cadence and calories', (tester) async {
      tester.view.physicalSize = const Size(360, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // What `health_connect_importer.dart` writes when the source app
      // released a workout summary but no GPS route: an empty track beside a
      // real average heart rate.
      await _pump(
        tester,
        _run(
          track: const [],
          metadata: const {
            'activity_type': 'run',
            'imported_from': 'health_connect',
            'steps': 5432,
            'avg_bpm': 142,
            'age_grade': '68.4%',
          },
        ),
      );
      tester.takeException();

      for (final label in _rowLabels) {
        expect(find.text(label), findsOneWidget,
            reason: '$label needs no geometry and should survive a bare '
                'summary import');
      }
      expect(find.text('142 bpm'), findsOneWidget);
      for (final label in _geometryLabels) {
        expect(find.text(label), findsNothing,
            reason: '$label genuinely needs a track');
      }
    });

    testWidgets('a suppressed heart-rate average still reports its coverage '
        'on a track-less run', (tester) async {
      tester.view.physicalSize = const Size(360, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // decisions § 1083: the Wear recorder withholds `avg_bpm` under 0.5
      // coverage and records the coverage instead. That record is metadata,
      // so it survives an import with no route.
      await _pump(
        tester,
        _run(
          track: const [],
          metadata: const {'activity_type': 'run', 'hr_coverage': 0.34},
        ),
      );
      tester.takeException();

      expect(find.text('Avg HR'), findsOneWidget);
      expect(find.text('34% covered'), findsOneWidget);
    });

    testWidgets('a run with nothing to report renders no secondary section',
        (tester) async {
      tester.view.physicalSize = const Size(360, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Recording started and stopped before the runner moved: no track, no
      // metadata, and a distance the calorie estimate cannot use.
      await _pump(
        tester,
        _run(
          track: const [],
          distanceMetres: 0,
          duration: const Duration(seconds: 30),
        ),
      );
      tester.takeException();

      for (final label in [..._geometryLabels, ..._rowLabels]) {
        expect(find.text(label), findsNothing,
            reason: '$label has no value on this run');
      }
      // Only the primary grid — the secondary section collapses rather than
      // leaving an empty frame.
      expect(find.byType(StatGrid), findsOneWidget);
    });

    testWidgets('calories are absent rather than 0 when the estimate is '
        'unusable', (tester) async {
      tester.view.physicalSize = const Size(360, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(
        tester,
        _run(
          track: const [],
          distanceMetres: 0,
          duration: const Duration(seconds: 30),
          metadata: const {'activity_type': 'run', 'avg_bpm': 142},
        ),
      );
      tester.takeException();

      expect(find.text('Avg HR'), findsOneWidget);
      expect(find.text('Calories'), findsNothing);
      expect(find.textContaining('0 kcal'), findsNothing);
    });
  });
}
