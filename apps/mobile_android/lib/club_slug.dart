/// The public club slug, derived from the club's name.
///
/// Dart twin of `apps/web/src/lib/social/club_slug.ts` — keep the two in
/// lockstep; the `shared-library-syncer` agent watches the pair.
///
/// One derivation for both clients, because the answer is PERSISTED: it is
/// written to `clubs.slug` at create time and is thereafter the club's public
/// URL. Until this module existed the derivation was written twice — here as
/// `_slugify` inside the club form sheet and again in web's `core/data.ts` —
/// as "lower-case, then `[^a-z0-9]+` to `-`", which reads as one expression
/// and is not one function. Dart's `toLowerCase` and JS's disagree at 466 code
/// points (decisions § 854), and the one of them reachable in Latin text is
/// U+0130: JS emits `i` + a combining dot, which the strip then turns into a
/// separator, so a club named `İzmir` became `izmir` on the phone and `i-zmir`
/// on the web — a different permanent URL for the same name depending on which
/// client happened to create it (§ 1251).
///
/// The fold is `catalogue_browse`'s generated accent-plus-case table rather
/// than either runtime's own lower-case, so what the slug answers is decided
/// by data committed beside it instead of by the host's Unicode version. It
/// also makes the slug do what a slug is for: `Zürich Runners` reaches
/// `zurich-runners` instead of `z-rich-runners`, because a stripped diacritic
/// leaves the base letter rather than a hyphen. Letters with no canonical
/// decomposition (`ß`, `ø`, `đ`) are deliberately NOT transliterated — the
/// fold refuses to invent equivalences Unicode does not have — so they still
/// strip.
///
/// Pure module — no Flutter, no Supabase, no localisation.
library;

import 'catalogue_browse.dart';

/// Cap on the derived slug. `clubs.slug` is `text unique not null` with no
/// CHECK, so nothing server-side enforced this and the two rails disagreed:
/// the web capped at 48 and the phone did not, which meant a long club name
/// got a 48-character URL from one client and an unbounded one from the other.
const int kClubSlugMaxLen = 48;

final RegExp _nonSlug = RegExp(r'[^a-z0-9]+');
final RegExp _edgeHyphen = RegExp(r'^-|-$');

/// [name] as a slug, or the empty string when the name carries no character
/// that survives the fold. Empty is a real answer both callers act on: the
/// phone refuses the save and says the name has no usable characters, the web
/// substitutes a literal `club`.
String clubSlug(String name) {
  final stripped =
      fold(name).replaceAll(_nonSlug, '-').replaceAll(_edgeHyphen, '');
  final capped = stripped.length <= kClubSlugMaxLen
      ? stripped
      : stripped.substring(0, kClubSlugMaxLen);
  // The cap can land mid-separator, and a slug ending in a hyphen is the one
  // shape the strip above exists to prevent.
  return capped.endsWith('-')
      ? capped.substring(0, capped.length - 1)
      : capped;
}
