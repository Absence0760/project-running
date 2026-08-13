import 'package:core_models/core_models.dart' as cm;

/// Pure helper: given a gear `kind` ('shoe' or 'bike'), a "since"
/// date, and a list of runs, return the subset that's a plausible
/// candidate for backfill — runs of an activity type that matches
/// the gear kind, dated on or after `since`.
///
/// Twin of `apps/web/src/lib/gear/gear_backfill.ts` — keep in lockstep
/// (activity mapping, boundary, ordering, edge cases).
///
/// A run with a missing `metadata.activity_type` defaults to `run` to
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
  final cutoffUtc = since.toUtc();
  final filtered = runs.where((r) {
    final activity =
        (r.metadata?['activity_type'] as String?)?.toLowerCase() ?? 'run';
    if (!_matchesGearKind(gearKind, activity)) return false;
    return !r.startedAt.toUtc().isBefore(cutoffUtc);
  }).toList();
  filtered.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return filtered;
}

/// Can this activity plausibly have been done in this gear kind?
///
/// DERIVED as "the bike takes cycling, everything else takes shoes", which is
/// the `auto_tag_default_gear` trigger's mapping verbatim (`case activity_type
/// when 'cycle' then 'bike' else 'shoe' end`, re-emitted over the promoted
/// column by migration `20261207_001`). Deliberately NOT an enumerated shoe
/// allowlist: `{run, walk, hike}` silently dropped `stroller` — a real value in
/// `runs_activity_type_check` — so the trigger auto-tagged a stroller run with
/// the current pair while backfill never offered it. An enumeration has to be
/// revisited every time the CHECK grows; this cannot fall behind it.
///
/// An unrecognised gear kind falls through to shoe semantics rather than
/// returning nothing, so a future gear kind can't silently make the prompt
/// disappear either.
bool _matchesGearKind(String gearKind, String activity) {
  return gearKind == 'bike' ? activity == 'cycle' : activity != 'cycle';
}
