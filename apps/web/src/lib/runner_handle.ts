// Persona-hunt Round 3 finding Privacy #5. Live-spectator surfaces
// (the /live/[id] page + the mobile spectator screen) used to show
// the runner's `display_name` verbatim, which is a friendly identifier
// — sharing a live URL externally would expose the runner's real
// name to anyone with the link, including stalkers / harassers /
// random crawlers picking up the share-page unfurl. The privacy-
// conscious persona expected an anonymous handle (e.g. `Runner #ABCD`)
// for non-friend spectators.
//
// `runnerHandle(userId)` is the canonical handle derivation: take the
// first 4 hex chars of the v4 uuid, upper-case them, prefix with
// `Runner #`. Deterministic so two spectators of the same runner see
// the same handle (helps tell two simultaneous live broadcasts apart
// on a club leaderboard) but anonymous because 4 hex chars are
// useless for identification without the uuid you already need.
//
// Mirrored byte-for-byte in `apps/mobile_android/lib/runner_handle.dart`
// (the Dart twin) — keep the algorithm in lockstep; the
// `shared-library-syncer` agent flags divergence.

/// Returns `Runner #ABCD` where ABCD is the first 4 hex characters
/// of `userId` upper-cased. Returns `Runner` (no suffix) for null /
/// empty input — anon-broadcaster runs that somehow lost their
/// user_id reference shouldn't crash the page.
export function runnerHandle(userId: string | null | undefined): string {
	if (!userId) return 'Runner';
	const stripped = userId.replace(/-/g, '');
	const slug = stripped.slice(0, 4).toUpperCase();
	if (slug.length < 4) return 'Runner';
	return `Runner #${slug}`;
}

/// Decides whether a spectator should see the runner's display_name
/// or the anonymous handle. The persona contract is "friends see the
/// real name, strangers see the handle" — `friends` here is a soft
/// definition (a one-way follow in either direction counts, plus the
/// runner viewing their own live broadcast).
///
/// Inputs:
///  - viewerUserId: signed-in viewer's auth.uid, or null for anon.
///  - runnerUserId: the broadcaster's auth.uid.
///  - viewerFollowsRunner: viewer→runner edge in user_follows.
///  - runnerFollowsViewer: runner→viewer edge in user_follows.
///
/// Returns true when the display_name should be revealed.
export function shouldRevealDisplayName(opts: {
	viewerUserId: string | null;
	runnerUserId: string | null;
	viewerFollowsRunner: boolean;
	runnerFollowsViewer: boolean;
}): boolean {
	if (!opts.runnerUserId) return false;
	if (!opts.viewerUserId) return false; // anon — never reveal
	if (opts.viewerUserId === opts.runnerUserId) return true; // self
	return opts.viewerFollowsRunner || opts.runnerFollowsViewer;
}
