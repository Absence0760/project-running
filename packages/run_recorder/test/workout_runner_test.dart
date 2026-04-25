import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

RunSnapshot _snap({double distance = 0, int elapsedSec = 0}) =>
    RunSnapshot(
      elapsed: Duration(seconds: elapsedSec),
      distanceMetres: distance,
    );

WorkoutStep _step({
  WorkoutStepKind kind = WorkoutStepKind.steady,
  double distance = 1000,
  int pace = 300,
  String label = 'Step',
  int? repIndex,
  int? repTotal,
}) =>
    WorkoutStep(
      kind: kind,
      targetDistanceMetres: distance,
      targetPaceSecPerKm: pace,
      label: label,
      repIndex: repIndex,
      repTotal: repTotal,
    );

void main() {
  group('expandWorkoutSteps', () {
    test('6×400 with warmup + cooldown → 14 steps', () {
      final steps = expandWorkoutSteps(
        structure: {
          'warmup': {'distance_m': 1000, 'pace_sec_per_km': 'easy'},
          'repeats': {
            'count': 6,
            'rep': {'distance_m': 400, 'pace_sec_per_km': 240},
            'recovery': {'distance_m': 200, 'pace_sec_per_km': 'jog'},
          },
          'cooldown': {'distance_m': 1000, 'pace_sec_per_km': 'easy'},
        },
        paces: const {'easy': 360, 'jog': 420},
        toleranceSecPerKm: 10,
      );
      // 1 warmup + 6 reps + 5 recoveries (last rep has no trailing
      // recovery) + 1 cooldown = 13.
      expect(steps, hasLength(13));
      expect(steps.first.kind, WorkoutStepKind.warmup);
      expect(steps.last.kind, WorkoutStepKind.cooldown);
      expect(
        steps.where((s) => s.kind == WorkoutStepKind.rep).length,
        6,
      );
      expect(
        steps.where((s) => s.kind == WorkoutStepKind.recovery).length,
        5, // last rep has no trailing recovery
      );
      expect(steps[1].label, 'Rep 1/6');
      expect(steps[2].label, 'Recovery 1/5');
    });

    test('no structure with fallback → single steady step', () {
      final steps = expandWorkoutSteps(
        structure: null,
        paces: const {'easy': 360},
        toleranceSecPerKm: 10,
        fallbackDistanceMetres: 8000,
        fallbackPaceSecPerKm: 320,
      );
      expect(steps, hasLength(1));
      expect(steps.first.kind, WorkoutStepKind.steady);
      expect(steps.first.targetDistanceMetres, 8000);
      expect(steps.first.targetPaceSecPerKm, 320);
    });

    test('steady-only structure → 1 step', () {
      final steps = expandWorkoutSteps(
        structure: {
          'steady': {'distance_m': 5000, 'pace_sec_per_km': 'tempo'},
        },
        paces: const {'tempo': 280},
        toleranceSecPerKm: 10,
      );
      expect(steps, hasLength(1));
      expect(steps.first.kind, WorkoutStepKind.steady);
      expect(steps.first.targetPaceSecPerKm, 280);
    });

    test('symbolic pace falls through to defaults when paces bag empty', () {
      final steps = expandWorkoutSteps(
        structure: {
          'steady': {'distance_m': 1000, 'pace_sec_per_km': 'easy'},
        },
        paces: const {},
        toleranceSecPerKm: 10,
      );
      expect(steps.first.targetPaceSecPerKm, 360);
    });

    test('empty structure falls back to a single step or empty list', () {
      final empty = expandWorkoutSteps(
        structure: const {},
        paces: const {},
        toleranceSecPerKm: 10,
        fallbackDistanceMetres: 5000,
      );
      expect(empty, hasLength(1));

      final none = expandWorkoutSteps(
        structure: null,
        paces: const {},
        toleranceSecPerKm: 10,
      );
      expect(none, isEmpty);
    });
  });

  group('WorkoutRunner auto-advance', () {
    test('advances exactly when stepDistance >= target', () async {
      final steps = [
        _step(distance: 400, label: 'A'),
        _step(distance: 200, label: 'B'),
      ];
      final runner = WorkoutRunner(steps: steps);
      final transitions = <int>[];
      runner.events.listen((e) {
        if (e is StepTransitionEvent) transitions.add(e.currentIndex);
      });

      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      runner.onSnapshot(_snap(distance: 200, elapsedSec: 60));
      expect(runner.currentStepIndex, 0);

      runner.onSnapshot(_snap(distance: 400, elapsedSec: 120));
      expect(runner.currentStepIndex, 1);

      runner.onSnapshot(_snap(distance: 600, elapsedSec: 180));
      expect(runner.isComplete, isTrue);

      // Drain the broadcast stream microtasks before reading transitions.
      await Future<void>.delayed(Duration.zero);
      runner.dispose();
      expect(transitions, [0, 1]);
    });

    test('emits the initial transition for the first step', () async {
      final runner = WorkoutRunner(steps: [_step()]);
      final events = <WorkoutExecEvent>[];
      runner.events.listen(events.add);

      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<StepTransitionEvent>().length, 1);
      runner.dispose();
    });

    test('emits halfway and last-50m progress cues once each', () async {
      final runner = WorkoutRunner(steps: [_step(distance: 1000)]);
      final progress = <StepProgressKind>[];
      runner.events.listen((e) {
        if (e is StepProgressEvent) progress.add(e.kind);
      });

      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      runner.onSnapshot(_snap(distance: 400, elapsedSec: 120));
      runner.onSnapshot(_snap(distance: 600, elapsedSec: 180)); // halfway
      runner.onSnapshot(_snap(distance: 700, elapsedSec: 210));
      runner.onSnapshot(_snap(distance: 960, elapsedSec: 280)); // last 50m
      runner.onSnapshot(_snap(distance: 990, elapsedSec: 295));
      await Future<void>.delayed(Duration.zero);

      expect(progress, [StepProgressKind.halfway, StepProgressKind.lastFiftyMetres]);
      runner.dispose();
    });
  });

  group('WorkoutRunner controls', () {
    test('skipStep marks the step skipped and advances', () {
      final steps = [_step(distance: 400, label: 'A'), _step(distance: 200, label: 'B')];
      final runner = WorkoutRunner(steps: steps);
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      runner.onSnapshot(_snap(distance: 100, elapsedSec: 30));

      runner.skipStep();
      expect(runner.currentStepIndex, 1);
      final results = runner.snapshotResults();
      expect(results.first.status, WorkoutStepStatus.skipped);
      expect(results.first.actualDistanceMetres, 100);
      runner.dispose();
    });

    test('abandon stops emitting transitions even if distance crosses target',
        () async {
      final runner = WorkoutRunner(steps: [
        _step(distance: 400, label: 'A'),
        _step(distance: 200, label: 'B'),
      ]);
      final events = <WorkoutExecEvent>[];
      runner.events.listen(events.add);

      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      runner.abandon();
      // After abandon, snapshots that would have triggered an advance
      // must produce no events.
      runner.onSnapshot(_snap(distance: 600, elapsedSec: 180));
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<StepTransitionEvent>().length, 1); // only initial
      expect(events.whereType<WorkoutAbandonedEvent>().length, 1);
      expect(events.whereType<StepTransitionEvent>().any((e) => e.currentIndex == 1),
          isFalse);
      expect(runner.adherence(), WorkoutAdherence.abandoned);
      runner.dispose();
    });
  });

  group('Pace adherence', () {
    test('flags wayBehind when 35s/km off target', () {
      final runner = WorkoutRunner(steps: [_step(distance: 400, pace: 240)]);
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      // 380 m in 105 s → ~276 s/km, 36 s slow, tolerance 10 → wayBehind.
      // Stay just under the target so the runner doesn't auto-advance
      // (and clear paceAdherence) before we read it.
      runner.onSnapshot(_snap(distance: 380, elapsedSec: 105));
      expect(runner.paceAdherence, PaceAdherence.wayBehind);
      runner.dispose();
    });
  });

  group('snapshotResults', () {
    test('covers every advanced step and the in-progress one', () {
      final steps = [
        _step(distance: 400, label: 'A'),
        _step(distance: 200, label: 'B'),
        _step(distance: 1000, label: 'C'),
      ];
      final runner = WorkoutRunner(steps: steps);
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      runner.onSnapshot(_snap(distance: 400, elapsedSec: 120)); // advance
      runner.onSnapshot(_snap(distance: 600, elapsedSec: 180)); // advance
      runner.onSnapshot(_snap(distance: 800, elapsedSec: 230)); // partway

      final results = runner.snapshotResults();
      expect(results, hasLength(3));
      expect(results[0].status, WorkoutStepStatus.completed);
      expect(results[1].status, WorkoutStepStatus.completed);
      expect(results[2].status, WorkoutStepStatus.skipped);
      runner.dispose();
    });

    test('toJson uses snake_case keys per metadata.md', () {
      final r = WorkoutStepResult(
        stepIndex: 2,
        step: _step(
          kind: WorkoutStepKind.rep,
          distance: 400,
          pace: 240,
          repIndex: 3,
          repTotal: 6,
          label: 'Rep 3/6',
        ),
        actualDistanceMetres: 400,
        actualPaceSecPerKm: 245,
        durationSeconds: 100,
        status: WorkoutStepStatus.completed,
      );
      final json = r.toJson();
      expect(json, containsPair('step_index', 2));
      expect(json, containsPair('kind', 'rep'));
      expect(json, containsPair('rep_index', 3));
      expect(json, containsPair('rep_total', 6));
      expect(json, containsPair('target_distance_m', 400));
      expect(json, containsPair('actual_distance_m', 400));
      expect(json, containsPair('target_pace_sec_per_km', 240));
      expect(json, containsPair('actual_pace_sec_per_km', 245));
      expect(json, containsPair('duration_s', 100));
      expect(json, containsPair('status', 'completed'));
    });
  });
}
