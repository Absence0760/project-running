import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// Mirror of `apps/web/src/lib/gym/exercise_catalogue.test.ts`, case for case,
/// plus two cases the web half cannot express — see the last two tests.
///
/// Mutation-tested against the rule it describes: dropping the `author_id`
/// precedence (keeping the first row under a key) fails the two shadow cases,
/// and keeping the LAST row instead fails whichever of them the fetch order
/// contradicts.
void main() {
  final epoch = DateTime.utc(2026, 1, 1);

  ExerciseRow row(String name, String nameKey, {String? authorId, String? id}) =>
      ExerciseRow(
        id: id ?? '$name/${authorId ?? 'global'}',
        authorId: authorId,
        name: name,
        nameKey: nameKey,
        category: 'other',
        modality: 'weight_reps',
        lastModifiedAt: epoch,
        createdAt: epoch,
      );

  // The stored `name_key` a seeded global carries is what the trigger stamped
  // from its own name, so the fixtures spell it out rather than fold it: this
  // package cannot reach the fold, and reading the stored value instead of
  // re-deriving it is the point of the module.
  ExerciseRow global(String name, [String? nameKey]) =>
      row(name, nameKey ?? name.toLowerCase());

  ExerciseRow custom(String name, String nameKey, {String? id}) =>
      row(name, nameKey, authorId: 'me', id: id);

  // The reducer is generic over its entry type because the read is not the only
  // list it reduces; this binds it to the row class the read hands it.
  List<ExerciseRow> dedupe(Iterable<ExerciseRow> rows) => dedupeShadowedExercises(
        rows,
        nameKey: (r) => r.nameKey,
        authorId: (r) => r.authorId,
      );

  test('a catalogue with no shadow is returned unchanged', () {
    final rows = [
      global('Back Squat'),
      global('Bench Press'),
      custom('Zercher Squat', 'zercher squat'),
    ];
    expect(dedupe(rows), rows);
  });

  test("the owner's custom wins over the global it shadows, whichever came first",
      () {
    final g = global('Bench Press');
    final c = custom('Bench Press', 'bench press');
    expect(dedupe([g, c]), [c]);
    expect(dedupe([c, g]), [c]);
  });

  test('the surviving row keeps the position of the first row under its key', () {
    // The read orders by (name, id) before this runs, so a dedupe that appended
    // the winner would move a shadowed exercise to the end of an ordered list.
    final rows = [
      global('Ab Wheel'),
      global('Bench Press'),
      custom('Bench Press', 'bench press'),
      global('Curl'),
    ];
    expect(
      dedupe(rows).map((e) => e.name),
      ['Ab Wheel', 'Bench Press', 'Curl'],
    );
    expect(dedupe(rows)[1].authorId, 'me');
  });

  test('the key is the stored exercise key, not the display spelling', () {
    // U+00A0 is in the shared whitespace class the key collapses, so the server
    // stamped these two rows with one key — they bind to the same PRs and the
    // same routine rows. Deduping on the display spelling would leave both, and
    // the picker would then file them in two different places in its list,
    // because `compareFoldedNames` does not collapse that character.
    final g = global('Bench Press');
    final c = custom('Bench Press', 'bench press');
    expect(dedupe([g, c]), [c]);
  });

  test('a case-only difference is one exercise too', () {
    final g = global('Bench Press');
    final c = custom('bench press', 'bench press');
    expect(dedupe([g, c]), [c]);
  });

  test('two globals under one key cannot both survive', () {
    // The partial unique forbids this pair, so it is unreachable from the
    // database — pinned so the reducer is total rather than only correct on the
    // shapes the schema currently allows.
    final a = global('Bench Press', 'bench press');
    final b = global('bench  press', 'bench press');
    expect(dedupe([a, b]), [a]);
  });

  test('an empty catalogue is empty, not an error', () {
    expect(dedupe(const []), isEmpty);
  });

  test('the input list is not mutated', () {
    final rows = [global('Bench Press'), custom('Bench Press', 'bench press')];
    final before = rows.map((e) => e.id).toList();
    dedupe(rows);
    expect(rows.map((e) => e.id).toList(), before);
  });

  test('two rows sharing a display name but not a stored key both survive', () {
    // The case the web half cannot express, and the reason this one reads
    // `name_key` instead of folding `name`. Regenerating the frozen fold table
    // is a MIGRATION (§ 1176), so a row stamped before the last regeneration
    // can carry a key the current table would not produce. The two partial
    // uniques are enforced on the STORED key, so a pair the index considers
    // distinct is distinct here too — where a client re-derivation would
    // collapse them and drop a row the database is still serving.
    final old = global('Bench Press', 'bench press');
    final fresh = custom('Bench Press', 'bench press ');
    expect(dedupe([old, fresh]), [old, fresh]);
  });

  test('the same rule reduces a list a surface assembled itself', () {
    // The composer merges this session's created customs onto the catalogue
    // prop and must resolve a shadow the read could not have seen: the author's
    // partial unique cannot see a row whose `author_id` is null, so creating a
    // custom under a seeded global's name succeeds and the merge holds both.
    // Its entries are records, which cannot implement an interface — the
    // reducer is generic over accessors for exactly that reason, so the surface
    // reduces through the same implementation rather than a second copy of the
    // rule (its old `id` test could not see a shadow at all).
    const seeded = (id: 'g1', nameKey: 'bench press', authorId: null);
    const mine = (id: 'c1', nameKey: 'bench press', authorId: 'me');
    const other = (id: 'g2', nameKey: 'deadlift', authorId: null);
    expect(
      dedupeShadowedExercises(
        const [seeded, other, mine],
        nameKey: (e) => e.nameKey,
        authorId: (e) => e.authorId,
      ),
      [mine, other],
    );
  });
}
