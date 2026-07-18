/// Direct-profile lookup parsing for People search (issue #465).
///
/// A pasted profile uuid — or a `/u/<uuid>` profile URL — resolves that exact
/// runner directly, instead of running a name/handle search. Safe because it
/// requires already knowing the full uuid (no enumeration surface), and it
/// mirrors the existing public `/u/[id]` page's own lookup path.
///
/// TS↔Dart parity pair with `apps/web/src/lib/social/profile_query.ts` —
/// keep the extraction rules in lockstep.
library;

const String _uuid =
    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
final RegExp _bareUuidRe = RegExp('^$_uuid\$', caseSensitive: false);
// The uuid must sit right after a `/u/` segment so an arbitrary string that
// merely contains a uuid substring isn't mistaken for a profile link.
final RegExp _urlUuidRe =
    RegExp('/u/($_uuid)(?:[/?#]|\$)', caseSensitive: false);

/// Returns the lowercased profile uuid if [input] is a bare uuid or a
/// `/u/<uuid>` profile URL/path, else null.
String? extractProfileId(String input) {
  final term = input.trim();
  if (term.isEmpty) return null;
  if (_bareUuidRe.hasMatch(term)) return term.toLowerCase();
  final inUrl = _urlUuidRe.firstMatch(term);
  if (inUrl != null) return inUrl.group(1)!.toLowerCase();
  return null;
}
