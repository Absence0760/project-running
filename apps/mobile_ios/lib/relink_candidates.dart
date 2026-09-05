/// Pure candidate-selection logic for the workout re-link picker.
///
/// Dart twin of `apps/web/src/lib/training/relink_candidates.ts` — keep
/// in lockstep (algorithm, edge cases, outputs, test counts).
///
/// Re-linking a completed run to a different planned workout must not
/// let one run count toward two workouts' `plan_progress`, so the picker
/// must NOT offer a run already linked (auto-matched or manually) to
/// *another* workout. The service fetches the owner's runs + the set of
/// run ids already linked anywhere in the owner's plans; this function
/// decides which are eligible, and in what order, for a given workout.

class RelinkCandidateRun {
  final String id;

  /// When the run started (`runs.started_at`).
  final DateTime startedAt;

  /// Metres covered (`runs.distance_m`).
  final double distanceM;

  /// Seconds of moving/elapsed time (`runs.duration_s`).
  final int durationS;

  const RelinkCandidateRun({
    required this.id,
    required this.startedAt,
    required this.distanceM,
    required this.durationS,
  });
}

const int kDefaultRelinkWindowDays = 7;

/// Calendar-day distance between a run's start and the scheduled date.
int _dayGap(DateTime runStart, DateTime scheduledDate) {
  final local = runStart.isUtc ? runStart.toLocal() : runStart;
  // Anchor both calendar days in UTC so a DST transition between them cannot
  // perturb the span. Local-midnight spans drift to 23 h / 25 h across a DST
  // boundary; Duration.inDays then truncated that toward zero where web rounds
  // it, so the ±window gate included/excluded a candidate the other platform
  // didn't. UTC-anchored, the gap is the exact calendar-day difference on both
  // platforms. Mirrors web's relink dayGap.
  final runDay = DateTime.utc(local.year, local.month, local.day);
  final scheduled =
      DateTime.utc(scheduledDate.year, scheduledDate.month, scheduledDate.day);
  return runDay.difference(scheduled).inDays.abs();
}

/// Eligible re-link candidates for a workout, newest-first.
///
/// A run is eligible when it is in-window (within ±[windowDays] of the
/// scheduled date) AND not already linked to a *different* workout. The
/// workout's own current run stays eligible regardless of window so the
/// current pick is always visible.
///
/// The order is TOTAL — `startedAt` descending, then `id` ascending — rather
/// than merely stable. Neither fetcher's `.order()` carries a secondary key and
/// the two queries differ (web windows on `started_at` and OR-s in the current
/// pick; this side reads the owner's whole history), so two runs sharing an
/// exact instant reached the sort in whatever order Postgres happened to return
/// them. `List.sort` is not stable: measured over 720,000 random lists it
/// matched a stable sort on every one of 400,000 at 33 elements or fewer and on
/// none of 320,000 past it (decisions § 1241). A total order makes both
/// unobservable.
List<RelinkCandidateRun> filterRelinkCandidates({
  required List<RelinkCandidateRun> runs,
  required Iterable<String> linkedRunIds,
  required String? currentRunId,
  required DateTime scheduledDate,
  int windowDays = kDefaultRelinkWindowDays,
}) {
  final linked = linkedRunIds.toSet();
  // The current run is allowed even though it's in `linked`.
  if (currentRunId != null) linked.remove(currentRunId);

  final out = runs.where((r) {
    // Never offer a run linked to another workout — that would
    // double-count it in plan_progress.
    if (linked.contains(r.id)) return false;
    // The current pick is always in; everything else must be inside
    // the date window.
    if (r.id == currentRunId) return true;
    return _dayGap(r.startedAt, scheduledDate) <= windowDays;
  }).toList();

  out.sort((a, b) {
    final byStart = b.startedAt.compareTo(a.startedAt);
    return byStart != 0 ? byStart : a.id.compareTo(b.id);
  });
  return out;
}
