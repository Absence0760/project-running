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

WorkoutStep _durStep({
  WorkoutStepKind kind = WorkoutStepKind.rep,
  int durationSec = 30,
  int pace = 240,
  String label = 'Stride',
  int? repIndex,
  int? repTotal,
}) =>
    WorkoutStep(
      kind: kind,
      targetDistanceMetres: 0,
      targetDurationSec: durationSec,
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

    test('rewindStep is a no-op on the first step (no previous to rewind to)',
        () {
      final runner = WorkoutRunner(steps: [
        _step(distance: 400, label: 'A'),
        _step(distance: 200, label: 'B'),
      ]);
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      runner.onSnapshot(_snap(distance: 100, elapsedSec: 30));
      expect(runner.rewindStep(), isFalse,
          reason: 'first step has no predecessor; rewind must report false');
      expect(runner.currentStepIndex, 0);
      runner.dispose();
    });

    test('rewindStep after a completed advance re-enters the previous step',
        () {
      final steps = [
        _step(distance: 400, label: 'A'),
        _step(distance: 200, label: 'B'),
      ];
      final runner = WorkoutRunner(steps: steps);
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      // Cross step A's target — runner auto-advances to step B.
      runner.onSnapshot(_snap(distance: 400, elapsedSec: 120));
      expect(runner.currentStepIndex, 1);

      // Realised the advance was premature — rewind. The next snapshot
      // sets _last, then the rewind anchors step start to that snapshot
      // so stepDistanceMetres is zero relative to "now."
      runner.onSnapshot(_snap(distance: 410, elapsedSec: 122));
      expect(runner.rewindStep(), isTrue);

      expect(runner.currentStepIndex, 0,
          reason: 'rewind must return to the previous step');
      expect(runner.currentStep?.label, 'A');
      // Step distance resets to zero from the rewind snapshot's distance.
      runner.onSnapshot(_snap(distance: 410, elapsedSec: 122));
      expect(runner.stepDistanceMetres, 0,
          reason: 'rewind must anchor step distance to the rewind moment');
      // Results from the completed advance are discarded.
      final results = runner.snapshotResults();
      expect(results, hasLength(1),
          reason: 'in-progress step is included; the previously-advanced '
              'result is dropped');
      expect(results.first.stepIndex, 0);
      runner.dispose();
    });

    test('rewindStep after skipStep also restores the skipped step', () {
      final steps = [
        _step(distance: 400, label: 'A'),
        _step(distance: 200, label: 'B'),
      ];
      final runner = WorkoutRunner(steps: steps);
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      runner.onSnapshot(_snap(distance: 100, elapsedSec: 30));
      runner.skipStep();
      expect(runner.currentStepIndex, 1);

      runner.onSnapshot(_snap(distance: 100, elapsedSec: 30));
      expect(runner.rewindStep(), isTrue);
      expect(runner.currentStepIndex, 0);
      // No skip artefact left behind in results.
      runner.onSnapshot(_snap(distance: 100, elapsedSec: 30));
      final results = runner.snapshotResults();
      // Only the in-progress step is reported (as skipped on the
      // snapshotResults convention); no completed/skipped record from
      // the rewound advance remains.
      expect(results.where((r) => r.stepIndex == 0).length, 1);
      runner.dispose();
    });

    test('rewindStep does not pre-empt an abandoned runner', () {
      final runner = WorkoutRunner(steps: [
        _step(distance: 400, label: 'A'),
        _step(distance: 200, label: 'B'),
      ]);
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      runner.onSnapshot(_snap(distance: 400, elapsedSec: 120));
      runner.abandon();
      expect(runner.rewindStep(), isFalse,
          reason: 'abandoned runs are terminal; rewind is a no-op');
      runner.dispose();
    });
  });

  group('Duration-based steps (v2)', () {
    test('isDurationBased toggles on positive targetDurationSec', () {
      expect(_step(distance: 400).isDurationBased, isFalse);
      expect(_durStep(durationSec: 30).isDurationBased, isTrue);
      // Zero / negative duration must NOT flip the switch — the auto-
      // advance check uses isDurationBased to pick its axis and would
      // immediately bail on a sentinel zero.
      expect(
        WorkoutStep(
          kind: WorkoutStepKind.rep,
          targetDistanceMetres: 100,
          targetDurationSec: 0,
          targetPaceSecPerKm: 240,
          label: 'x',
        ).isDurationBased,
        isFalse,
      );
    });

    test('auto-advances on stepElapsed >= targetDurationSec', () async {
      final steps = [
        _durStep(durationSec: 30, label: 'A'),
        _durStep(durationSec: 60, label: 'B'),
      ];
      final runner = WorkoutRunner(steps: steps);
      final transitions = <int>[];
      runner.events.listen((e) {
        if (e is StepTransitionEvent) transitions.add(e.currentIndex);
      });

      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      runner.onSnapshot(_snap(distance: 100, elapsedSec: 15));
      expect(runner.currentStepIndex, 0,
          reason: 'mid-window, no advance');

      runner.onSnapshot(_snap(distance: 200, elapsedSec: 30));
      expect(runner.currentStepIndex, 1,
          reason: 'exactly at target → advance');

      // 60 s for step B → cumulative elapsed = 90.
      runner.onSnapshot(_snap(distance: 600, elapsedSec: 90));
      expect(runner.isComplete, isTrue);

      await Future<void>.delayed(Duration.zero);
      runner.dispose();
      expect(transitions, [0, 1]);
    });

    test('halfway cue fires at the time-axis midpoint, not the distance one',
        () async {
      final runner = WorkoutRunner(steps: [_durStep(durationSec: 60)]);
      final progress = <StepProgressKind>[];
      runner.events.listen((e) {
        if (e is StepProgressEvent) progress.add(e.kind);
      });
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      // 25 s — short of halfway. No cue.
      runner.onSnapshot(_snap(distance: 100, elapsedSec: 25));
      expect(progress, isEmpty);
      // 30 s — exactly halfway.
      runner.onSnapshot(_snap(distance: 120, elapsedSec: 30));
      await Future<void>.delayed(Duration.zero);
      expect(progress, [StepProgressKind.halfway]);
      runner.dispose();
    });

    test('last-10s cue fires for duration > 20 s, suppressed for short steps',
        () async {
      final long = WorkoutRunner(steps: [_durStep(durationSec: 60)]);
      final longProg = <StepProgressKind>[];
      long.events.listen((e) {
        if (e is StepProgressEvent) longProg.add(e.kind);
      });
      long.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      long.onSnapshot(_snap(distance: 250, elapsedSec: 51)); // last 10s
      await Future<void>.delayed(Duration.zero);
      expect(longProg.contains(StepProgressKind.lastFiftyMetres), isTrue,
          reason: 'fires once 60 - 51 = 9 ≤ 10');

      // Short step (≤ 20 s): cue collides with halfway, suppressed.
      final short = WorkoutRunner(steps: [_durStep(durationSec: 15)]);
      final shortProg = <StepProgressKind>[];
      short.events.listen((e) {
        if (e is StepProgressEvent) shortProg.add(e.kind);
      });
      short.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      short.onSnapshot(_snap(distance: 50, elapsedSec: 10));
      await Future<void>.delayed(Duration.zero);
      expect(shortProg.contains(StepProgressKind.lastFiftyMetres), isFalse,
          reason: 'duration ≤ 20 s gates the cue off');
      long.dispose();
      short.dispose();
    });

    test('progressFraction reads elapsed/duration for time steps', () {
      final runner = WorkoutRunner(steps: [_durStep(durationSec: 30)]);
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      expect(runner.progressFraction, 0);
      runner.onSnapshot(_snap(distance: 50, elapsedSec: 15));
      expect(runner.progressFraction, closeTo(0.5, 1e-9));
      runner.dispose();
    });

    test('stepRemainingDuration reports a positive remainder until target', () {
      final runner = WorkoutRunner(steps: [_durStep(durationSec: 60)]);
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      expect(runner.stepRemainingDuration, const Duration(seconds: 60));
      runner.onSnapshot(_snap(distance: 100, elapsedSec: 45));
      expect(runner.stepRemainingDuration, const Duration(seconds: 15));
      // Past target: clamps to zero rather than negative.
      runner.onSnapshot(_snap(distance: 130, elapsedSec: 70));
      expect(runner.stepRemainingDuration, Duration.zero);
      runner.dispose();
    });

    test('stepRemainingDuration is zero for distance-based steps', () {
      final runner = WorkoutRunner(steps: [_step(distance: 400)]);
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      runner.onSnapshot(_snap(distance: 100, elapsedSec: 30));
      expect(runner.stepRemainingDuration, Duration.zero,
          reason: 'distance-based steps never report a duration remainder');
      runner.dispose();
    });

    test('adherence applies 80% threshold against the time axis', () {
      // 30s step skipped at 20s = 66%, which is < 80% → partial.
      final runner = WorkoutRunner(steps: [
        _durStep(durationSec: 30, label: 'A'),
        _durStep(durationSec: 30, label: 'B'),
      ]);
      runner.onSnapshot(_snap(distance: 0, elapsedSec: 0));
      runner.onSnapshot(_snap(distance: 90, elapsedSec: 20));
      runner.skipStep();
      runner.onSnapshot(_snap(distance: 200, elapsedSec: 50));
      // Step B reaches 30 s → completes.
      expect(runner.adherence(), WorkoutAdherence.partial);
      runner.dispose();
    });

    test('toJson includes target_duration_s for duration steps', () {
      final r = WorkoutStepResult(
        stepIndex: 0,
        step: _durStep(durationSec: 30, pace: 240, label: 'Stride'),
        actualDistanceMetres: 120,
        actualPaceSecPerKm: 245,
        durationSeconds: 30,
        status: WorkoutStepStatus.completed,
      );
      final json = r.toJson();
      expect(json, containsPair('target_duration_s', 30));
      expect(json, containsPair('duration_s', 30));
      // target_distance_m is still emitted (numeric default) so the web
      // reader's existing field is always present.
      expect(json, containsPair('target_distance_m', 0));
    });

    test('toJson omits target_duration_s for distance steps', () {
      final r = WorkoutStepResult(
        stepIndex: 0,
        step: _step(distance: 400, pace: 240, label: 'Rep'),
        actualDistanceMetres: 400,
        actualPaceSecPerKm: 240,
        durationSeconds: 96,
        status: WorkoutStepStatus.completed,
      );
      expect(r.toJson().containsKey('target_duration_s'), isFalse);
    });
  });

  group('expandWorkoutSteps duration-based shapes', () {
    test('warmup duration_s yields a duration-based step', () {
      final steps = expandWorkoutSteps(
        structure: {
          'warmup': {'duration_s': 600, 'pace': 'easy'},
        },
        paces: const {'easy': 360},
        toleranceSecPerKm: 10,
      );
      expect(steps, hasLength(1));
      expect(steps.first.isDurationBased, isTrue);
      expect(steps.first.targetDurationSec, 600);
      expect(steps.first.kind, WorkoutStepKind.warmup);
    });

    test('repeats with rep.duration_s expands to count duration-based reps',
        () {
      final steps = expandWorkoutSteps(
        structure: {
          'repeats': {
            'count': 4,
            'rep': {'duration_s': 30, 'pace_sec_per_km': 240},
            'recovery': {'duration_s': 60, 'pace': 'jog'},
          },
        },
        paces: const {'jog': 420},
        toleranceSecPerKm: 10,
      );
      expect(steps, hasLength(7),
          reason: '4 reps + 3 recoveries (last rep has no recovery)');
      expect(steps[0].isDurationBased, isTrue);
      expect(steps[0].targetDurationSec, 30);
      expect(steps[1].isDurationBased, isTrue);
      expect(steps[1].targetDurationSec, 60);
      expect(steps.last.targetDurationSec, 30,
          reason: 'last entry is rep #4, not a recovery');
    });

    test('repeats generator shape with duration_s + recovery_duration_s', () {
      final steps = expandWorkoutSteps(
        structure: {
          'repeats': {
            'count': 3,
            'duration_s': 30,
            'pace_sec_per_km': 240,
            'recovery_duration_s': 90,
            'recovery_pace': 'jog',
          },
        },
        paces: const {'jog': 420},
        toleranceSecPerKm: 10,
      );
      expect(steps, hasLength(5),
          reason: '3 reps + 2 recoveries');
      expect(
        steps.where((s) => s.isDurationBased).length,
        steps.length,
        reason: 'every step is duration-based',
      );
    });

    test('mixed step types: distance warmup + duration repeats', () {
      final steps = expandWorkoutSteps(
        structure: {
          'warmup': {'distance_m': 1000, 'pace': 'easy'},
          'repeats': {
            'count': 2,
            'rep': {'duration_s': 30, 'pace_sec_per_km': 240},
          },
          'cooldown': {'distance_m': 1000, 'pace': 'easy'},
        },
        paces: const {'easy': 360},
        toleranceSecPerKm: 10,
      );
      // No recovery block → reps only, no recoveries between.
      expect(steps, hasLength(4));
      expect(steps[0].isDurationBased, isFalse);
      expect(steps[1].isDurationBased, isTrue);
      expect(steps[2].isDurationBased, isTrue);
      expect(steps[3].isDurationBased, isFalse);
    });

    test('block with both distance_m and duration_s prefers distance', () {
      // Backwards-compatibility: existing plans with `distance_m` keep
      // their distance-based shape even if a v2 editor adds duration.
      final steps = expandWorkoutSteps(
        structure: {
          'steady': {
            'distance_m': 5000,
            'duration_s': 1500,
            'pace': 'tempo',
          },
        },
        paces: const {'tempo': 300},
        toleranceSecPerKm: 10,
      );
      expect(steps, hasLength(1));
      expect(steps.first.isDurationBased, isFalse);
      expect(steps.first.targetDistanceMetres, 5000);
    });

    test('block with neither distance_m nor positive duration_s is dropped',
        () {
      final steps = expandWorkoutSteps(
        structure: {
          'warmup': {'duration_s': 0, 'pace': 'easy'},
          'steady': {'distance_m': 5000, 'pace': 'tempo'},
        },
        paces: const {'easy': 360, 'tempo': 300},
        toleranceSecPerKm: 10,
      );
      expect(steps, hasLength(1),
          reason: 'malformed warmup falls out; steady survives');
      expect(steps.first.kind, WorkoutStepKind.steady);
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
