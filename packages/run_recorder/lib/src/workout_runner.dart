import 'dart:async';

import 'run_snapshot.dart';

/// Live execution of a structured workout's expanded step list. Sits on
/// top of the [RunRecorder] — it consumes [RunSnapshot]s, advances
/// through its steps, and emits [WorkoutExecEvent]s the run screen
/// turns into audio cues and band updates.
///
/// Spec: [docs/features/workout_execution.md](../../../../docs/features/workout_execution.md).
class WorkoutRunner {
  WorkoutRunner({required this.steps});

  /// Step list expanded once at workout start (warmup → reps → ... →
  /// cooldown). Use [expandWorkoutSteps] to build it from a stored
  /// `plan_workouts.structure` jsonb plus the plan's [TrainingPaces].
  final List<WorkoutStep> steps;

  final StreamController<WorkoutExecEvent> _events =
      StreamController<WorkoutExecEvent>.broadcast();
  Stream<WorkoutExecEvent> get events => _events.stream;

  // Auto-advance bookkeeping.
  int _idx = 0;
  double _stepStartDistanceMetres = 0;
  Duration _stepStartElapsed = Duration.zero;
  RunSnapshot? _last;
  bool _abandoned = false;
  bool _emittedFirstStart = false;

  // Per-step result accumulator. We snapshot at advance / skip /
  // abandon time so the final list survives a recorder stop without
  // needing a final snapshot.
  final List<WorkoutStepResult> _results = [];

  // Cue-once flags per step index — reset when a step is entered.
  bool _firedHalfway = false;
  bool _firedLastFifty = false;
  DateTime? _lastDriftCueAt;

  int get currentStepIndex => _idx;
  WorkoutStep? get currentStep => _idx < steps.length ? steps[_idx] : null;
  bool get isComplete => _idx >= steps.length || _abandoned;

  // Per-step derived metrics. Cheap getters recomputed against the
  // last snapshot so the band can read them without buffering state.
  double get stepDistanceMetres {
    final snap = _last;
    if (snap == null) return 0;
    final d = snap.distanceMetres - _stepStartDistanceMetres;
    return d < 0 ? 0 : d;
  }

  Duration get stepElapsed {
    final snap = _last;
    if (snap == null) return Duration.zero;
    final el = snap.elapsed - _stepStartElapsed;
    return el.isNegative ? Duration.zero : el;
  }

  int? get stepAveragePaceSecPerKm {
    final d = stepDistanceMetres;
    final el = stepElapsed.inSeconds;
    if (d < 5 || el < 1) return null;
    return (el / (d / 1000)).round();
  }

  double get stepRemainingMetres {
    final s = currentStep;
    if (s == null) return 0;
    final r = s.targetDistanceMetres - stepDistanceMetres;
    return r < 0 ? 0 : r;
  }

  /// Seconds remaining on the current step when it's duration-based.
  /// Always 0 for distance-based steps — callers can read
  /// [WorkoutStep.isDurationBased] to know which axis to display.
  Duration get stepRemainingDuration {
    final s = currentStep;
    if (s == null || !s.isDurationBased) return Duration.zero;
    final r = s.targetDurationSec! - stepElapsed.inSeconds;
    return r < 0 ? Duration.zero : Duration(seconds: r);
  }

  /// Progress 0..1 along the active step's end condition — distance
  /// fraction for distance-based steps, time fraction for duration-based.
  /// The band reads this so the progress bar renders the same shape on
  /// both step types.
  double get progressFraction {
    final s = currentStep;
    if (s == null) return 1.0;
    if (s.isDurationBased) {
      final target = s.targetDurationSec!;
      if (target <= 0) return 1.0;
      return (stepElapsed.inSeconds / target).clamp(0.0, 1.0);
    }
    final target = s.targetDistanceMetres;
    if (target <= 0) return 1.0;
    return (stepDistanceMetres / target).clamp(0.0, 1.0);
  }

  PaceAdherence get paceAdherence {
    final s = currentStep;
    if (s == null) return PaceAdherence.onPace;
    final actual = stepAveragePaceSecPerKm;
    if (actual == null) return PaceAdherence.onPace;
    final diff = actual - s.targetPaceSecPerKm; // positive = slower
    final tol = s.toleranceSecPerKm;
    if (diff.abs() <= tol) return PaceAdherence.onPace;
    if (diff.abs() <= tol * 2) {
      return diff > 0 ? PaceAdherence.behind : PaceAdherence.ahead;
    }
    return diff > 0 ? PaceAdherence.wayBehind : PaceAdherence.wayAhead;
  }

