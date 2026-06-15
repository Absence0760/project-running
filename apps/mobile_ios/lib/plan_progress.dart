/// Plan-progress derivations — the two stats the plan-detail header was
/// missing: the longest long run completed so far, and the overall
/// base→build→peak→taper arc the current week sits in. Pure (no Supabase /
/// Flutter); the UI formats + localizes the results.
///
/// Dart twin of `apps/web/src/lib/training/plan_progress.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
library;

/// Canonical phase ordering. Plans don't always use every phase, and the
/// rows aren't guaranteed to be stored in order, so the marker derives its
/// sequence from this rather than from row order.
const List<String> planPhaseOrder = ['base', 'build', 'peak', 'taper', 'race'];

/// A plan week as far as the phase marker cares — only its phase string.
class PlanProgressWeek {
  final String phase;
  const PlanProgressWeek(this.phase);
}

/// The distinct phases the plan moves through, de-duplicated and sorted into
/// canonical order. Drives the overall phase marker.
List<String> orderedPlanPhases(List<PlanProgressWeek> weeks) {
  final present = weeks.map((w) => w.phase).toSet();
  return planPhaseOrder.where(present.contains).toList();
}

/// A planned workout as far as the longest-long-run stat cares.
class LongRunWorkout {
  final String kind;
  final double? targetDistanceM;
  final String? completedRunId;
  final bool? manuallyCompleted;
  const LongRunWorkout({
    required this.kind,
    required this.targetDistanceM,
    this.completedRunId,
    this.manuallyCompleted,
  });
}

/// Longest long run completed so far, in metres. Prefers the actual recorded
/// distance of the linked run (looked up in [actualById] by run id); falls
/// back to the workout's planned target when the run isn't in the supplied
/// map (e.g. it dropped off the recent-runs window). Returns null when no
/// long run has been completed yet.
double? longestCompletedLongRunMetres(
  List<LongRunWorkout> workouts, [
  Map<String, double> actualById = const {},
]) {
  double? max;
  for (final w in workouts) {
    if (w.kind != 'long') continue;
    final completed = w.manuallyCompleted == true || w.completedRunId != null;
    if (!completed) continue;
    final actual =
        w.completedRunId != null ? actualById[w.completedRunId] : null;
    // A non-positive actual (degenerate / distance-less linked run) is
    // treated as missing, falling back to the planned target — `actual ??`
    // would keep a 0 and drop the long run from the max entirely.
    final dist = (actual != null && actual > 0) ? actual : (w.targetDistanceM ?? 0);
    if (dist > 0 && (max == null || dist > max)) max = dist;
  }
  return max;
}
