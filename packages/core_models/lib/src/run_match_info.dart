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

  const RunMatchInfo({
    required this.status,
    this.algorithm,
    this.algorithmVersion,
    this.matchedAt,
    this.track,
  });

  /// True iff the matched track is fully populated and renderable.
  /// Screens should branch on this rather than `status == matched`
  /// alone, because the row can be `matched` while the gz download
  /// is still in flight or has failed.
  bool get hasRenderableTrack =>
      status == MatchStatus.matched && (track?.length ?? 0) >= 2;
}