  /// Drive — call from `_onSnapshot` in run_screen.
  void onSnapshot(RunSnapshot s) {
    if (_abandoned) return;
    if (steps.isEmpty) {
      // Treat empty step lists as instantly complete.
      if (_idx == 0 && !_emittedFirstStart) {
        _emittedFirstStart = true;
        _events.add(const WorkoutCompleteEvent());
        _idx = 1;
      }
      return;
    }
    _last = s;

    if (!_emittedFirstStart) {
      _emittedFirstStart = true;
      _stepStartDistanceMetres = s.distanceMetres;
      _stepStartElapsed = s.elapsed;
      _events.add(StepTransitionEvent(
        previousIndex: -1,
        currentIndex: 0,
        step: steps[0],
      ));
    }

    if (isComplete) return;

    final step = steps[_idx];
    final stepDist = stepDistanceMetres;
    final stepSecs = stepElapsed.inSeconds;

    // Halfway cue — branches on step axis. Duration steps hit half on
    // time elapsed; distance steps on distance covered.
    final halfwayHit = step.isDurationBased
        ? stepSecs >= step.targetDurationSec! / 2
        : stepDist >= step.targetDistanceMetres * 0.5;
    if (!_firedHalfway && halfwayHit) {
      _firedHalfway = true;
      _events.add(StepProgressEvent(
        step: step,
        index: _idx,
        kind: StepProgressKind.halfway,
      ));
    }

    // End-of-step warning cue. For distance steps: last 50 m, gated to
    // steps longer than 100 m (else cue collides with halfway). For
    // duration steps: last 10 s, gated to durations longer than 20 s.
    final lastWindowHit = step.isDurationBased
        ? (step.targetDurationSec! - stepSecs <= 10 &&
            step.targetDurationSec! > 20)
        : (step.targetDistanceMetres - stepDist <= 50 &&
            step.targetDistanceMetres > 100);
    if (!_firedLastFifty && lastWindowHit) {
      _firedLastFifty = true;
      _events.add(StepProgressEvent(
        step: step,
        index: _idx,
        kind: StepProgressKind.lastFiftyMetres,
      ));
    }

    // Pace drift cue (rate-limited to 45 s).
    final adh = paceAdherence;
    if (adh == PaceAdherence.wayBehind || adh == PaceAdherence.wayAhead) {
      final now = DateTime.now();
      if (_lastDriftCueAt == null ||
          now.difference(_lastDriftCueAt!) >= const Duration(seconds: 45)) {
        _lastDriftCueAt = now;
        final actual = stepAveragePaceSecPerKm;
        if (actual != null) {
          _events.add(PaceDriftEvent(
            step: step,
            index: _idx,
            ahead: adh == PaceAdherence.wayAhead,
            deltaSecPerKm: (actual - step.targetPaceSecPerKm).abs(),
          ));
        }
      }
    }

    // Auto-advance — duration steps trip on elapsed time, distance
    // steps on distance covered.
    final endHit = step.isDurationBased
        ? stepSecs >= step.targetDurationSec!
        : stepDist >= step.targetDistanceMetres;
    if (endHit) {
      _advance(s, status: WorkoutStepStatus.completed);
    }
  }

  /// Skip current step — record what's been covered so far as "skipped"
  /// and advance.
  void skipStep() {
    if (isComplete) return;
    final snap = _last;
    if (snap == null) return;
    _advance(snap, status: WorkoutStepStatus.skipped);
  }

