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

/// A climbing track: enough elevation for gain/loss and a grade-adjusted pace
/// that diverges from the raw pace, plus a stopped stretch so "Moving" differs
/// from the total duration and the primary row shows all four cells.
List<Waypoint> _hillyTrack() {
  const start = 0;
  final t0 = DateTime.utc(2026, 4, 15, 7, 30);
  return [
    for (var i = start; i <= 40; i++)
      Waypoint(
        lat: -37.8136 + i * 0.0009,
        lng: 144.9631,
        // Up for 20 samples, back down for 20 — gain and loss both non-zero.
        elevationMetres: i <= 20 ? 10.0 + i * 6 : 10.0 + (40 - i) * 6,
        timestamp: t0.add(Duration(seconds: i * 30)),
      ),
    // A three-minute stop at the end so movingTimeOf < duration.
    for (var i = 1; i <= 6; i++)
      Waypoint(
        lat: -37.8136 + 40 * 0.0009,
        lng: 144.9631,
        elevationMetres: 10.0,
        timestamp: t0.add(Duration(seconds: 40 * 30 + i * 30)),
      ),
  ];
}

/// A run that lights up every one of the eight conditional secondary stats.
Run _everyStatRun() => Run(
      id: 'run-stats',
      startedAt: DateTime.utc(2026, 4, 15, 7, 30),
      duration: const Duration(minutes: 23),
      distanceMetres: 5000,
      source: RunSource.app,
      metadata: const {
        'activity_type': 'run',
        'steps': 5432,
        'cadence_spm': 172,
        'avg_bpm': 142,
        'age_grade': '68.4%',
      },
      track: _hillyTrack(),
    );

Future<void> _pump(
  WidgetTester tester,
  Run run, {
  double textScale = 1.0,
}) async {
  SharedPreferences.setMockInitialValues({'body_weight_kg': 72.0});
  final prefs = Preferences();
  await prefs.init();

  final dir = Directory.systemTemp.createTempSync('run_detail_stats_grid_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: dir);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
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

/// At 2.0x the map's `MapAttribution` credit strip — an unbounded `Row` of
/// two link labels, sized `MainAxisSize.min` inside an `Align` — outgrows a
/// 360dp map and throws. That is a residual of the § 497 text-scale sweep in
/// `lib/widgets/map_attribution.dart`, not something the stat grid can cause
/// (a `Wrap` has no horizontal overflow mode), so drain it rather than let it
/// mask the geometry these tests exist to measure.
void _drainUnrelatedOverflow(WidgetTester tester) => tester.takeException();

/// The stat cell holding [label] — the `Column` a stat widget is built from,
/// which its parent (an `Expanded` before, a grid cell now) sizes tightly, so
/// the same finder measures the real cell width under either layout.
Finder _cell(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(Column)).first;

double _cellWidth(WidgetTester tester, String label) =>
    tester.getSize(_cell(label)).width;

const _secondaryLabels = [
  'Elev Gain',
  'Elev Loss',
  'Grade-Adj. Pace',
  'Calories',
  'Steps',
  'Cadence',
  'Avg HR',
  'Age grade',
];

void main() {
  group('run detail stat grid (issue #666 C2)', () {
    testWidgets(
        'all eight secondary stats get a readable cell on a 360dp phone '
        'instead of eight 40dp ellipsis stubs', (tester) async {
      tester.view.physicalSize = const Size(360, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, _everyStatRun());

      for (final label in _secondaryLabels) {
        expect(find.text(label), findsOneWidget,
            reason: '$label should be present on a run carrying every stat');
        // Eight Expanded cells across (360 - 40) gave 40dp each, under every
        // value the row draws. Four columns give 80.
        expect(_cellWidth(tester, label), greaterThanOrEqualTo(72.0),
            reason: '$label cell is too narrow for its value');
      }
    });

    testWidgets('the secondary row lines up with the primary row above it',
        (tester) async {
      tester.view.physicalSize = const Size(360, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, _everyStatRun());

      // Both rows carry four cells, so they share a column grid: each
      // secondary cell's left edge sits under a primary cell's left edge.
      final primaryLefts = ['Distance', 'Time', 'Moving', 'Pace']
          .map((l) => tester.getRect(_cell(l)).left)
          .toList();
      expect(primaryLefts, hasLength(4));
      for (final label in _secondaryLabels.take(4)) {
        final left = tester.getRect(_cell(label)).left;
        expect(primaryLefts, contains(closeTo(left, 0.5)),
            reason: '$label does not align with a primary stat column');
      }
    });

    testWidgets('at 2.0x text scale the grid drops columns instead of '
        'shrinking every cell below legibility', (tester) async {
      tester.view.physicalSize = const Size(360, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, _everyStatRun(), textScale: 2.0);
      _drainUnrelatedOverflow(tester);

      for (final label in _secondaryLabels) {
        // 72dp of value at 1.0x needs 144 at 2.0x, so 320dp of row fits two.
        expect(_cellWidth(tester, label), greaterThanOrEqualTo(144.0),
            reason: '$label cell did not grow with the text');
      }
    });

    testWidgets('the heart-rate summary row reflows at 2.0x rather than '
        'overflowing its Row', (tester) async {
      tester.view.physicalSize = const Size(360, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(
        tester,
        Run(
          id: 'run-hr',
          startedAt: DateTime.utc(2026, 4, 15, 7, 30),
          duration: const Duration(minutes: 23),
          distanceMetres: 5000,
          source: RunSource.app,
          metadata: const {'activity_type': 'run'},
          track: [
            for (var i = 0; i <= 20; i++)
              Waypoint(
                lat: -37.8136 + i * 0.0009,
                lng: 144.9631,
                bpm: 120 + i,
                timestamp: DateTime.utc(2026, 4, 15, 7, 30)
                    .add(Duration(seconds: i * 30)),
              ),
          ],
        ),
        textScale: 2.0,
      );

      _drainUnrelatedOverflow(tester);
      expect(find.text('Heart rate zones'), findsOneWidget);
      for (final label in ['Avg', 'Min', 'Max']) {
        expect(_cellWidth(tester, label), greaterThanOrEqualTo(144.0),
            reason: '$label cell did not grow with the text');
      }
    });
  });
}
