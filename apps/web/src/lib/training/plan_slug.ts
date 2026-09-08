import { fold } from '../segments/catalogue_browse';

/** What a plan with no usable name exports as. */
export const PLAN_SLUG_FALLBACK = 'plan';

/**
 * The filename a plan's Markdown / JSON export downloads as, derived from the
 * plan's name.
 *
 * Folded through `catalogue_browse`'s table rather than `toLowerCase`, for the
 * reason `clubSlug` folds: JS lower-cases U+0130 to `i` plus a combining dot,
 * and the strip below turns that dot into a SEPARATOR — so a plan named
 * `İstanbul Marathon` downloaded as `i-stanbul-marathon.md` (decisions § 1251,
 * § 1398). The fold also leaves the base letter where a diacritic was, so
 * `Champs-Élysées 10K` reaches `champs-elysees-10k` rather than
 * `champs-lys-es-10k`.
 *
 * A letter with no canonical decomposition — `ß`, `ø`, `đ` — is deliberately
 * NOT transliterated, the same refusal `clubSlug` makes: folding one would
 * invent an equivalence Unicode does not have, so it strips like any other
 * unmapped character.
 *
 * Lives here rather than inside `/plans/[id]/+page.svelte` because a `.svelte`
 * file is not compilable by the `tsx --test` suite, which is the whole of
 * § 1278's structural gap and left the § 1398 fix with nothing asserting it.
 */
export function planSlug(name: string | null | undefined): string {
	const slug = fold(name ?? '')
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-|-$/g, '');
	return slug || PLAN_SLUG_FALLBACK;
}
