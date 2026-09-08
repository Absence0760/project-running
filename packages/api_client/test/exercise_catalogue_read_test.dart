import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// The two properties of the catalogue read that no consumer can restore.
///
/// A source guard rather than a wire test because both failures are STATIC and
/// both succeed: a read that skips the dedupe returns a well-formed list, and a
/// read that catches its own failure returns a well-formed empty one. Neither
/// raises anything for an integration test to observe, and the harm is a
/// binding or an affordance three files away.
void main() {
  final src = File('lib/src/api_client.dart').readAsStringSync();
  final start =
      src.indexOf('Future<List<ExerciseRow>> fetchExerciseCatalogue()');
  final end = start < 0 ? -1 : src.indexOf('\n  /// ', start);
  final body = start < 0 ? '' : src.substring(start, end == -1 ? src.length : end);

  test('fetchExerciseCatalogue is where the catalogue is read', () {
    expect(body, isNotEmpty, reason: 'the method moved or was renamed');
  });

  test('the shadowed pair is resolved at the read, not at each surface', () {
    // `exercises` carries two PARTIAL uniques on `name_key`, so a user's custom
    // may shadow a seeded global under one name (migration 20270222_001) and a
    // read legitimately returns two rows for one exercise. Every consumer binds
    // a typed name to ONE `exercises.id`, so an unresolved pair leaves the
    // binding to whichever row the consumer's own map happens to keep.
    expect(
      body.contains('dedupeShadowedExercises'),
      isTrue,
      reason: 'the read must return one row per exercise — resolving the '
          'shadow per surface lets two surfaces disagree about one lift',
    );
  });

  test('a failed read is not answered as an empty catalogue', () {
    // An empty catalogue is the state in which every typed name looks free: the
    // create affordance is offered for a name the catalogue already holds,
    // which mints a shadow or 23505s against a row the client cannot see. So
    // the failure has to reach the caller as a failure.
    expect(
      RegExp(r'\btry\b|\bcatch\b|catchError').hasMatch(body),
      isFalse,
      reason: 'swallowing here erases "unavailable" for every surface at once; '
          'the caller carries the third state',
    );
  });

  test('the dedupe the read applies is the registered pair, not a local copy',
      () {
    // Reachable from this package only because the Dart half lives in
    // `core_models` — a private copy here would be a pair the syncer cannot
    // see (decisions § 1397).
    final rows = [
      ExerciseRow(
        id: 'global',
        name: 'Bench Press',
        nameKey: 'bench press',
        category: 'other',
        modality: 'weight_reps',
        lastModifiedAt: DateTime.utc(2026),
        createdAt: DateTime.utc(2026),
      ),
      ExerciseRow(
        id: 'mine',
        authorId: 'me',
        name: 'Bench Press',
        nameKey: 'bench press',
        category: 'other',
        modality: 'weight_reps',
        lastModifiedAt: DateTime.utc(2026),
        createdAt: DateTime.utc(2026),
      ),
    ];
    expect(dedupeShadowedExercises(rows).map((e) => e.id), ['mine']);
  });
}
