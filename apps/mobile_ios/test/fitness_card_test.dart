import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training_load.dart';
import '../lib/widgets/fitness_card.dart';

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

      // Two qualifying runs → the "Runs" FitnessStat shows 2.
      final runsStatFinder = find.ancestor(
          of: find.text('Runs'), matching: find.byType(FitnessStat));
      expect(
          find.descendant(of: runsStatFinder, matching: find.text('2')),
          findsOneWidget);

      // Recovery-advice line is present (text content varies with TSB,
      // so just check the icon and that some text sits beside it).
      expect(find.byIcon(Icons.health_and_safety), findsOneWidget);
    });

    testWidgets('CTL/ATL/TSB come from the training-load series, not computeSnapshot',
        (tester) async {
      // round-5 pro: the card must read the SAME series the chart shows so
      // the form number can't contradict the curve. Pin the displayed
      // CTL/ATL/TSB to computeTrainingLoadSeries(...).last.
      final now = DateTime.utc(2026, 5, 1);
      final runs = [
        _r(distance: 5000, durationS: 1500, startedAt: now.subtract(const Duration(days: 25))),
        _r(distance: 5000, durationS: 1300, startedAt: now.subtract(const Duration(days: 5))),
      ];
      final last = computeTrainingLoadSeries(runs, endDate: now).last;
      await _pump(tester, runs: runs, now: now);
      await tester.pumpAndSettle();

      for (final entry in {
        'Fitness (CTL)': last.ctl,
        'Fatigue (ATL)': last.atl,
        'Form (TSB)': last.tsb,
      }.entries) {
        final stat = find.ancestor(
            of: find.text(entry.key), matching: find.byType(FitnessStat));
        expect(
          find.descendant(
              of: stat, matching: find.text(entry.value.toStringAsFixed(0))),
          findsOneWidget,
          reason: '${entry.key} must equal the series value '
              '${entry.value.toStringAsFixed(0)}',
        );
      }
    });

    testWidgets('honours an injected loadSeries over its own recompute',
        (tester) async {
      // The dashboard computes ONE training-load series (with lifts) and passes
      // it to FitnessCard, ReadinessCard, and the chart so they can't disagree.
      // Pin that the card reads the injected series, not a self-recomputed
      // run-only one: feed a series whose CTL/ATL/TSB are distinctive values
      // the runs alone would never produce.
      final now = DateTime.utc(2026, 5, 1);
      final runs = [
        _r(distance: 5000, durationS: 1500, startedAt: now.subtract(const Duration(days: 25))),
        _r(distance: 5000, durationS: 1300, startedAt: now.subtract(const Duration(days: 5))),
      ];
      final injected = [
        TrainingLoadPoint(
          date: now,
          stress: 120,
          runStress: 60,
          liftStress: 60,
          atl: 71,
          ctl: 88,
          tsb: 17,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FitnessCard(runs: runs, now: now, loadSeries: injected),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in {
        'Fitness (CTL)': '88',
        'Fatigue (ATL)': '71',
        'Form (TSB)': '17',
      }.entries) {
        final stat = find.ancestor(
            of: find.text(entry.key), matching: find.byType(FitnessStat));
        expect(find.descendant(of: stat, matching: find.text(entry.value)),
            findsOneWidget,
            reason: '${entry.key} must come from the injected series '
                '(${entry.value}), not a self-recompute.');
      }
    });

    testWidgets('uses an em-dash placeholder when VDOT cannot be computed',
        (tester) async {
      // Two qualifying-distance runs both outside the 90-day VDOT recency
      // window — qualifyingRunCount > 0 (so the card renders), but
      // currentVdot returns null because no run is recent enough → "—".
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
          startedAt: now.subtract(const Duration(days: 95)),
        ),
      ];
      await _pump(tester, runs: runs, now: now);
      // Card is up.
      expect(find.text('Fitness'), findsOneWidget);
      // 2 qualifying runs — scope to the Runs FitnessStat to avoid matching
      // CTL/ATL/TSB values that might also round to "2".
      final runsStatFinder = find.ancestor(
          of: find.text('Runs'), matching: find.byType(FitnessStat));
      expect(
          find.descendant(of: runsStatFinder, matching: find.text('2')),
          findsOneWidget);
      // VDOT and VO2max must render as em-dash when currentVdot is null.
      // CTL/ATL/TSB are also "—" here, so we check for at least 2 (not exactly).
      expect(find.text('—'), findsAtLeastNWidgets(2));
      // Specifically the VDOT and VO2max labels must both be present.
      expect(find.text('VO₂ max'), findsOneWidget);
      expect(find.text('VDOT'), findsOneWidget);
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

    testWidgets('wraps in a Tooltip when a plain-English message is given (#25)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FitnessStat(
              label: 'VDOT',
              value: '49.8',
              tooltip: 'Running-fitness score from your best recent effort.',
            ),
          ),
        ),
      );
      final tip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tip.message, contains('Running-fitness score'));
    });

    testWidgets('a tap opens a dialog with the explanation, no long-press (#267)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: FitnessStat(
                label: 'VDOT',
                value: '49.8',
                tooltip: 'Running-fitness score from your best recent effort.',
              ),
            ),
          ),
        ),
      );
      // The explanation is not on screen until the affordance is used — and
      // a plain tap (not a long-press) must reveal it.
      expect(
          find.text('Running-fitness score from your best recent effort.'),
          findsNothing);
      await tester.tap(find.text('VDOT'));
      await tester.pumpAndSettle();
      expect(
          find.text('Running-fitness score from your best recent effort.'),
          findsOneWidget);
    });
  });
}
