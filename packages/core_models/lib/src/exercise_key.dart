/// The exercise grouping KEY — one derivation, in the one package every Dart
/// consumer can reach.
///
/// Dart half of `apps/web/src/lib/gym/gym_prs.ts`'s `normaliseExerciseName` /
/// `namesAnExercise` / `EXERCISE_WHITESPACE`, and the third rail is the SQL
/// `public.normalise_exercise_name` (migration 20270623000001);
/// `scripts/check_shared_constants.mjs` compares all three. The rest of that
/// pair — the PR metrics — stays in `apps/mobile_android/lib/gym_prs.dart`,
/// which re-exports this file so every existing caller keeps its one import.
///
/// It lives HERE rather than under `apps/mobile_android/lib/` because
/// `packages/api_client` decides the same question and could not reach the
/// class: `createCustomExercise` tested blankness with `name.trim()`, which is
/// this rail's answer only by a coincidence of Dart's own whitespace set
/// ([kExerciseWhitespace] is `trim()`'s set verbatim, so a name folds to the
/// empty key exactly when `trim()` empties it — measured in both directions
/// over every assignable code point). A rule stated by a runtime coincidence
/// is a rule that stops holding the moment either side of it moves, and the
/// coincidence was the only thing keeping a name whose key is `''` off two
/// columns whose CHECK is `length(...) between 1 and 120` (decisions § 1367).
///
/// Moving it also collapses the two Dart copies of the frozen fold table into
/// one: `core_models` is not twinned, so the iOS app consumes this package
/// rather than carrying a mirror the generator had to keep in step.
///
/// Pure — no Supabase, no Flutter.
library;

import 'exercise_fold_table.dart';

/// The whitespace class every rail folds, spelled out by code point rather
/// than left to a runtime's default.
///
/// This value is PERSISTED as `gym_sets.exercise_key` (server-stamped),
/// `gym_routine_exercises.exercise_key` and `exercises.name_key`, so all three
/// rails must produce an identical key or one exercise buckets as two: the
/// local PR tracker says PR where `gym_workout_summaries.is_pr` says no, and
/// `gym_exercise_set_history(p_name)` returns an empty history for a lift that
/// has one.
///
/// Naming the set is what removes the dependency on each runtime's idea of
/// whitespace, and the three ideas genuinely differ. Dart's `String.trim()`
/// strips every Unicode `White_Space` code point including U+0085 (NEL) where
/// JS's `trim()` and `\s` do not. Postgres is worse than either: `btrim(text)`
/// with no second argument strips U+0020 ALONE, and `\s` is `[[:space:]]`,
/// whose membership past ASCII is decided by the database's locale provider —
/// measured on PG 17.6, the ICU provider folds U+00A0 / U+2007 / U+202F /
/// U+001C-U+001F and the libc `en_US.utf8` provider folds none of them. A
/// persisted key cannot be a function of the server's collation.
///
/// The class is Unicode `White_Space` plus U+FEFF, which is not White_Space but
/// is invisible and must not split a bucket. U+001C-U+001F are deliberately
/// absent: they are control characters, not spaces, and Postgres folding them
/// under one provider was a divergence to close, not a rule to copy. The SQL
/// mirror is `public.normalise_exercise_name` (migration 20270623000001);
/// `scripts/check_shared_constants.mjs` compares all three. decisions § 790.
final RegExp kExerciseWhitespace = RegExp(
  '[\\u0009-\\u000d\\u0020\\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff]+',
);

/// The one case fold applied around the table, spelled out by code point for
/// the same reason [kExerciseWhitespace] is.
///
/// U+03C2 folds to U+03C3 AFTER the table. Final sigma is a CONTEXT, not a
/// case: ICU and JS produce it when lowercasing a word-final capital sigma and
/// this rail and libc never do, and no per-code-point table can express either
/// behaviour. The table always answers U+03C3, so this collapses a lifter's own
/// typed final sigma onto it and an all-caps Greek spelling meets its
/// lower-case one on all three rails.
const List<String> kExerciseCasePostFold = ['\u03c2', '\u03c3'];

