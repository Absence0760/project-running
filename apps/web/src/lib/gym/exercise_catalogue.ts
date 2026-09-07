/**
 * What the exercise catalogue IS, once the two partial uniques are taken into
 * account.
 *
 * `exercises` has two unique indexes on `name_key` and both are PARTIAL —
 * `exercises_global_name_key` on `(name_key) where author_id is null`,
 * `exercises_author_name_key` on `(author_id, name_key) where author_id is not
 * null` (migration 20270222_001). The migration states the intent outright:
 * "a user may shadow a global name with a custom one". So a read can legitimately
 * return TWO rows carrying one display name and one folded key, and every
 * consumer downstream treats a name as identifying one exercise:
 * `GymEditor`'s `catalogueByKey` is a Map over the list, so the LAST row under
 * a key silently wins; the picker's exact-match test can hold two rows; and a
 * surface that later aggregates by `exercise_id` would read one lift as two.
 *
 * The precedence rule nothing in the tree stated: **the owner's row wins.** A
 * shadow exists only because the user deliberately created a custom under a
 * name the catalogue already had, which is a personal override by construction
 * — so resolving it to the seeded global is resolving it the one way the user
 * did not ask for. Applied at the READ, so no consumer has to know the rule
 * and none can disagree with another about it.
 *
 * RLS is what makes "the owner's row" cheap to recognise: the read policy
 * returns seeded globals plus the caller's OWN customs and nothing else, so any
 * row with a non-null `author_id` in a result set is by construction the
 * caller's. No user id is needed and none is taken.
 *
 * There is NO Dart half yet, and that is the state to know rather than assume:
 * `ApiClient.fetchExerciseCatalogue` still returns the shadowed pair unresolved
 * and still degrades a failed read to an empty catalogue, so the phone's picker
 * can offer to create a name the catalogue already holds. Writing that half is
 * what would make this a registered parity pair — which edits `CLAUDE.md` and
 * the syncer table too — and it is filed in `followups.md`, not done here.
 *
 * Pure module — no Supabase, no runes. Entries are matched structurally, so the
 * caller's row type needs no relationship to this file.
 */

/// The two fields the precedence rule reads. `author_id` is null for a seeded
/// global and set for an owner custom; `name_key` is the STORED key, not a
/// re-derivation of it.
export interface ShadowableExercise {
	name_key: string;
	author_id: string | null;
}

/**
 * One row per folded exercise key, the owner's custom winning over the seeded
 * global it shadows. Input order is otherwise preserved, and the surviving row
 * keeps the position of the FIRST row under its key — so a caller that ordered
 * the list before calling still holds an ordered list afterwards.
 *
 * Keyed on the STORED `exercises.name_key`, which is the column both partial
 * uniques are built on — so "the database considers these one exercise" is read
 * off the database's own value rather than inferred by re-deriving it. The two
 * agree on any migrated row (`exercises_name_key_canonical` is validated, and
 * `exercises_stamp_name_key` re-stamps on every write), and they are not
 * guaranteed to agree in the window between a client carrying a regenerated
 * fold table and the migration that re-folds the column — which is exactly a
 * window in which a re-derivation splits a pair the unique index will not let
 * anyone add a third row to. The Dart half keys on the same column.
 *
 * This is also what removes the ordering hazard the picker's comparator has:
 * the key collapses the shared whitespace class where `catalogue_browse`'s
 * `fold` does not, so `Bench Press` and `Bench<U+00A0>Press` are ONE exercise
 * that a folded-name comparator files in two different places in the list.
 * After the dedupe no catalogue surface holds both, so the two can no longer be
 * rendered as unrelated neighbours — and the two functions keep answering the
 * different questions § 1334 says they must.
 *
 * Applied to every list a surface works from, not only to the read. A custom
 * created in the picker can shadow a global the CLIENT's list still carries,
 * because that list is a snapshot and the author's partial unique cannot see a
 * row whose `author_id` is null — so the insert succeeds and a merge of the two
 * holds both. Folding the created customs in through here is what stops that
 * being a second answer to which row a typed name binds to; a de-duplication by
 * `id`, which is what both editors did instead, cannot see it at all.
 */
export function dedupeShadowedExercises<E extends ShadowableExercise>(entries: readonly E[]): E[] {
	const at = new Map<string, number>();
	const out: E[] = [];
	for (const e of entries) {
		const seen = at.get(e.name_key);
		if (seen === undefined) {
			at.set(e.name_key, out.length);
			out.push(e);
			continue;
		}
		// A second row under one key is a shadow, and only two shapes reach here:
		// global-then-custom and custom-then-global. Both uniques forbid a second
		// row of the SAME shape, so the incumbent is replaced exactly when it is
		// the global and the newcomer is not.
		if (out[seen].author_id == null && e.author_id != null) out[seen] = e;
	}
	return out;
}