  /// Rewind one step — undoes the most recent [_advance] (whether
  /// completed or skipped). The current step's distance counter resets
  /// to zero and the previous step re-enters. No-op if there's no
  /// previous step or no snapshot to anchor on.
  ///
  /// Spec: [docs/features/workout_execution.md § Rewind step](../../../../docs/features/workout_execution.md).
  /// Only one step deep — no rewind-of-rewind history.
  bool rewindStep() {
    if (_abandoned) return false;
    if (_results.isEmpty) return false;
    final snap = _last;
    if (snap == null) return false;

    _results.removeLast();
    final prev = _idx;
    _idx -= 1;

    _stepStartDistanceMetres = snap.distanceMetres;
    _stepStartElapsed = snap.elapsed;
    _firedHalfway = false;
    _firedLastFifty = false;
    _lastDriftCueAt = null;

    _events.add(StepTransitionEvent(
      previousIndex: prev,
      currentIndex: _idx,
      step: steps[_idx],
    ));
    return true;
  }

  /// Abandon the workout — remaining steps are not added to results;
  /// the recorder keeps running as a free run.
  void abandon() {
    if (isComplete) return;
    _abandoned = true;
    _events.add(const WorkoutAbandonedEvent());
  }

  /// Snapshot per-step results for `runs.metadata.workout_step_results`.
  /// Includes the in-progress step truncated to the current distance.
  List<WorkoutStepResult> snapshotResults() {
    final out = List<WorkoutStepResult>.from(_results);
    if (!isComplete && _last != null && _idx < steps.length) {
      out.add(_resultForStep(
        index: _idx,
        step: steps[_idx],
        actualDistance: stepDistanceMetres,
        actualElapsed: stepElapsed,
        status: WorkoutStepStatus.skipped,
      ));
    }
    return out;
  }

  /// Adherence label for `runs.metadata.workout_adherence`. Computed
  /// from the snapshot of results — call after [snapshotResults].
  WorkoutAdherence adherence() {
    if (_abandoned) return WorkoutAdherence.abandoned;
    final results = snapshotResults();
    if (results.isEmpty) return WorkoutAdherence.abandoned;
    var anyShort = false;
    for (final r in results) {
      if (r.status == WorkoutStepStatus.skipped) {
        anyShort = true;
        continue;
      }
      // ≥ 80 % of target counts as "completed for adherence" — matches
      // the web review section's 'partial' cutoff. Duration-based steps
      // measure against the time axis, distance-based against the metres.
      if (r.step.isDurationBased) {
        if (r.durationSeconds < r.step.targetDurationSec! * 0.8) {
          anyShort = true;
        }
      } else if (r.actualDistanceMetres < r.step.targetDistanceMetres * 0.8) {
        anyShort = true;
      }
    }
    if (results.length < steps.length) anyShort = true;
    return anyShort ? WorkoutAdherence.partial : WorkoutAdherence.completed;
  }

  /// Build the `runs.metadata` entries for the workout review trail —
  /// `plan_workout_id`, `workout_step_results`, `workout_adherence`.
  /// Returns an empty map when [planWorkoutId] is null (no linked
  /// workout, nothing to record).
  ///
  /// Called from both the in-progress save path (so a crash mid-workout
  /// preserves the planned-vs-actual table on the recovered run) and
  /// the final save path on stop. Reading [snapshotResults] mid-run is
  /// safe — it already includes the in-progress step as a `skipped`
  /// row, which is exactly what we want for the crash case: the user
  /// sees they were partway through that rep when the app died, and
  /// adherence reads as `partial`.
  Map<String, dynamic> reviewMetadata({required String? planWorkoutId}) {
    if (planWorkoutId == null) return const <String, dynamic>{};
    return <String, dynamic>{
      'plan_workout_id': planWorkoutId,
      'workout_step_results':
          snapshotResults().map((r) => r.toJson()).toList(),
      'workout_adherence': switch (adherence()) {
        WorkoutAdherence.completed => 'completed',
        WorkoutAdherence.partial => 'partial',
        WorkoutAdherence.abandoned => 'abandoned',
      },
    };
  }

  void dispose() {
    _events.close();
  }

  void _advance(RunSnapshot s, {required WorkoutStepStatus status}) {
    final step = steps[_idx];
    _results.add(_resultForStep(
      index: _idx,
      step: step,
      actualDistance: stepDistanceMetres,
      actualElapsed: stepElapsed,
      status: status,
    ));

    final prev = _idx;
    _idx += 1;
    _stepStartDistanceMetres = s.distanceMetres;
    _stepStartElapsed = s.elapsed;
    _firedHalfway = false;
    _firedLastFifty = false;
    _lastDriftCueAt = null;

    if (_idx >= steps.length) {
      _events.add(const WorkoutCompleteEvent());
      return;
    }
    _events.add(StepTransitionEvent(
      previousIndex: prev,
      currentIndex: _idx,
      step: steps[_idx],
    ));
  }

