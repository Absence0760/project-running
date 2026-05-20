import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/mileage_trend.dart';
import '../lib/preferences.dart';
import '../lib/widgets/mileage_trend_card.dart';

Run _run({
  required DateTime startedAt,
  required double distanceM,
}) =>
    Run(
      id: 'r-${startedAt.millisecondsSinceEpoch}',
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
      distanceMetres: distanceM,
      source: RunSource.app,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<Run> runs,
  DistanceUnit unit = DistanceUnit.km,
  required DateTime now,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MileageTrendCard(runs: runs, unit: unit, now: now),
        ),
      ),
    ),
  );
}

void main() {
  final now = DateTime(2026, 5, 19, 12); // Tuesday

  group('MileageTrendCard', () {
    testWidgets('renders nothing when there are no runs', (tester) async {
      await _pump(tester, runs: const [], now: now);
      expect(find.text('MILEAGE'), findsNothing);
    });

    testWidgets('renders the header + view toggle when populated',
        (tester) async {
      await _pump(
        tester,
        runs: [
          _run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 5000),
        ],
        now: now,
      );
      expect(find.text('MILEAGE'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
    });

    testWidgets('default view is weekly — week labels visible on first frame',
        (tester) async {
      await _pump(
        tester,
        runs: [
          _run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 5000),
        ],
        now: now,
      );
      // Weekly bucket starts Monday 11 May → "11 May".
      expect(find.text('11 May'), findsOneWidget);
    });

    testWidgets(
        'tapping Month switches to monthly buckets ("May \'26" label)',
        (tester) async {
      await _pump(
        tester,
        runs: [
          _run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 5000),
        ],
        now: now,
      );
      // Tap the Month segment in the SegmentedButton.
      await tester.tap(find.text('Month'));
      await tester.pump();
      expect(find.text("May '26"), findsOneWidget);
      expect(find.text('11 May'), findsNothing,
          reason: 'monthly view must replace the weekly bucket label');
    });

    testWidgets('tapping Year switches to yearly buckets (4-digit year label)',
        (tester) async {
      await _pump(
        tester,
        runs: [
          _run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 5000),
        ],
        now: now,
      );
      await tester.tap(find.text('Year'));
      await tester.pump();
      expect(find.text('2026'), findsOneWidget);
    });

    testWidgets('numeric labels honour the user unit (km vs mi)',
        (tester) async {
      // A clean ~10 km bucket. km view should render "10.0"; mi view
      // should render approximately "6.2".
      final tenKm = [_run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 10000)];

      await _pump(tester, runs: tenKm, unit: DistanceUnit.km, now: now);
      // UnitFormat.distanceValue uses toStringAsFixed(2) — "10.00".
      expect(find.text('10.00'), findsOneWidget);

      await _pump(tester, runs: tenKm, unit: DistanceUnit.mi, now: now);
      // 10 km ≈ 6.21 mi → toStringAsFixed(2) → "6.21".
      expect(find.text('6.21'), findsOneWidget);
    });
  });
}
