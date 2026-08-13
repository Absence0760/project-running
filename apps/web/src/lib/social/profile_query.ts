// Direct-profile lookup parsing for People search (issue #465).
//
// A pasted profile uuid — or a `/u/<uuid>` profile URL — resolves that exact
// runner directly, instead of running a name/handle search. Safe because it
// requires already knowing the full uuid (no enumeration surface), and it
// mirrors the existing public `/u/[id]` page's own lookup path.
//
// TS↔Dart parity pair with `packages/core_models/lib/src/profile_query.dart`
// — keep the extraction rules in lockstep. The Dart side lives in the shared
// package rather than under apps/mobile_android/lib/, so it needs no iOS-twin
// mirror and its suite is packages/core_models/test/profile_query_test.dart.

const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const BARE_UUID_RE = new RegExp(`^${UUID}$`, 'i');
// The uuid must sit right after a `/u/` segment so an arbitrary string that
// merely contains a uuid substring isn't mistaken for a profile link.
const URL_UUID_RE = new RegExp(`/u/(${UUID})(?:[/?#]|$)`, 'i');

/// Returns the lowercased profile uuid if `input` is a bare uuid or a
/// `/u/<uuid>` profile URL/path, else null.
export function extractProfileId(input: string): string | null {
	const term = (input ?? '').trim();
	if (!term) return null;
	if (BARE_UUID_RE.test(term)) return term.toLowerCase();
	const inUrl = term.match(URL_UUID_RE);
	if (inUrl) return inUrl[1].toLowerCase();
	return null;
}