/// Normalise a free-text exercise name for grouping: trimmed, lower-cased,
/// internal whitespace collapsed.
///
/// This is the KEY, not the display order. `catalogue_browse`'s `fold` answers
/// the other question — where a reader looks for the name — and § 1334 records
/// that keeping the two apart is deliberate. Where they part company is
/// measured rather than left to be rediscovered: of the 26 code points
/// [kExerciseWhitespace] collapses onto U+0020, the display fold leaves **25**
/// distinct from it, because that fold is built on CANONICAL decomposition and
/// the only whitespace carrying one is U+2000 / U+2001 (to U+2002 / U+2003,
/// still not a plain space). So two names that share ONE key — `Bench Press`
/// and `Bench` + U+00A0 + `Press`, which bind to the same PRs, the same routine
/// rows and the same grouping — sort not merely apart but on opposite sides of
/// every other name beginning `Bench`.
///
/// **Which side is not fixed**, and § 1496 read it as fixed: 20 of the 25 sort
/// ABOVE U+0020 and the five C0 members (U+0009-U+000D) sort BELOW it, so a
/// shadowed spelling files after the whole `Bench …` block or before all of it
/// depending on which member it carries. A surface that groups such a pair
/// therefore cannot reach the second row by scanning in one direction from the
/// first, whichever direction it picks. `gym_prs_test.dart` derives the split
/// from the class rather than asserting it (decisions § 1496, § 1565).
String normaliseExerciseName(String name) =>
    _foldExerciseCase(name.replaceAll(kExerciseWhitespace, ' ').trim())
        .replaceAll(kExerciseCasePostFold[0], kExerciseCasePostFold[1])
        .replaceAll(RegExp(r' +'), ' ');

/// Lower-case through the FROZEN table rather than through [String.toLowerCase].
///
/// The runtime's own table is the last thing about this key that still moved
/// with the runtime, and this rail carried the worst of it: Dart's
/// `toLowerCase()` is Unicode SIMPLE case mapping from an older revision, and
/// measured over every assignable code point it left 465 code points alone that
/// web folded and 410 that the server folded. The key is PERSISTED, so each of
/// those was a name this rail wrote to `gym_routine_exercises.exercise_key` or
/// `exercises.name_key` under a key nothing else agreed on (decisions § 1175).
/// The 23514 that used to accompany it is gone: since 20270711000001 both
/// columns are stamped by a BEFORE trigger and a client value is CORRECTED
/// rather than refused, so a stale table no longer fails the save -- it splits
/// the bucket silently, which is why the table has to stay frozen. The table is
/// generated by `scripts/gen_exercise_fold_table.mjs`; the mirrors are
/// `apps/web/src/lib/gym/exercise_fold_table.ts` and the `translate()` inside
/// `public.exercise_fold_case`.
///
/// Walking [String.runes] is load-bearing: 307 of the 1,488 entries are outside
/// the BMP, and a code-unit walk would fold each half of a surrogate pair
/// separately and match nothing.
String _foldExerciseCase(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    out.writeCharCode(_exerciseFold[rune] ?? rune);
  }
  return out.toString();
}

final Map<int, int> _exerciseFold = <int, int>{
  for (var i = 0; i < kExerciseFoldKeys.length; i++)
    kExerciseFoldKeys[i]: kExerciseFoldValues[i],
};

/// Does this free-text spelling name an exercise at all?
///
/// The one blankness test every surface that PERSISTS an exercise name must
/// make, and the companion to [sameExerciseName]: identity and emptiness are
/// both properties of the KEY, and a surface that reads either off the display
/// spelling disagrees with every surface that reads it off the key.
///
/// This rail answered correctly before it named the test, and that is the
/// reason it now names it. `String.trim()` strips the whole Unicode
/// `White_Space` set plus U+FEFF, which is [kExerciseWhitespace] exactly — so
/// `name.trim().isEmpty` was right by coincidence of the runtime, the precise
/// dependency the spelled-out class exists to remove. The web twin's `trim()`
/// is a narrower set that leaves U+0085 (NEL) in place, so the same guard there
/// SAVED a set whose server-stamped `exercise_key` is `''` and passed a name to
/// two columns whose key CHECK is `length(...) between 1 and 120`
/// (decisions 1367). One name for one rule, on both rails.
bool namesAnExercise(String? name) => normaliseExerciseName(name ?? '') != '';
