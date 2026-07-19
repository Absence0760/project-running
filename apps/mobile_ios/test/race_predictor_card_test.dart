import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/race_predictor_card.dart';

Run _r({
  required double distance,
  required int durationS,
  required DateTime startedAt,
  RunSource source = RunSource.app,
}) =>
    Run(
      id: 'r-${startedAt.millisecondsSinceEpoch}',
      startedAt: startedAt,
      duration: Duration(seconds: durationS),
      distanceMetres: distance,
      source: source,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<Run> runs,
  required DateTime now,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: RacePredictorCard(runs: runs, now: now),
        ),
      ),
    ),
  );
}

void main() {
  group('RacePredictorCard', () {
    testWidgets('renders nothing when there are no qualifying runs',
        (tester) async {
      final now = DateTime.utc(2026, 5, 1);
      // Below the 1.5 km / 5 min qualifying gate.
      await _pump(
        tester,
        runs: [
          _r(
            distance: 1000,
            durationS: 200,
            startedAt: now.subtract(const Duration(days: 1)),
          ),
        ],
        now: now,
      );
      expect(find.text('Race-time predictor'), findsNothing);
    });

    testWidgets('renders nothing when there are no runs at all',
        (tester) async {
      await _pump(tester, runs: const [], now: DateTime.utc(2026, 5, 1));
      expect(find.text('Race-time predictor'), findsNothing);
    });

    testWidgets('renders the full ladder when the gate passes', (tester) async {
      final now = DateTime.utc(2026, 5, 1);
      final runs = [
        _r(
          distance: 5000,
          durationS: 1300,
          startedAt: now.subtract(const Duration(days: 5)),
        ),
      ];
      await _pump(tester, runs: runs, now: now);
      await tester.pumpAndSettle();

      // Card title + the four ladder column headers (uppercased).
      expect(find.text('Race-time predictor'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('PACE'), findsOneWidget);
      expect(find.text('CONFIDENCE'), findsOneWidget);

      // Four ladder rungs (5K / 10K / Half / Marathon) each render a
      // confidence chip — at least one HIGH/MODERATE/LOW chip is present.
      final chips = find.byWidgetPredicate((w) =>
          w is Text &&
          {'HIGH', 'MODERATE', 'LOW'}.contains((w.data ?? '').toUpperCase()));
      expect(chips, findsWidgets);
    });
  });
}
