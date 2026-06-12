import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

GymRunnerStep _step({
  String name = 'Back Squat',
  String key = 'back_squat',
  int setIndex = 0,
  String setType = 'working',
  int? repsMin = 5,
  int? repsMax = 5,
  double? weightKg = 60,
  double? rpe,
  int? restS,
  int? durationS,
  int? supersetGroup,
}) =>
    GymRunnerStep(
      exerciseName: name,
      exerciseKey: key,
      setIndex: setIndex,
      setType: setType,
      targetRepsMin: repsMin,
      targetRepsMax: repsMax,
      targetWeightKg: weightKg,
      targetRpe: rpe,
      restS: restS,
      targetDurationS: durationS,
      supersetGroup: supersetGroup,
    );

void main() {
  group('advance', () {
    test('start emits the first step transition', () async {
      final runner = GymWorkoutRunner(steps: [_step()]);
      final transitions = <int>[];
      runner.events.listen((e) {
        if (e is GymStepTransitionEvent) transitions.add(e.currentIndex);
      });
      runner.start();
      await Future<void>.delayed(Duration.zero);
      expect(transitions, [0]);
      expect(runner.currentStepIndex, 0);
      runner.dispose();
    });

    test('completeSet advances to the next step', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1),
      ]);
      runner.start();
      runner.completeSet(reps: 5, weightKg: 60);
      expect(runner.currentStepIndex, 1);
      runner.dispose();
    });

    test('completing the last step emits GymWorkoutCompleteEvent', () async {
      final runner = GymWorkoutRunner(steps: [_step()]);
      var completed = 0;
      runner.events.listen((e) {
        if (e is GymWorkoutCompleteEvent) completed++;
      });
      runner.start();
      runner.completeSet(reps: 5, weightKg: 60);
      await Future<void>.delayed(Duration.zero);
      expect(completed, 1);
      expect(runner.isComplete, isTrue);
      runner.dispose();
    });

    test('emits a rest event when the next step has restS > 0', () async {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1, restS: 90),
      ]);
      final rests = <GymRestStartedEvent>[];
      runner.events.listen((e) {
        if (e is GymRestStartedEvent) rests.add(e);
      });
      runner.start();
      runner.completeSet(reps: 5, weightKg: 60);
      await Future<void>.delayed(Duration.zero);
      expect(rests, hasLength(1));
      expect(rests.first.restS, 90);
      expect(rests.first.nextStep.setIndex, 1);
      runner.dispose();
    });

    test('an empty step list completes instantly on start', () async {
      final runner = GymWorkoutRunner(steps: const []);
      var completed = 0;
      runner.events.listen((e) {
        if (e is GymWorkoutCompleteEvent) completed++;
      });
      runner.start();
      await Future<void>.delayed(Duration.zero);
      expect(completed, 1);
      expect(runner.isComplete, isTrue);
      runner.dispose();
    });

    test('currentStep is null past the end of the list', () {
      final runner = GymWorkoutRunner(steps: [_step()]);
      runner.start();
      expect(runner.currentStep, isNotNull);
      runner.completeSet(reps: 5, weightKg: 60);
      expect(runner.currentStep, isNull);
      runner.dispose();
    });
  });

  group('controls', () {
    test('skipStep marks the step skipped and advances', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1),
      ]);
      runner.start();
      runner.skipStep();
      expect(runner.currentStepIndex, 1);
      final results = runner.snapshotResults();
      expect(results.first.status, GymRunnerStepStatus.skipped);
      runner.dispose();
    });

    test('abandon emits an abandoned event and stops advancing', () async {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1),
      ]);
      var abandoned = 0;
      runner.events.listen((e) {
        if (e is GymWorkoutAbandonedEvent) abandoned++;
      });
      runner.start();
      runner.abandon();
      runner.completeSet(reps: 5, weightKg: 60);
      await Future<void>.delayed(Duration.zero);
      expect(abandoned, 1);
      expect(runner.currentStepIndex, 0);
      runner.dispose();
    });

    test('rewindStep is a no-op on the first step', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1),
      ]);
      runner.start();
      expect(runner.rewindStep(), isFalse);
      expect(runner.currentStepIndex, 0);
      runner.dispose();
    });

    test('rewindStep after completeSet re-enters the previous step', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1),
      ]);
      runner.start();
      runner.completeSet(reps: 5, weightKg: 60);
      expect(runner.currentStepIndex, 1);
      expect(runner.rewindStep(), isTrue);
      expect(runner.currentStepIndex, 0);
      expect(runner.snapshotResults().where((r) => r.stepIndex == 0).length, 1);
      runner.dispose();
    });

    test('rewindStep after skipStep restores the skipped step', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1),
      ]);
      runner.start();
      runner.skipStep();
      expect(runner.currentStepIndex, 1);
      expect(runner.rewindStep(), isTrue);
      expect(runner.currentStepIndex, 0);
      final results = runner.snapshotResults();
      expect(results.where((r) => r.stepIndex == 0).length, 1);
      expect(results.first.status, GymRunnerStepStatus.skipped,
          reason: 'in-progress step reads as skipped after the rewind drops '
              'the earlier skip record');
      runner.dispose();
    });

    test('rewindStep is a no-op when abandoned', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1),
      ]);
      runner.start();
      runner.completeSet(reps: 5, weightKg: 60);
      runner.abandon();
      expect(runner.rewindStep(), isFalse);
      runner.dispose();
    });
  });

  group('snapshotResults', () {
    test('captures completed sets with entered values', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1),
      ]);
      runner.start();
      runner.completeSet(reps: 6, weightKg: 62.5, rpe: 8);
      final results = runner.snapshotResults();
      final done = results.firstWhere((r) => r.stepIndex == 0);
      expect(done.status, GymRunnerStepStatus.completed);
      expect(done.actualReps, 6);
      expect(done.actualWeightKg, 62.5);
      expect(done.actualRpe, 8);
      runner.dispose();
    });

    test('a skipped set is tagged skipped', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1),
      ]);
      runner.start();
      runner.skipStep();
      final results = runner.snapshotResults();
      expect(results.firstWhere((r) => r.stepIndex == 0).status,
          GymRunnerStepStatus.skipped);
      runner.dispose();
    });

    test('the in-progress step is reported as skipped', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1),
      ]);
      runner.start();
      runner.completeSet(reps: 5, weightKg: 60);
      final results = runner.snapshotResults();
      expect(results, hasLength(2));
      expect(results.last.stepIndex, 1);
      expect(results.last.status, GymRunnerStepStatus.skipped);
      runner.dispose();
    });

    test('toJson uses snake_case keys', () {
      final result = GymRunnerSetResult(
        stepIndex: 2,
        step: _step(
          name: 'Bench Press',
          key: 'bench_press',
          setIndex: 2,
          setType: 'working',
          repsMin: 8,
          repsMax: 10,
          weightKg: 80,
        ),
        actualReps: 9,
        actualWeightKg: 80,
        actualRpe: 7.5,
        actualDurationS: null,
        status: GymRunnerStepStatus.completed,
      );
      final json = result.toJson();
      expect(json, containsPair('step_index', 2));
      expect(json, containsPair('exercise_name', 'Bench Press'));
      expect(json, containsPair('exercise_key', 'bench_press'));
      expect(json, containsPair('set_index', 2));
      expect(json, containsPair('set_type', 'working'));
      expect(json, containsPair('target_reps_min', 8));
      expect(json, containsPair('target_reps_max', 10));
      expect(json, containsPair('target_weight_kg', 80));
      expect(json, containsPair('actual_reps', 9));
      expect(json, containsPair('actual_weight_kg', 80));
      expect(json, containsPair('actual_rpe', 7.5));
      expect(json, containsPair('status', 'completed'));
    });

    test('a duration set records actual_duration_s', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0, durationS: 45, repsMin: null, repsMax: null),
      ]);
      runner.start();
      runner.completeSet(durationS: 50);
      final results = runner.snapshotResults();
      final json = results.first.toJson();
      expect(json, containsPair('actual_duration_s', 50));
      runner.dispose();
    });
  });

  group('adherence', () {
    test('abandon yields abandoned', () {
      final runner = GymWorkoutRunner(steps: [_step()]);
      runner.start();
      runner.abandon();
      expect(runner.adherence(), GymRunnerAdherence.abandoned);
      runner.dispose();
    });

    test('every set within target yields completed', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0, repsMin: 5, repsMax: 5),
        _step(setIndex: 1, repsMin: 5, repsMax: 5),
      ]);
      runner.start();
      runner.completeSet(reps: 5, weightKg: 60);
      runner.completeSet(reps: 5, weightKg: 60);
      expect(runner.adherence(), GymRunnerAdherence.completed);
      runner.dispose();
    });

    test('a set under 80% of target reps yields partial', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0, repsMin: 10, repsMax: 10),
      ]);
      runner.start();
      runner.completeSet(reps: 5, weightKg: 60);
      expect(runner.adherence(), GymRunnerAdherence.partial);
      runner.dispose();
    });

    test('an in-progress workout reads as partial', () {
      final runner = GymWorkoutRunner(steps: [
        _step(setIndex: 0),
        _step(setIndex: 1),
      ]);
      runner.start();
      runner.completeSet(reps: 5, weightKg: 60);
      expect(runner.adherence(), GymRunnerAdherence.partial);
      runner.dispose();
    });
  });

  group('reviewMetadata', () {
    test('returns empty when routineId is null', () {
      final runner = GymWorkoutRunner(steps: [_step()]);
      runner.start();
      runner.completeSet(reps: 5, weightKg: 60);
      expect(runner.reviewMetadata(routineId: null), isEmpty);
      runner.dispose();
    });

    test('emits the three keys when active', () {
      final runner = GymWorkoutRunner(steps: [_step()]);
      runner.start();
      runner.completeSet(reps: 5, weightKg: 60);
      final meta = runner.reviewMetadata(routineId: 'routine-1');
      expect(meta, containsPair('routine_id', 'routine-1'));
      expect(meta['gym_step_results'], isA<List>());
      expect(meta, containsPair('gym_adherence', isA<String>()));
      runner.dispose();
    });

    test('an abandoned workout reads gym_adherence abandoned', () {
      final runner = GymWorkoutRunner(steps: [_step()]);
      runner.start();
      runner.abandon();
      final meta = runner.reviewMetadata(routineId: 'routine-1');
      expect(meta['gym_adherence'], 'abandoned');
      runner.dispose();
    });
  });
}
