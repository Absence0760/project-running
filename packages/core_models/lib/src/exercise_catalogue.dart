/// What the exercise catalogue IS, once the two partial uniques are taken into
/// account.
///
/// Dart twin of `apps/web/src/lib/gym/exercise_catalogue.ts` — keep the
/// precedence rule, the ordering guarantee and the test counts in lockstep.
///
/// `exercises` has two unique indexes on `name_key` and both are PARTIAL —
/// `exercises_global_name_key` on `(name_key) where author_id is null`,
/// `exercises_author_name_key` on `(author_id, name_key) where author_id is not
/// null` (migration 20270222_001). The migration states the intent outright:
/// "a user may shadow a global name with a custom one". So a read can
/// legitimately return TWO rows carrying one display name and one folded key,
/// and every consumer downstream treats a name as identifying one exercise:
/// the composer binds a typed name to ONE `exercises.id` by walking the list,
/// the picker's exact-match test can hold two rows, and a surface that later
/// aggregates by `exercise_id` would read one lift as two.
///
/// The precedence rule nothing in the tree stated: **the owner's row wins.** A
/// shadow exists only because the user deliberately created a custom under a
/// name the catalogue already had, which is a personal override by construction
/// — so resolving it to the seeded global is resolving it the one way the user
/// did not ask for. Applied at the READ, so no consumer has to know the rule
/// and none can disagree with another about it.
///
/// RLS is what makes "the owner's row" cheap to recognise: the read policy
/// returns seeded globals plus the caller's OWN customs and nothing else, so
/// any row with a non-null `author_id` in a result set is by construction the
/// caller's. No user id is needed and none is taken.
///
/// **The key is the row's own `name_key`, not a re-derivation of it**, and that
/// is the one deliberate difference from the web half, which folds `name`
/// through `normaliseExerciseName`. Two reasons, and the second is the load
/// bearing one. `name_key` is what the two partial uniques are enforced ON, so
/// it is by definition what makes two rows a shadow pair; and it is stamped by
/// the `exercises_stamp_name_key` trigger at write time (20270711000001), where
/// a client fold is this build's answer to the same question. The two agree
/// only while the frozen fold table matches the server's, which is exactly the
/// property § 1176 says moves by MIGRATION rather than by codegen — so a row
/// stamped before the last regeneration can carry a key the current table would
/// not produce, and grouping by the re-derivation would then split a pair the
/// index considers one. Reading the stored value cannot drift from the index by
/// construction. It also keeps this package clear of a fourth copy of the
/// 1,488-entry fold table, which `packages/` cannot reach at all.
///
/// Pure — no Supabase, no Flutter.
library;

import 'generated/db_rows.dart';

/// One row per stored `name_key`, the owner's custom winning over the seeded
/// global it shadows. Input order is otherwise preserved, and the surviving row
/// keeps the position of the FIRST row under its key — so a caller that ordered
/// the list before calling still holds an ordered list afterwards.
///
/// This is also what removes the ordering hazard a folded-name comparator has:
/// the exercise key collapses the shared whitespace class where
/// `catalogue_browse`'s `fold` does not, so `Bench Press` and
/// `Bench<U+00A0>Press` are ONE exercise that such a comparator files in two
/// different places in the list. After the dedupe no catalogue surface holds
/// both, so the two can no longer be rendered as unrelated neighbours — and the
/// two functions keep answering the different questions § 1334 says they must.
List<ExerciseRow> dedupeShadowedExercises(List<ExerciseRow> entries) {
  final at = <String, int>{};
  final out = <ExerciseRow>[];
  for (final e in entries) {
    final seen = at[e.nameKey];
    if (seen == null) {
      at[e.nameKey] = out.length;
      out.add(e);
      continue;
    }
    // A second row under one key is a shadow, and only two shapes reach here:
    // global-then-custom and custom-then-global. Both uniques forbid a second
    // row of the SAME shape, so the incumbent is replaced exactly when it is
    // the global and the newcomer is not.
    if (out[seen].authorId == null && e.authorId != null) out[seen] = e;
  }
  return out;
}
