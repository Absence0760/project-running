import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/preferences.dart';
import '../lib/widgets/workout_execution_band.dart';
import 'package:run_recorder/run_recorder.dart';

WorkoutStep _step({
  WorkoutStepKind kind = WorkoutStepKind.rep,
  String label = 'Rep 3/6',
  double distance = 400,
  int pace = 240,
  int? repIndex = 3,
  int? repTotal = 6,
}) =>
    WorkoutStep(
      kind: kind,
      targetDistanceMetres: distance,
      targetPaceSecPerKm: pace,
      label: label,
      repIndex: repIndex,
      repTotal: repTotal,
    );

WorkoutStep _durStep({
  String label = 'Stride',
  int durationSec = 30,
  int pace = 240,
}) =>
    WorkoutStep(
      kind: WorkoutStepKind.rep,
      targetDistanceMetres: 0,
      targetDurationSec: durationSec,
      targetPaceSecPerKm: pace,
      label: label,
    );

Future<void> _pumpBand(
  WidgetTester tester, {
  required WorkoutBandState state,
  VoidCallback? onSkip,
  VoidCallback? onRewind,
  VoidCallback? onAbandon,
}) {
  final notifier = ValueNotifier<WorkoutBandState>(state);
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WorkoutExecutionBand(
          state: notifier,
          onSkip: onSkip ?? () {},
          onRewind: onRewind ?? () {},
          onAbandon: onAbandon ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('WorkoutExecutionBand', () {
    testWidgets('renders nothing when state is empty (no step + not complete)',
        (tester) async {
      await _pumpBand(tester, state: WorkoutBandState.empty);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Rewind'), findsNothing);
    });

    testWidgets('renders step label, target distance, target pace, and m-to-go',
        (tester) async {
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 14,
          currentIndex: 4,
          progress: 0.25,
          remainingMetres: 300,
          actualPaceSecPerKm: 235,
          adherence: PaceAdherence.ahead,
          complete: false,
          abandoned: false,
        ),
      );
      // Header line: "Rep 3/6 · 400 m @ 4:00/km"
      expect(find.textContaining('Rep 3/6'), findsOneWidget);
      expect(find.textContaining('400 m'), findsOneWidget);
      expect(find.textContaining('4:00/km'), findsOneWidget);
      // Step counter and remaining-distance footer.
      expect(find.text('5/14'), findsOneWidget);
      expect(find.text('300 m to go'), findsOneWidget);
      // Pace pip shows signed delta.
      expect(find.text('−5s'), findsOneWidget);
    });

    testWidgets('Skip and Abandon trigger callbacks', (tester) async {
      var skips = 0;
      var abandons = 0;
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 3,
          currentIndex: 0,
          progress: 0.5,
          remainingMetres: 200,
          actualPaceSecPerKm: 240,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
        onSkip: () => skips++,
        onAbandon: () => abandons++,
      );

      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(skips, 1);

      await tester.tap(find.text('Abandon'));
      await tester.pump();
      expect(abandons, 1);
    });

    testWidgets('Rewind is disabled on the first step', (tester) async {
      var rewinds = 0;
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 3,
          currentIndex: 0,
          progress: 0.5,
          remainingMetres: 200,
          actualPaceSecPerKm: 240,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
        onRewind: () => rewinds++,
      );
      final rewindBtn = find.widgetWithText(OutlinedButton, 'Rewind');
      expect(rewindBtn, findsOneWidget);
      // onPressed is null on the first step → button is disabled, taps no-op.
      await tester.tap(rewindBtn, warnIfMissed: false);
      await tester.pump();
      expect(rewinds, 0,
          reason: 'Rewind button must be disabled when currentIndex == 0');
    });

    testWidgets('Rewind triggers callback once advanced past first step',
        (tester) async {
      var rewinds = 0;
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 3,
          currentIndex: 1,
          progress: 0.1,
          remainingMetres: 360,
          actualPaceSecPerKm: 240,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
        onRewind: () => rewinds++,
      );
      await tester.tap(find.text('Rewind'));
      await tester.pump();
      expect(rewinds, 1);
    });

    testWidgets('renders the workout-complete shell when step is null + complete',
        (tester) async {
      await _pumpBand(
        tester,
        state: const WorkoutBandState(
          step: null,
          totalSteps: 6,
          currentIndex: 6,
          progress: 1,
          remainingMetres: 0,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: true,
          abandoned: false,
        ),
      );
      expect(find.textContaining('Workout complete'), findsOneWidget);
      // Controls hidden in complete state.
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Rewind'), findsNothing);
      expect(find.text('Abandon'), findsNothing);
    });

    testWidgets('renders the abandoned shell', (tester) async {
      await _pumpBand(
        tester,
        state: const WorkoutBandState(
          step: null,
          totalSteps: 6,
          currentIndex: 2,
          progress: 0,
          remainingMetres: 0,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: true,
        ),
      );
      expect(find.textContaining('abandoned'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Rewind'), findsNothing);
    });

    testWidgets('renders duration-based target ("30s") and seconds-to-go',
        (tester) async {
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _durStep(durationSec: 30, pace: 240),
          totalSteps: 4,
          currentIndex: 1,
          progress: 0.6,
          remainingMetres: 0,
          remainingDuration: const Duration(seconds: 12),
          actualPaceSecPerKm: 245,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      // Header shows time target, not metres.
      expect(find.textContaining('Stride · 30s'), findsOneWidget);
      // Distance footer is replaced by a time remainder.
      expect(find.text('12s to go'), findsOneWidget);
      expect(find.text('0 m to go'), findsNothing,
          reason: 'must not fall back to distance footer for duration steps');
    });

    testWidgets('formats longer duration remainders as "Nm Ns"',
        (tester) async {
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _durStep(durationSec: 240, pace: 240),
          totalSteps: 1,
          currentIndex: 0,
          progress: 0.1,
          remainingMetres: 0,
          remainingDuration: const Duration(seconds: 215),
          actualPaceSecPerKm: 240,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      // 4-minute step, 215 s remaining → "3m 35s to go".
      expect(find.text('3m 35s to go'), findsOneWidget);
      // Header shows the rounded target as "4m".
      expect(find.textContaining('4m'), findsOneWidget);
    });

    testWidgets('pace pip uses an em-dash when actual pace is null',
        (tester) async {
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 3,
          currentIndex: 0,
          progress: 0,
          remainingMetres: 400,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      expect(find.text('—'), findsOneWidget);
    });
  });

  group('WorkoutExecutionBand — distance pref propagation', () {
    // The band's `_fmtDistance` was hardcoded km. Mi-mode users now
    // see miles / yards. Each test plants a Preferences in the
    // desired mode then asserts the rendered text reflects it.
    tearDown(resetActivePreferencesForTest);

    Future<void> setUnit(bool useMiles) async {
      SharedPreferences.setMockInitialValues({'use_miles': useMiles});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
    }

    testWidgets('mi mode: 400 m target renders in yards + /mi pace',
        (tester) async {
      // 400 × 1.09361 ≈ 437 yards (sub-1 mile → yards branch).
      // Both the header's distance pill AND the "to go" footer
      // render in yards; pace flips to /mi.
      await setUnit(true);
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 6,
          currentIndex: 0,
          progress: 0,
          remainingMetres: 400,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      expect(find.textContaining('437 yd'), findsAtLeastNWidgets(1));
      // Header pace also flips to /mi (was "4:00/km").
      expect(find.textContaining('/mi'), findsOneWidget);
      // Negative shape — the original "400 m" / "/km" must NOT
      // leak through.
      expect(find.textContaining('400 m'), findsNothing);
      expect(find.textContaining('/km'), findsNothing);
    });

    testWidgets('mi mode: 2000 m target renders as "1.2 mi"',
        (tester) async {
      // 2000 / 1609.344 = 1.243 → "1.2 mi" at 1 decimal.
      await setUnit(true);
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(distance: 2000),
          totalSteps: 6,
          currentIndex: 0,
          progress: 0,
          remainingMetres: 2000,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      expect(find.textContaining('1.2 mi'), findsOneWidget);
    });

    testWidgets('km mode (default): 400 m renders in metres + /km pace',
        (tester) async {
      // Negative-shape pin so a regression that inverted the branch
      // would fail loud. 400 m appears in both the header pill and
      // the "to go" footer → findsAtLeastNWidgets(2).
      await setUnit(false);
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 6,
          currentIndex: 0,
          progress: 0,
          remainingMetres: 400,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      expect(find.textContaining('400 m'), findsAtLeastNWidgets(1));
      expect(find.textContaining('/km'), findsOneWidget);
      expect(find.textContaining('yd'), findsNothing);
      expect(find.textContaining('/mi'), findsNothing);
    });
  });
}
