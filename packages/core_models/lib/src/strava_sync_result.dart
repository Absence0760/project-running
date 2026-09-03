/// What the `strava-import` Edge Function says about a backfill, and how
/// much of it a client may believe.
///
/// The function walks Strava's activity pages until it reaches the end of
/// the lookback window — or until Strava throttles us (429/503), an
/// upstream call fails, the transport drops, a page comes back malformed,
/// or the 20-page safety cap trips. Five of those seven exits leave
/// activities in the window unfetched. [StravaSyncResult.complete]
/// separates them from a finished walk; [StravaSyncResult.rateLimited]
/// names the one cause the runner can act on (wait ~15 minutes) rather than
/// merely retry.
///
/// This matters more than a missing count. The window is measured from the
/// moment of the call, so the activities a truncated sync skipped stay
/// reachable by a later sync ONLY until they age past `lookbackDays`. A
/// sync that reports "complete" when it is not is therefore a data loss on
/// a fuse as long as the window: it is the report, not the truncation, that
/// stops the runner from syncing again.
///
/// [StravaSyncResult.resumable] is what makes "sync again" an instruction
/// that can succeed. The function stores the window still to walk on
/// `integrations.sync_cursor`, so a re-sync continues from the frontier
/// instead of re-walking the same pages and stopping at the same cap. A
/// truncation that got nowhere — throttled on the first page — records
/// nothing and says so, because "carry on from where we stopped" would be a
/// claim about a point that does not exist.
///
/// Hence the fail-closed direction — anything this parser cannot read as an
/// explicit `true` is reported as partial.
///
/// TS↔Dart parity pair with `apps/web/src/lib/integrations/strava_sync_result.ts`.
/// Lives in the SHARED core_models package rather than under
/// `apps/mobile_android/lib/` because `api_client` consumes it, so it needs
/// no iOS-twin mirror — same placement as `profile_query.dart`.
library;

class StravaSyncResult {
  const StravaSyncResult({
    required this.imported,
    required this.skipped,
    required this.failed,
    required this.rateLimited,
    required this.complete,
    required this.resumable,
    this.athleteId,
    this.error,
  });

  final int imported;
  final int skipped;
  final int failed;

  /// Strava throttled us mid-walk. Implies [complete] is false.
  final bool rateLimited;

  /// The lookback window was walked to its end. Only an explicit `true`
  /// from the function earns this.
  final bool complete;

  /// A re-sync continues from where this walk stopped rather than starting
  /// the window again. Never true alongside [complete] — a finished window
  /// leaves nothing to resume.
  final bool resumable;

  /// Present on the `connect` response only.
  final String? athleteId;

  /// An error the function embedded in an otherwise-2xx body. Forces
  /// [complete] false — a body that reports a failure is not evidence that
  /// a window was walked.
  final String? error;
}

