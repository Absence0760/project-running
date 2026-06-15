import 'dart:async';

enum GymRunnerStepStatus { pending, completed, skipped }

enum GymRunnerAdherence { completed, partial, abandoned }

class GymRunnerStep {
  final String exerciseName;
  final String exerciseKey;
  final int setIndex;
  final String setType;
  final int? targetRepsMin;
  final int? targetRepsMax;
  final double? targetWeightKg;
  final double? targetRpe;
  final int? restS;
  final int? targetDurationS;
  final int? supersetGroup;

  const GymRunnerStep({
    required this.exerciseName,
    required this.exerciseKey,
    required this.setIndex,
    required this.setType,
    this.targetRepsMin,
    this.targetRepsMax,
    this.targetWeightKg,
    this.targetRpe,
    this.restS,
    this.targetDurationS,
    this.supersetGroup,
  });

  bool get isDurationBased => targetDurationS != null && targetDurationS! > 0;
}

class GymRunnerSetResult {
  final int stepIndex;
  final GymRunnerStep step;
  final int? actualReps;
  final double? actualWeightKg;
  final double? actualRpe;
  final int? actualDurationS;
  final GymRunnerStepStatus status;

  const GymRunnerSetResult({
    required this.stepIndex,
    required this.step,
    required this.actualReps,
    required this.actualWeightKg,
    required this.actualRpe,
    required this.actualDurationS,
    required this.status,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'step_index': stepIndex,
      'exercise_name': step.exerciseName,
      'exercise_key': step.exerciseKey,
      'set_index': step.setIndex,
      'set_type': step.setType,
      'target_reps_min': step.targetRepsMin,
      'target_reps_max': step.targetRepsMax,
      'target_weight_kg': step.targetWeightKg,
      'actual_reps': actualReps,
      'actual_weight_kg': actualWeightKg,
      'actual_rpe': actualRpe,
      'actual_duration_s': actualDurationS,
      'status': switch (status) {
        GymRunnerStepStatus.pending => 'pending',
        GymRunnerStepStatus.completed => 'completed',
        GymRunnerStepStatus.skipped => 'skipped',
      },
    };
  }
}

sealed class GymExecEvent {
  const GymExecEvent();
}

class GymStepTransitionEvent extends GymExecEvent {
  final int previousIndex;
  final int currentIndex;
  final GymRunnerStep step;
  const GymStepTransitionEvent({
    required this.previousIndex,
    required this.currentIndex,
    required this.step,
  });
}

class GymRestStartedEvent extends GymExecEvent {
  final int restS;
  final GymRunnerStep nextStep;
  const GymRestStartedEvent({required this.restS, required this.nextStep});
}

class GymWorkoutCompleteEvent extends GymExecEvent {
  const GymWorkoutCompleteEvent();
}

class GymWorkoutAbandonedEvent extends GymExecEvent {
  const GymWorkoutAbandonedEvent();
}

class GymWorkoutRunner {
  GymWorkoutRunner({required this.steps, this.routineId});

  final List<GymRunnerStep> steps;
  final String? routineId;

  final StreamController<GymExecEvent> _events =
      StreamController<GymExecEvent>.broadcast();
  Stream<GymExecEvent> get events => _events.stream;

  int _idx = 0;
  bool _abandoned = false;
  bool _started = false;

  final List<GymRunnerSetResult> _results = [];

  int get currentStepIndex => _idx;
  bool get isComplete => _idx >= steps.length || _abandoned;
  GymRunnerStep? get currentStep => _idx < steps.length ? steps[_idx] : null;

  void start() {
    if (_started) return;
    _started = true;
    if (steps.isEmpty) {
      _idx = 0;
      _events.add(const GymWorkoutCompleteEvent());
      return;
    }
    _events.add(GymStepTransitionEvent(
      previousIndex: -1,
      currentIndex: 0,
      step: steps[0],
    ));
  }

