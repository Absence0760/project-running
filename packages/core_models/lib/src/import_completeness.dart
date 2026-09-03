/// What an importer says about how much of a history it read, and how much of
/// it a client may believe.
///
/// `parkrun-import` answers `{ imported, skipped, total, complete }` and
/// `race-results-import` answers `complete` on every success shape. Neither
/// count reveals a shortfall on its own: a parkrun history capped at
/// `MAX_PARKRUN_ROWS` and a finisher field truncated at 2,000 both present as
/// a successful import of everything that was there.
///
/// Fail-closed — anything this parser cannot read as an explicit `true` is
/// reported as partial. One transport per importer, shipped from this repo
/// alongside its callers, so an absent `complete` means a body this build does
/// not recognise rather than an older deployment of a second transport. A
/// false "partial" costs a sentence the runner can ignore; a false "complete"
/// tells them a history is whole when it is not.
///
/// The two count/text primitives below are public because
/// `strava_sync_result.dart` grades the same fields by the same rule — a sync
/// IS an import, and one home for that rule is what stops the two parsers
/// reading the same malformed body differently. `strava_sync_result` composes
/// on this library rather than the reverse: naming the general rule after one
/// provider is what put parkrun and race-results grading in a file called
/// `strava_sync_result` in the first place (decisions § 1014).
///
/// TS↔Dart parity pair with
/// `apps/web/src/lib/integrations/import_completeness.ts`. Lives in the SHARED
/// core_models package rather than under `apps/mobile_android/lib/` because
/// `api_client` consumes it, so it needs no iOS-twin mirror — same placement
/// as `profile_query.dart` and `strava_sync_result.dart`.
library;

/// A count the function sent. Only a non-negative integer is a count;
/// anything else (a fraction, a negative, a string, null, absent) is a
/// malformed payload and reads as 0 rather than as a number the banner would
/// then state as fact.
///
/// A whole `double` counts, because JSON has one number type and the web
/// twin's `Number.isInteger` cannot tell `12` from `12.0` — rejecting it here
/// would be a divergence rather than a stricter contract.
int importResponseCount(Object? value) {
  if (value is! num || !value.isFinite || value < 0) return 0;
  if (value != value.roundToDouble()) return 0;
  return value.toInt();
}

/// A non-blank string the function sent, trimmed, or null.
String? importResponseText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

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

/// Grade an importer's response. Never throws.
ImportCompleteness parseImportCompleteness(Object? data) {
  if (data is! Map) {
    return const ImportCompleteness(
        imported: 0, skipped: 0, total: null, complete: false);
  }
  final imported = importResponseCount(data['imported']);
  final skipped = importResponseCount(data['skipped']);
  // An embedded error forces partial even beside a `complete: true`, matching
  // `stravaSyncResultFromResponse`: the function answered about a walk it did
  // not finish.
  final complete =
      importResponseText(data['error']) == null && data['complete'] == true;
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