  WorkoutStepResult _resultForStep({
    required int index,
    required WorkoutStep step,
    required double actualDistance,
    required Duration actualElapsed,
    required WorkoutStepStatus status,
  }) {
    int? actualPace;
    final secs = actualElapsed.inSeconds;
    if (actualDistance >= 5 && secs >= 1) {
      actualPace = (secs / (actualDistance / 1000)).round();
    }
    return WorkoutStepResult(
      stepIndex: index,
      step: step,
      actualDistanceMetres: actualDistance,
      actualPaceSecPerKm: actualPace,
      durationSeconds: secs,
      status: status,
    );
  }
}

enum WorkoutStepKind { warmup, rep, recovery, walk, steady, cooldown }

enum PaceAdherence { onPace, ahead, behind, wayAhead, wayBehind }

enum WorkoutStepStatus { completed, skipped }

enum WorkoutAdherence { completed, partial, abandoned }

class WorkoutStep {
  final WorkoutStepKind kind;
  final int? repIndex; // 1-based for rep + recovery
  final int? repTotal;
  final double targetDistanceMetres;
  // Duration target in whole seconds. When non-null + positive, this
  // step auto-advances on elapsed time rather than distance covered —
  // useful for time-trial reps and short pickups (e.g. 30 s strides).
  // Mutually exclusive with [targetDistanceMetres] at the call sites
  // that read the end condition; [targetDistanceMetres] is left at the
  // numeric default for duration-based steps but isn't read by the
  // auto-advance check when [isDurationBased] is true.
  final int? targetDurationSec;
  final int targetPaceSecPerKm;
  final int toleranceSecPerKm;
  final String label;

  const WorkoutStep({
    required this.kind,
    this.repIndex,
    this.repTotal,
    required this.targetDistanceMetres,
    this.targetDurationSec,
    required this.targetPaceSecPerKm,
    this.toleranceSecPerKm = 10,
    required this.label,
  });

  bool get isDurationBased =>
      targetDurationSec != null && targetDurationSec! > 0;
}

class WorkoutStepResult {
  final int stepIndex;
  final WorkoutStep step;
  final double actualDistanceMetres;
  final int? actualPaceSecPerKm;
  final int durationSeconds;
  final WorkoutStepStatus status;

  const WorkoutStepResult({
    required this.stepIndex,
    required this.step,
    required this.actualDistanceMetres,
    required this.actualPaceSecPerKm,
    required this.durationSeconds,
    required this.status,
  });

  /// JSON shape registered in `docs/backend/metadata.md` under
  /// `runs.metadata.workout_step_results`. Keep snake_case keys in sync
  /// with the TS reader on `apps/web/src/routes/runs/[id]/+page.svelte`.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'step_index': stepIndex,
      'kind': switch (step.kind) {
        WorkoutStepKind.warmup => 'warmup',
        WorkoutStepKind.rep => 'rep',
        WorkoutStepKind.recovery => 'recovery',
        WorkoutStepKind.walk => 'walk',
        WorkoutStepKind.steady => 'steady',
        WorkoutStepKind.cooldown => 'cooldown',
      },
      if (step.repIndex != null) 'rep_index': step.repIndex,
      if (step.repTotal != null) 'rep_total': step.repTotal,
      'target_distance_m': step.targetDistanceMetres,
      if (step.targetDurationSec != null)
        'target_duration_s': step.targetDurationSec,
      'actual_distance_m': actualDistanceMetres,
      'target_pace_sec_per_km': step.targetPaceSecPerKm,
      'actual_pace_sec_per_km': actualPaceSecPerKm,
      'tolerance_sec_per_km': step.toleranceSecPerKm,
      'duration_s': durationSeconds,
      'status': switch (status) {
        WorkoutStepStatus.completed => 'completed',
        WorkoutStepStatus.skipped => 'skipped',
      },
    };
  }
}

// ──────────────────────── Events ────────────────────────

abstract class WorkoutExecEvent {
  const WorkoutExecEvent();
}

