import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/widgets/workout_execution_band.dart';
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

Future<void> _pumpBand(
  WidgetTester tester, {
  required WorkoutBandState state,
  VoidCallback? onSkip,
  VoidCallback? onAbandon,
}) {
  final notifier = ValueNotifier<WorkoutBandState>(state);
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WorkoutExecutionBand(
          state: notifier,
          onSkip: onSkip ?? () {},
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
      expect(find.text('Skip step'), findsNothing);
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

      await tester.tap(find.text('Skip step'));
      await tester.pump();
      expect(skips, 1);

      await tester.tap(find.text('Abandon'));
      await tester.pump();
      expect(abandons, 1);
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
      expect(find.text('Skip step'), findsNothing);
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
      expect(find.text('Skip step'), findsNothing);
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
}
