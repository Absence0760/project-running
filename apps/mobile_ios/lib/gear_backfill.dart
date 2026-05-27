import 'package:core_models/core_models.dart' as cm;

/// Pure helper: given a gear `kind` ('shoe' or 'bike'), a "since"
/// date, and a list of runs, return the subset that's a plausible
/// candidate for backfill — runs of an activity type that matches
/// the gear kind, dated on or after `since`.
///
/// Activity-type mapping mirrors the Settings → Gear web copy
/// ("Track shoes + bikes"): shoes go with running activities (run,
/// walk, hike — the trail-run alias), bikes go with cycle. A run
/// with a missing `metadata.activity_type` defaults to `run` to
/// match the rest of the app (`run_screen` + Strava import treat
/// unset as run).
///
/// The list is returned newest-first so the backfill sheet's
/// default top-N selection lands on the most-recent runs.
List<cm.Run> gearBackfillCandidates({
  required String gearKind,
  required DateTime since,
  required Iterable<cm.Run> runs,
}) {
  final allowed = _allowedActivitiesFor(gearKind);
  final cutoffUtc = since.toUtc();
  final filtered = runs.where((r) {
    final activity =
        (r.metadata?['activity_type'] as String?)?.toLowerCase() ?? 'run';
    if (!allowed.contains(activity)) return false;
    return !r.startedAt.toUtc().isBefore(cutoffUtc);
  }).toList();
  filtered.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return filtered;
}

Set<String> _allowedActivitiesFor(String gearKind) {
  switch (gearKind) {
    case 'bike':
      return const {'cycle'};
    case 'shoe':
    default:
      return const {'run', 'walk', 'hike'};
  }
}
