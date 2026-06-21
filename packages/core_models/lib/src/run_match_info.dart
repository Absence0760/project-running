import 'waypoint.dart';

/// Status of a run's map-match attempt. Mirrors the CHECK constraint
/// on `run_matched_tracks.status` in migration
/// `20260609_001_run_match_pipeline.sql`.
enum MatchStatus {
  pending,
  matched,
  failed,
  skipped;

  static MatchStatus fromName(String name) {
    return MatchStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => MatchStatus.pending,
    );
  }
}

/// Map-match metadata + the matched track payload, joined into one
/// shape so screens have everything they need from a single fetch.
/// Track is null until the worker writes a matched gz to Storage and
/// the client downloads it; status reflects the row state regardless.
class RunMatchInfo {
  final MatchStatus status;
  final String? algorithm;
  final String? algorithmVersion;
  final DateTime? matchedAt;
  final List<Waypoint>? track;

  /// True when the row is `matched` but the matched gz couldn't be
  /// downloaded because the backend/network was unreachable (as opposed
  /// to a corrupt/missing object). The caller renders the raw track and
  /// an honest "offline / will retry" status, and re-fetches when
  /// connectivity returns — distinct from a `failed`/`skipped` server
  /// verdict, which is terminal and not worth retrying.
  final bool trackUnreachable;

  const RunMatchInfo({
    required this.status,
    this.algorithm,
    this.algorithmVersion,
    this.matchedAt,
    this.track,
    this.trackUnreachable = false,
  });

  /// True iff the matched track is fully populated and renderable.
  /// Screens should branch on this rather than `status == matched`
  /// alone, because the row can be `matched` while the gz download
  /// is still in flight or has failed.
  bool get hasRenderableTrack =>
      status == MatchStatus.matched && (track?.length ?? 0) >= 2;
}

/// Best-effort classifier for "the map-match read failed because the
/// backend/network was unreachable" vs "the server gave a definite
/// answer". Used to decide whether the run-detail surface shows an
/// honest offline/will-retry status (and re-fetches on reconnect) or
/// treats the result as terminal. Pure + Supabase-free so it can be
/// unit-tested without booting the client.
///
/// Recognises the transport-layer signals the Supabase Dart client
/// surfaces on a dead connection — `dart:io` `SocketException` /
/// `HttpException`, `http` `ClientException`, `TimeoutException`, and
/// the "Failed host lookup" / "Connection refused" / "Network is
/// unreachable" message bodies — while leaving a PostgREST/Storage
/// error (a real status/permission verdict) classified as reachable.
bool isMatchUnreachableError(Object error) {
  final type = error.runtimeType.toString();
  if (type == 'SocketException' ||
      type == 'HttpException' ||
      type == 'ClientException' ||
      type == 'TimeoutException') {
    return true;
  }
  final msg = error.toString().toLowerCase();
  const needles = [
    'socketexception',
    'failed host lookup',
    'connection refused',
    'connection closed',
    'connection reset',
    'connection timed out',
    'network is unreachable',
    'no address associated',
    'software caused connection abort',
    'timeoutexception',
    'clientexception',
  ];
  for (final n in needles) {
    if (msg.contains(n)) return true;
  }
  return false;
}

/// The status the run-detail map-match pill should show. Folds the
/// server [MatchStatus] together with the client-side offline signal so
/// the widget renders one of a small, exhaustive set of states. Pure so
/// the mapping is unit-tested without pumping a widget.
///
/// `offline` is the screen's "the last match read couldn't reach the
/// backend" flag; it takes precedence over a stale `pending` row but
/// NOT over a terminal `failed`/`skipped` verdict already read from the
/// server (that answer is authoritative and re-fetching won't change
/// it). A `matched` row whose gz couldn't be downloaded
/// ([RunMatchInfo.trackUnreachable]) also reads as offline.
enum MatchPillKind { hidden, pending, offline, failed, skipped }

MatchPillKind matchPillKind(RunMatchInfo? info, {required bool offline}) {
  if (info == null) {
    return offline ? MatchPillKind.offline : MatchPillKind.hidden;
  }
  switch (info.status) {
    case MatchStatus.matched:
      return info.trackUnreachable
          ? MatchPillKind.offline
          : MatchPillKind.hidden;
    case MatchStatus.pending:
      return offline ? MatchPillKind.offline : MatchPillKind.pending;
    case MatchStatus.failed:
      return MatchPillKind.failed;
    case MatchStatus.skipped:
      return MatchPillKind.skipped;
  }
}

/// Whether a connectivity-return (or a foreground resume) should kick a
/// fresh map-match read for the currently-shown state. True only when
/// there's something an online re-fetch could improve — an unread row
/// (offline-on-open), a still-`pending` row, or a `matched` row whose
/// track we couldn't download — and false for a terminal
/// `failed`/`skipped`/already-rendered state. Keeps the retry bounded
/// and idempotent: a settled run never re-hits the backend.
bool shouldRetryMatchFetch(RunMatchInfo? info, {required bool offline}) {
  if (info == null) return offline;
  switch (info.status) {
    case MatchStatus.matched:
      return info.trackUnreachable;
    case MatchStatus.pending:
      return true;
    case MatchStatus.failed:
    case MatchStatus.skipped:
      return false;
  }
}