  void completeSet({int? reps, double? weightKg, double? rpe, int? durationS}) {
    if (isComplete) return;
    _results.add(GymRunnerSetResult(
      stepIndex: _idx,
      step: steps[_idx],
      actualReps: reps,
      actualWeightKg: weightKg,
      actualRpe: rpe,
      actualDurationS: durationS,
      status: GymRunnerStepStatus.completed,
    ));
    _advance();
  }

  void skipStep() {
    if (isComplete) return;
    _results.add(GymRunnerSetResult(
      stepIndex: _idx,
      step: steps[_idx],
      actualReps: null,
      actualWeightKg: null,
      actualRpe: null,
      actualDurationS: null,
      status: GymRunnerStepStatus.skipped,
    ));
    // A skipped set isn't performed, so its trailing rest doesn't apply —
    // advance straight to the next step (matches web GymSessionRunner.onSkip).
    _advance(withRest: false);
  }

  bool rewindStep() {
    if (_abandoned) return false;
    if (_results.isEmpty) return false;
    _results.removeLast();
    final prev = _idx;
    _idx -= 1;
    _events.add(GymStepTransitionEvent(
      previousIndex: prev,
      currentIndex: _idx,
      step: steps[_idx],
    ));
    return true;
  }

  void abandon() {
    if (isComplete) return;
    _abandoned = true;
    _events.add(const GymWorkoutAbandonedEvent());
  }

  List<GymRunnerSetResult> snapshotResults() {
    final out = List<GymRunnerSetResult>.from(_results);
    if (!isComplete && _idx < steps.length) {
      out.add(GymRunnerSetResult(
        stepIndex: _idx,
        step: steps[_idx],
        actualReps: null,
        actualWeightKg: null,
        actualRpe: null,
        actualDurationS: null,
        status: GymRunnerStepStatus.skipped,
      ));
    }
    return out;
  }

  GymRunnerAdherence adherence() {
    if (_abandoned) return GymRunnerAdherence.abandoned;
    final results = snapshotResults();
    if (results.isEmpty) return GymRunnerAdherence.abandoned;
    if (results.length < steps.length) return GymRunnerAdherence.partial;
    for (final r in results) {
      if (r.status != GymRunnerStepStatus.completed) {
        return GymRunnerAdherence.partial;
      }
      if (!_withinTarget(r)) return GymRunnerAdherence.partial;
    }
    return GymRunnerAdherence.completed;
  }

  Map<String, dynamic> reviewMetadata() {
    if (routineId == null) return const <String, dynamic>{};
    return <String, dynamic>{
      'routine_id': routineId,
      'gym_step_results': snapshotResults().map((r) => r.toJson()).toList(),
      'gym_adherence': switch (adherence()) {
        GymRunnerAdherence.completed => 'completed',
        GymRunnerAdherence.partial => 'partial',
        GymRunnerAdherence.abandoned => 'abandoned',
      },
    };
  }

  void dispose() {
    _events.close();
  }

  void _advance({bool withRest = true}) {
    final prev = _idx;
    // rest_s is "rest after this set" (schema + web GymSessionRunner), so the
    // pause is authored on the just-completed step, not the one we move to.
    final completed = steps[prev];
    _idx += 1;
    if (_idx >= steps.length) {
      _events.add(const GymWorkoutCompleteEvent());
      return;
    }
    final next = steps[_idx];
    final rest = completed.restS;
    if (withRest && rest != null && rest > 0) {
      _events.add(GymRestStartedEvent(restS: rest, nextStep: next));
    }
    _events.add(GymStepTransitionEvent(
      previousIndex: prev,
      currentIndex: _idx,
      step: next,
    ));
  }

  bool _withinTarget(GymRunnerSetResult r) {
    final step = r.step;
    if (step.isDurationBased) {
      final actual = r.actualDurationS;
      if (actual == null) return false;
      return actual >= step.targetDurationS! * 0.8;
    }
    final min = step.targetRepsMin;
    if (min == null) return true;
    final actual = r.actualReps;
    if (actual == null) return false;
    return actual >= min * 0.8;
  }
}
