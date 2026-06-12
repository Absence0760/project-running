import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/gym_execution_band.dart';

GymRunnerStep _step({
  String name = 'Back Squat',
  int? repsMin = 5,
  int? repsMax,
  double? weightKg = 100,
  int? durationS,
}) =>
    GymRunnerStep(
      exerciseName: name,
      exerciseKey: name.toLowerCase(),
      setIndex: 0,
      setType: 'working',
      targetRepsMin: repsMin,
      targetRepsMax: repsMax,
      targetWeightKg: weightKg,
      targetDurationS: durationS,
    );

Future<void> _pumpBand(
  WidgetTester tester, {
  required GymBandState state,
  VoidCallback? onComplete,
  VoidCallback? onSkip,
  VoidCallback? onRewind,
  VoidCallback? onAbandon,
}) {
  final notifier = ValueNotifier<GymBandState>(state);
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: GymExecutionBand(
          state: notifier,
          onComplete: onComplete ?? () {},
          onSkip: onSkip ?? () {},
          onRewind: onRewind ?? () {},
          onAbandon: onAbandon ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('GymExecutionBand', () {
    testWidgets('renders nothing when state is empty (no step + not complete)',
        (tester) async {
      await _pumpBand(tester, state: GymBandState.empty);
      expect(find.text('Skip set'), findsNothing);
      expect(find.text('Previous'), findsNothing);
      expect(find.text('Complete set'), findsNothing);
    });

    testWidgets('renders exercise, set counter, target, and controls',
        (tester) async {
      await _pumpBand(
        tester,
        state: GymBandState(
          step: _step(repsMin: 8, repsMax: 12, weightKg: 80),
          total: 6,
          currentIndex: 2,
          restRemainingS: 0,
          entered: false,
          targetHit: false,
          complete: false,
          abandoned: false,
        ),
      );
      // Exercise name + the "exercise · set n of total" counter line.
      expect(find.text('Back Squat'), findsOneWidget);
      expect(find.text('Back Squat · set 3 of 6'), findsOneWidget);
      // Target: rep range × weight.
      expect(find.textContaining('8–12'), findsOneWidget);
      expect(find.textContaining('80.0 kg'), findsOneWidget);
      // Controls present.
      expect(find.text('Complete set'), findsOneWidget);
      expect(find.text('Skip set'), findsOneWidget);
      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('Abandon'), findsOneWidget);
    });

    testWidgets('renders the rest countdown when resting', (tester) async {
      await _pumpBand(
        tester,
        state: GymBandState(
          step: _step(),
          total: 4,
          currentIndex: 1,
          restRemainingS: 45,
          entered: false,
          targetHit: false,
          complete: false,
          abandoned: false,
        ),
      );
      expect(find.text('Rest 45s'), findsOneWidget);
    });

    testWidgets('Complete triggers callback', (tester) async {
      var completes = 0;
      await _pumpBand(
        tester,
        state: GymBandState(
          step: _step(),
          total: 3,
          currentIndex: 0,
          restRemainingS: 0,
          entered: true,
          targetHit: true,
          complete: false,
          abandoned: false,
        ),
        onComplete: () => completes++,
      );
      await tester.tap(find.text('Complete set'));
      await tester.pump();
      expect(completes, 1);
    });

    testWidgets('Skip and Abandon trigger callbacks', (tester) async {
      var skips = 0;
      var abandons = 0;
      await _pumpBand(
        tester,
        state: GymBandState(
          step: _step(),
          total: 3,
          currentIndex: 0,
          restRemainingS: 0,
          entered: false,
          targetHit: false,
          complete: false,
          abandoned: false,
        ),
        onSkip: () => skips++,
        onAbandon: () => abandons++,
      );
      await tester.tap(find.text('Skip set'));
      await tester.pump();
      expect(skips, 1);
      await tester.tap(find.text('Abandon'));
      await tester.pump();
      expect(abandons, 1);
    });

    testWidgets('renders the complete + abandoned shells', (tester) async {
      await _pumpBand(
        tester,
        state: const GymBandState(
          step: null,
          total: 6,
          currentIndex: 6,
          restRemainingS: 0,
          entered: false,
          targetHit: false,
          complete: true,
          abandoned: false,
        ),
      );
      expect(find.text('Session complete'), findsOneWidget);
      expect(find.text('Complete set'), findsNothing);
      expect(find.text('Skip set'), findsNothing);

      await _pumpBand(
        tester,
        state: const GymBandState(
          step: null,
          total: 6,
          currentIndex: 2,
          restRemainingS: 0,
          entered: false,
          targetHit: false,
          complete: false,
          abandoned: true,
        ),
      );
      expect(find.text('Abandon'), findsOneWidget);
      expect(find.text('Skip set'), findsNothing);
      expect(find.text('Previous'), findsNothing);
    });
  });
}
