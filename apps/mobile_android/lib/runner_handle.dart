/// Persona-hunt Round 3 finding Privacy #5. Anonymous handle for live-
/// spectator surfaces (mobile twin of `apps/web/src/lib/runner_handle.ts`).
/// Take the first 4 hex chars of the v4 uuid, upper-case them, prefix
/// with `Runner #`. Deterministic so two spectators of the same runner
/// see the same handle but anonymous because 4 hex chars are useless
/// for identification without the uuid you already need.
///
/// Mirrored from the web `runner_handle.ts` module — keep both in
/// lockstep. The shared-library-syncer agent flags divergence.
String runnerHandle(String? userId) {
  if (userId == null || userId.isEmpty) return 'Runner';
  final stripped = userId.replaceAll('-', '');
  if (stripped.length < 4) return 'Runner';
  return 'Runner #${stripped.substring(0, 4).toUpperCase()}';
}

/// Decides whether a mobile spectator should see the runner's
/// display_name or the anonymous handle. The persona contract is
/// "friends see the real name, strangers see the handle" — `friends`
/// here is a soft definition (one-way follow in either direction
/// counts, plus the runner viewing their own live broadcast).
///
/// Returns true when the display_name should be revealed.
bool shouldRevealDisplayName({
  required String? viewerUserId,
  required String? runnerUserId,
  required bool viewerFollowsRunner,
  required bool runnerFollowsViewer,
}) {
  if (runnerUserId == null) return false;
  if (viewerUserId == null) return false;
  if (viewerUserId == runnerUserId) return true;
  return viewerFollowsRunner || runnerFollowsViewer;
}