/// A count the function sent. Only a non-negative integer is a count;
/// anything else (a fraction, a negative, a string, null, absent) is a
/// malformed payload and reads as 0 rather than as a number the banner
/// would then state as fact.
///
/// A whole `double` counts, because JSON has one number type and the web
/// twin's `Number.isInteger` cannot tell `12` from `12.0` — rejecting it
/// here would be a divergence rather than a stricter contract.
int _count(Object? value) {
  if (value is! num || !value.isFinite || value < 0) return 0;
  if (value != value.roundToDouble()) return 0;
  return value.toInt();
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Grade the function's response. Never throws: an unrecognised shape — null,
/// a list, a string, a body from a deployment that predates `complete` —
/// yields zeroed counts and `complete: false`, which every caller renders as
/// "sync again to finish".
StravaSyncResult stravaSyncResultFromResponse(Object? data) {
  if (data is! Map) {
    return const StravaSyncResult(
      imported: 0,
      skipped: 0,
      failed: 0,
      rateLimited: false,
      complete: false,
      resumable: false,
    );
  }
  final error = _text(data['error']);
  final complete = error == null && data['complete'] == true;
  return StravaSyncResult(
    imported: _count(data['imported']),
    skipped: _count(data['skipped']),
    failed: _count(data['failed']),
    rateLimited: data['rate_limited'] == true,
    complete: complete,
    resumable: !complete && data['resumable'] == true,
    athleteId: _text(data['athlete_id']),
    error: error,
  );
}

/// How far back a sync may ask the function to walk, in days. The function
/// refuses anything above [kStravaLookbackMaxDays] outright (400
/// `invalid_lookback_days`), so this list and that bound are one contract
/// across three rails — the two clients and the Edge Function.
///
/// The default stays at 90 deliberately. Strava's per-user budget is 100
/// requests / 15 minutes and the walk spends one per 50 activities, so
/// raising the default would make every routine sync several times heavier
/// for the sake of history the runner already has. Widening is an explicit
/// act, taken once, to recover from a truncation left too long.
const int kStravaLookbackDefaultDays = 90;
const int kStravaLookbackMaxDays = 365;
const List<int> kStravaLookbackOptions = [90, 180, 365];

/// Whether a widened window can still reach the runs they are after. Older
/// than the maximum and no sync can fetch them — the Strava bulk export is
/// the only path, which is why both surfaces say so rather than offering a
/// window that will come back empty.
bool isStravaLookbackReachable(int days) =>
    days > 0 && days <= kStravaLookbackMaxDays;

/// What a SCRAPER importer says about how much it read, and how much of it a
/// client may believe.
///
/// `parkrun-import` answers `{ imported, skipped, total, complete }` and
/// `race-results-import` answers `complete` on every success shape. Neither
/// count reveals a shortfall on its own: a parkrun history capped at
/// `MAX_PARKRUN_ROWS` and a finisher field truncated at 2,000 both present as
/// a successful import of everything that was there.
///
/// Same fail-closed direction as [parseStravaSyncResult], for the same reason
/// and not by analogy: one transport per importer, shipped from this repo
/// alongside its callers, so an absent `complete` means a body this build does
/// not recognise rather than an older deployment of a second transport. A
/// false "partial" costs a sentence the runner can ignore; a false "complete"
/// tells them a history is whole when it is not.
///
/// Lives beside the Strava parser rather than in a module of its own because
/// it is the SAME rule — a new module would be a parity pair, and a pair that
/// neither registry names is a pair whose divergence nothing detects
/// (decisions § 641). Splitting the three parsers into a registered
/// `import_completeness` pair is filed.
class ImportCompleteness {
  final int imported;
  final int skipped;

  /// How many rows the page actually carried, when the function said. Null
  /// when it did not, so a caller can tell "12 of 60" from "12, and there may
  /// be more" rather than printing a fabricated denominator.
  final int? total;

  /// Only an explicit `true` earns it.
  final bool complete;

  const ImportCompleteness({
    required this.imported,
    required this.skipped,
    required this.total,
    required this.complete,
  });
}

/// Grade a scraper importer's response. Never throws.
ImportCompleteness parseImportCompleteness(Object? data) {
  if (data is! Map) {
    return const ImportCompleteness(
        imported: 0, skipped: 0, total: null, complete: false);
  }
  final imported = _count(data['imported']);
  final skipped = _count(data['skipped']);
  // An embedded error forces partial even beside a `complete: true`, matching
  // [parseStravaSyncResult]: the function answered about a walk it did not
  // finish.
  final complete = _text(data['error']) == null && data['complete'] == true;
  final rawTotal = data['total'];
  final total = rawTotal is num &&
          rawTotal.isFinite &&
          rawTotal >= 0 &&
          rawTotal == rawTotal.roundToDouble()
      ? rawTotal.toInt()
      : null;
  return ImportCompleteness(
    imported: imported,
    skipped: skipped,
    // A total below what was already processed is not a total — reporting
    // "12 of 5" is worse than reporting no denominator at all.
    total: total != null && total >= imported + skipped ? total : null,
    complete: complete,
  );
}
