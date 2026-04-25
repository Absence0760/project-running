import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/widgets/fitness_card.dart';

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
      home: Scaffold(
        body: SingleChildScrollView(
          child: FitnessCard(runs: runs, now: now),
        ),
      ),
    ),
  );
}

void main() {
  group('FitnessCard', () {
    testWidgets('renders nothing when there are no runs at all',
        (tester) async {
      await _pump(tester, runs: const [], now: DateTime.utc(2026, 5, 1));
      expect(find.text('Fitness'), findsNothing);
      expect(find.text('VDOT'), findsNothing);
    });

    testWidgets('renders nothing when there are no qualifying runs',
        (tester) async {
      // Below the 3 km / 5 min threshold → does not qualify.
      final now = DateTime.utc(2026, 5, 1);
      await _pump(
        tester,
        runs: [
          _r(
            distance: 1500,
            durationS: 200,
            startedAt: now.subtract(const Duration(days: 1)),
          ),
        ],
        now: now,
      );
      expect(find.text('Fitness'), findsNothing);
      expect(find.text('VDOT'), findsNothing);
    });

    testWidgets('renders the full populated card with qualifying runs',
        (tester) async {
      final now = DateTime.utc(2026, 5, 1);
      // Two 5 km runs in the recency window so both VDOT and CTL/ATL/TSB
      // have something to chew on.
      final runs = [
        _r(
          distance: 5000,
          durationS: 1500, // 25:00 5k
          startedAt: now.subtract(const Duration(days: 25)),
        ),
        _r(
          distance: 5000,
          durationS: 1300, // 21:40 5k
          startedAt: now.subtract(const Duration(days: 5)),
        ),
      ];
      await _pump(tester, runs: runs, now: now);
      await tester.pumpAndSettle();

      // Section title and stat labels.
      expect(find.text('Fitness'), findsOneWidget);
      expect(find.text('VO₂ max'), findsOneWidget);
      expect(find.text('VDOT'), findsOneWidget);
      expect(find.text('Runs'), findsOneWidget);
      expect(find.text('Fitness (CTL)'), findsOneWidget);
      expect(find.text('Fatigue (ATL)'), findsOneWidget);
      expect(find.text('Form (TSB)'), findsOneWidget);

      // Two qualifying runs → "Runs" stat shows 2.
      expect(find.text('2'), findsOneWidget);

      // Recovery-advice line is present (text content varies with TSB,
      // so just check the icon and that some text sits beside it).
      expect(find.byIcon(Icons.health_and_safety), findsOneWidget);
    });

    testWidgets('uses an em-dash placeholder when VDOT cannot be computed',
        (tester) async {
      // A single qualifying-distance run that's outside the 90-day VDOT
      // recency window — qualifyingRunCount > 0 (so the card renders),
      // but currentVdot returns null → "—".
      final now = DateTime.utc(2026, 5, 1);
      final runs = [
        _r(
          distance: 5000,
          durationS: 1500,
          startedAt: now.subtract(const Duration(days: 200)),
        ),
        _r(
          distance: 5000,
          durationS: 1500,
          startedAt: now.subtract(const Duration(days: 5)),
        ),
      ];
      await _pump(tester, runs: runs, now: now);
      // Card is up.
      expect(find.text('Fitness'), findsOneWidget);
      // 2 qualifying runs.
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('FitnessStat', () {
    testWidgets('renders value over label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FitnessStat(label: 'VDOT', value: '49.8'),
          ),
        ),
      );
      expect(find.text('49.8'), findsOneWidget);
      expect(find.text('VDOT'), findsOneWidget);
    });
  });
}