class StepTransitionEvent extends WorkoutExecEvent {
  final int previousIndex; // -1 on first step
  final int currentIndex;
  final WorkoutStep step;
  const StepTransitionEvent({
    required this.previousIndex,
    required this.currentIndex,
    required this.step,
  });
}

enum StepProgressKind { halfway, lastFiftyMetres }

class StepProgressEvent extends WorkoutExecEvent {
  final WorkoutStep step;
  final int index;
  final StepProgressKind kind;
  const StepProgressEvent({
    required this.step,
    required this.index,
    required this.kind,
  });
}

class PaceDriftEvent extends WorkoutExecEvent {
  final WorkoutStep step;
  final int index;
  final bool ahead;
  final int deltaSecPerKm;
  const PaceDriftEvent({
    required this.step,
    required this.index,
    required this.ahead,
    required this.deltaSecPerKm,
  });
}

class WorkoutCompleteEvent extends WorkoutExecEvent {
  const WorkoutCompleteEvent();
}

class WorkoutAbandonedEvent extends WorkoutExecEvent {
  const WorkoutAbandonedEvent();
}

// ──────────────────── Step expansion ────────────────────

/// Expand a stored `plan_workouts` row into [WorkoutStep]s.
///
/// Inputs:
/// - [structure] — the jsonb shape from `plan_workouts.structure`
///   (warmup / repeats / steady / cooldown). Pass `null` for
///   unstructured workouts (e.g. "Easy 8 km") and the function will
///   return a single [WorkoutStep] from [fallbackDistanceMetres] +
///   [fallbackPaceSecPerKm].
/// - [paces] — symbolic pace lookups (`'easy'`, `'jog'`, `'tempo'`,
///   etc.) → seconds-per-km. Mirrors the plan's `paces` jsonb on
///   `training_plans`.
/// - [fallbackDistanceMetres] / [fallbackPaceSecPerKm] —
///   `plan_workouts.target_distance_m` and `target_pace_sec_per_km`,
///   used when [structure] is null.
List<WorkoutStep> expandWorkoutSteps({
  required Map<String, dynamic>? structure,
  required Map<String, int> paces,
  required int toleranceSecPerKm,
  double? fallbackDistanceMetres,
  int? fallbackPaceSecPerKm,
}) {
  if (structure == null || structure.isEmpty) {
    if (fallbackDistanceMetres == null || fallbackDistanceMetres <= 0) {
      return const [];
    }
    return [
      WorkoutStep(
        kind: WorkoutStepKind.steady,
        targetDistanceMetres: fallbackDistanceMetres,
        targetPaceSecPerKm:
            fallbackPaceSecPerKm ?? paces['easy'] ?? 360,
        toleranceSecPerKm: toleranceSecPerKm,
        label: 'Steady',
      ),
    ];
  }

  // Pace resolution accepts either a numeric `pace_sec_per_km` (the
  // explicit form) or a symbolic `pace` key ('easy', 'jog', etc.).
  // Real generators on this codebase mix both — warmup/cooldown use
  // `pace: 'easy'`, intervals use numeric `pace_sec_per_km`.
  int resolvePaceFrom(Map block, [String? fallbackKey]) {
    final raw = block['pace_sec_per_km'] ?? block['pace'];
    if (raw is num) return raw.round();
    if (raw is String) {
      return paces[raw] ?? paces[fallbackKey ?? 'easy'] ?? 360;
    }
    return paces[fallbackKey ?? 'easy'] ?? 360;
  }

  // Read either `distance_m` (legacy + Phase 2 default) or `duration_s`
  // (v2 — time-based steps). When both are present, distance wins so
  // existing plans don't change behaviour. Returns null if neither is
  // a usable positive number.
  WorkoutStep? buildStep({
    required Map block,
    required WorkoutStepKind kind,
    required String label,
    required String paceFallback,
    int? repIndex,
    int? repTotal,
  }) {
    final dist = (block['distance_m'] as num?)?.toDouble();
    final dur = (block['duration_s'] as num?)?.toInt();
    if (dist != null && dist > 0) {
      return WorkoutStep(
        kind: kind,
        repIndex: repIndex,
        repTotal: repTotal,
        targetDistanceMetres: dist,
        targetPaceSecPerKm: resolvePaceFrom(block, paceFallback),
        toleranceSecPerKm: toleranceSecPerKm,
        label: label,
      );
    }
    if (dur != null && dur > 0) {
      return WorkoutStep(
        kind: kind,
        repIndex: repIndex,
        repTotal: repTotal,
        targetDistanceMetres: 0,
        targetDurationSec: dur,
        targetPaceSecPerKm: resolvePaceFrom(block, paceFallback),
        toleranceSecPerKm: toleranceSecPerKm,
        label: label,
      );
    }
    return null;
  }

  final out = <WorkoutStep>[];

  final warmup = structure['warmup'];
  if (warmup is Map) {
    final step = buildStep(
      block: warmup,
      kind: WorkoutStepKind.warmup,
      label: 'Warmup',
      paceFallback: 'easy',
    );
    if (step != null) out.add(step);
  }

  // Repeats — supports two on-disk shapes:
  //   1. Spec-style: `{count, rep: {...}, recovery: {...}}`
  //   2. Generator-style: `{count, distance_m | duration_s, pace_sec_per_km,
  //      recovery_distance_m | recovery_duration_s, recovery_pace}`
  // Both shapes can now use `duration_s` instead of `distance_m` for
  // either the rep or the recovery (v2 time-based reps).
  final repeats = structure['repeats'];
  if (repeats is Map) {
    final count = (repeats['count'] as num?)?.toInt() ?? 0;
    if (count > 0) {
      Map repBlock;
      Map? recBlock;
      final nestedRep = repeats['rep'];
      final nestedRec = repeats['recovery'];
      if (nestedRep is Map) {
        repBlock = nestedRep;
        recBlock = nestedRec is Map ? nestedRec : null;
      } else {
        repBlock = repeats;
        // Flatten the generator shape into a recovery-block map so
        // buildStep can read it uniformly.
        recBlock = {
          if (repeats['recovery_distance_m'] != null)
            'distance_m': repeats['recovery_distance_m'],
          if (repeats['recovery_duration_s'] != null)
            'duration_s': repeats['recovery_duration_s'],
          if (repeats['recovery_pace_sec_per_km'] != null)
            'pace_sec_per_km': repeats['recovery_pace_sec_per_km'],
          if (repeats['recovery_pace'] != null)
            'pace': repeats['recovery_pace'],
        };
        if (recBlock.isEmpty) recBlock = null;
      }

      // Walk-run sessions (recovery_pace == 'walk') relabel the work/rest
      // intervals as Run / Walk and tag the rest step as a walk so the
      // recorder's TTS announces "Run"/"Walk" instead of "Rep"/"Recovery"
      // (persona #22).
      final isWalkRun = recBlock != null && recBlock['pace'] == 'walk';
      for (var i = 0; i < count; i++) {
        final repStep = buildStep(
          block: repBlock,
          kind: WorkoutStepKind.rep,
          label: isWalkRun ? 'Run ${i + 1}/$count' : 'Rep ${i + 1}/$count',
          paceFallback: isWalkRun ? 'easy' : 'interval',
          repIndex: i + 1,
          repTotal: count,
        );
        if (repStep == null) {
          // Malformed rep block — skip the entire repeats group.
          break;
        }
        out.add(repStep);
        if (i < count - 1 && recBlock != null) {
          final recStep = buildStep(
            block: recBlock,
            kind: isWalkRun ? WorkoutStepKind.walk : WorkoutStepKind.recovery,
            label: isWalkRun
                ? 'Walk ${i + 1}/${count - 1}'
                : 'Recovery ${i + 1}/${count - 1}',
            paceFallback: isWalkRun ? 'easy' : 'jog',
            repIndex: i + 1,
            repTotal: count - 1,
          );
          if (recStep != null) out.add(recStep);
        }
      }
    }
  }

  final steady = structure['steady'];
  if (steady is Map) {
    final step = buildStep(
      block: steady,
      kind: WorkoutStepKind.steady,
      label: 'Steady',
      paceFallback: 'tempo',
    );
    if (step != null) out.add(step);
  }

  final cooldown = structure['cooldown'];
  if (cooldown is Map) {
    final step = buildStep(
      block: cooldown,
      kind: WorkoutStepKind.cooldown,
      label: 'Cooldown',
      paceFallback: 'easy',
    );
    if (step != null) out.add(step);
  }

  return out;
}
