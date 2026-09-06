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

/// The slug a caller substitutes when the fold leaves nothing — a club named
/// entirely in Cyrillic, Greek, Hebrew, Arabic or CJK has no `[a-z0-9]` to
/// build one from, and refusing to create it is not an option either client
/// should take. It reaches `clubs.slug` and becomes a public URL, so it
/// belongs to the pair rather than being written out at each call site; the
/// create paths' collision retry is what keeps the second such club
/// distinguishable.
const String kClubSlugFallback = 'club';

/// [name] as a slug, or the empty string when the name carries no character
/// that survives the fold. Empty is a real answer, not a failure: both callers
/// substitute [kClubSlugFallback] for it.
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

/// Whether [name] names something, rather than being blank or made only of
/// marks that cannot name anything on their own.
///
/// This is the pre-flight both club create forms run before [clubSlug], and it
/// belongs to the pair because the two clients disagreeing about it means one
/// of them creates a club the other would refuse. This side tested the NAME
/// for `[\p{L}\p{N}]` while the web tested nothing beyond non-blank, so a club
/// called `!!!` was creatable there and refused here, landing under the
/// [kClubSlugFallback] slug (decisions § 1338).
///
/// It is deliberately a REFUSE-list rather than the accept-list this side used,
/// and the reason is measured. A Unicode property class is answered by each
/// runtime's own Unicode tables, exactly like `toLowerCase`: over all
/// 1,112,064 assignable scalar values, `[\p{L}\p{N}]` gives a DIFFERENT answer
/// in Dart and in Node at **4,657 code points**, and every one of them is a
/// letter the newer table knows and the older one does not — so the
/// accept-list refuses real letters on whichever platform is behind, which is
/// § 1281's bug verbatim. `[^\p{Z}\p{P}\p{S}\p{Cc}\p{Cf}]` diverges at
/// **104**, and in the opposite direction: a code point one runtime has not
/// yet assigned is in none of those categories, so it reads as nameable on
/// both. The residual 104 are newly-assigned SYMBOLS that web refuses and this
/// side accepts — the harmless direction, and only for a name made of nothing
/// else.
///
/// `\p{Cn}` (unassigned) is deliberately NOT in the list even though `\p{C}`
/// would be shorter: including it is what makes the class fail closed against
/// a letter this runtime is too old to know. `Cc` and `Cf` are named
/// individually because they are stable, long-assigned categories, so a name
/// of nothing but control or format characters is still refused.
///
/// Wider than the slug's own `[a-z0-9]` on purpose: this decides whether the
/// name is NAMING something, which every script can do, where the slug decides
/// what the URL can spell, which only ASCII can.
final RegExp _nameable = RegExp(r'[^\p{Z}\p{P}\p{S}\p{Cc}\p{Cf}]', unicode: true);

bool clubNameNamesSomething(String name) => _nameable.hasMatch(name);
