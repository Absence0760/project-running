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
///
/// The count/text primitives come from `import_completeness.dart` rather
/// than living here: a sync IS an import, and one home for that rule is what
/// stops the two parsers reading the same malformed body differently.
library;

import 'import_completeness.dart';

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
  final error = importResponseText(data['error']);
  final complete = error == null && data['complete'] == true;
  return StravaSyncResult(
    imported: importResponseCount(data['imported']),
    skipped: importResponseCount(data['skipped']),
    failed: importResponseCount(data['failed']),
    rateLimited: data['rate_limited'] == true,
    complete: complete,
    resumable: !complete && data['resumable'] == true,
    athleteId: importResponseText(data['athlete_id']),
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
