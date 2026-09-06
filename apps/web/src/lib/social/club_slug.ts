/**
 * The public club slug, derived from the club's name.
 *
 * One derivation for both clients, because the answer is PERSISTED: it is
 * written to `clubs.slug` at create time and is thereafter the club's public
 * URL. Until this module existed the derivation was written twice — here in
 * `core/data.ts` and again as `_slugify` in the phone's club form sheet — as
 * "lower-case, then `[^a-z0-9]+` to `-`", which reads as one expression and is
 * not one function. `String.prototype.toLowerCase` and Dart's `toLowerCase`
 * disagree at 466 code points (decisions § 854), and the one of them that is
 * reachable in Latin text is U+0130: JS emits `i` + a combining dot, which the
 * strip then turns into a separator, so a club named `İzmir` became `i-zmir`
 * on the web and `izmir` on the phone — a different permanent URL for the
 * same name depending on which client happened to create it (§ 1251).
 *
 * The fold is `catalogue_browse`'s generated accent-plus-case table rather
 * than either runtime's own lower-case, so what the slug answers is decided by
 * data committed beside it instead of by the host's Unicode version. It also
 * makes the slug do what a slug is for: `Zürich Runners` reaches
 * `zurich-runners` instead of `z-rich-runners`, because a stripped diacritic
 * leaves the base letter rather than a hyphen. Letters with no canonical
 * decomposition (`ß`, `ø`, `đ`) are deliberately NOT transliterated — the fold
 * refuses to invent equivalences Unicode does not have — so they still strip.
 */
import { fold } from '../segments/catalogue_browse';

/**
 * Cap on the derived slug. `clubs.slug` is `text unique not null` with no
 * CHECK, so nothing server-side enforced this and the two rails disagreed: the
 * web capped at 48 and the phone did not, which meant a long club name got a
 * 48-character URL from one client and an unbounded one from the other.
 */
export const CLUB_SLUG_MAX_LEN = 48;

/**
 * `name` as a slug, or the empty string when the name carries no character
 * that survives the fold. Empty is a real answer both callers act on: the web
 * substitutes a literal `club`, the phone refuses the save and says the name
 * has no usable characters.
 */
export function clubSlug(name: string): string {
	return (
		fold(name)
			.replace(/[^a-z0-9]+/g, '-')
			.replace(/^-|-$/g, '')
			.slice(0, CLUB_SLUG_MAX_LEN)
			// The cap can land mid-separator, and a slug ending in a hyphen is
			// the one shape the strip above exists to prevent.
			.replace(/-$/, '')
	);
}
