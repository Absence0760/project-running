import 'training_load.dart' show LiftForLoad, LiftSetForLoad;

/// Bridges flat gym set-history rows into the input the training-load model
/// expects ([LiftForLoad]: one entry per session with its sets). Pure +
/// unit-tested so the dashboard can feed real lifts into
/// computeTrainingLoadSeries and have CTL/ATL/TSB reflect them, while the
/// run-only curve stays recoverable (the model tags lift stress separately;
/// see training_load.dart § "Separable provenance").
///
/// Dart twin of `apps/web/src/lib/gym/lift_load.ts` — keep in lockstep.

/// One flat set row joined to its workout start time. Mirrors the web
/// `SetWithWorkoutDate` shape. Kept store-free so this stays a pure module.
class SetWithWorkoutDate {
  final String workoutId;
  final String startedAt;
  final num? reps;
  final num? weightKg;
  final num? rpe;
  const SetWithWorkoutDate({
    required this.workoutId,
    required this.startedAt,
    this.reps,
    this.weightKg,
    this.rpe,
  });
}

/// Group flat set-history rows into per-session [LiftForLoad] entries.
/// Sessions with no started_at (an RLS-stripped join) are dropped — a lift
/// with no date can't land on a calendar day, so it can't carry stress.
/// Order is not significant; computeTrainingLoadSeries buckets by local day.
List<LiftForLoad> liftsFromSetHistory(List<SetWithWorkoutDate> history) {
  final byWorkout = <String, _MutableLift>{};
  for (final s in history) {
    if (s.workoutId.isEmpty || s.startedAt.isEmpty) continue;
    final lift = byWorkout.putIfAbsent(
      s.workoutId,
      () => _MutableLift(s.startedAt),
    );
    lift.sets.add(LiftSetForLoad(reps: s.reps, weightKg: s.weightKg, rpe: s.rpe));
  }
  return [
    for (final l in byWorkout.values)
      LiftForLoad(startedAt: DateTime.parse(l.startedAt), sets: l.sets),
  ];
}

class _MutableLift {
  final String startedAt;
  final List<LiftSetForLoad> sets = [];
  _MutableLift(this.startedAt);
}
