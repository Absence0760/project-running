import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the fix for the local-wall-clock-into-a-`timestamptz` class.
///
/// `toIso8601String()` on a LOCAL `DateTime` emits a naive string with no `Z`
/// and no offset. PostgreSQL reads a naive literal into a `timestamptz` as
/// UTC, so the stored instant is wrong by the runner's offset — a Berlin user
/// archiving a coach thread at 23:30 has it dated the next day, and a
/// last-modified stamp that feeds newer-wins sync (`createCustomExercise`)
/// resolves conflicts by the writer's time zone rather than by who wrote last.
/// `saveRun`'s own comment has documented the mechanism the whole time.
///
/// The rule this guards: anything destined for the server is stamped
/// `DateTime.now().toUtc()`. The exceptions below are writes that never reach
/// a `timestamptz`; each is listed with its exact line so a NEW wall-clock
/// write in one of these files still fails.
void main() {
  const pattern = 'DateTime.now().toIso8601String()';

  /// `path|trimmed source line` for every permitted occurrence.
  const allowed = <String>{
    // A `date` column, not a timestamptz. "The day I retired these shoes" is
    // a local-calendar fact; converting to UTC first would retire them
    // yesterday for anyone west of Greenwich after 00:00 UTC.
    "lib/local_gear_store.dart|'retired_at': DateTime.now().toIso8601String().substring(0, 10),",
    // On-device NDJSON checkpoint stamp for the in-progress recording file.
    // Never uploaded, read back by the same device that wrote it.
    "lib/local_run_store.dart|'t': DateTime.now().toIso8601String(),",
    // metadata.in_progress_saved_at — crash-recovery recency, compared
    // against the local clock by `_isRecent` and cleared before the run is
    // finalised, so it never reaches the server.
    'lib/screens/run_screen.dart|cm.MetadataKeys.inProgressSavedAt: DateTime.now().toIso8601String(),',
    // Export filenames, not data.
    "lib/screens/settings_account_screen.dart|DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');",
  };

  Iterable<File> dartFiles(Directory d) => d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  test('no local wall-clock is written where the server reads it', () {
    final roots = <String, Directory>{'lib': Directory('lib')};
    for (final pkg in Directory('../../packages').listSync().whereType<Directory>()) {
      final lib = Directory('${pkg.path}/lib');
      if (lib.existsSync()) roots[pkg.path.split('/').last] = lib;
    }

    final found = <String>{};
    for (final entry in roots.entries) {
      for (final file in dartFiles(entry.value)) {
        final rel = entry.key == 'lib'
            ? file.path
            : 'packages/${entry.key}/${file.path.split('/lib/').last}';
        for (final line in file.readAsLinesSync()) {
          if (line.contains(pattern)) found.add('$rel|${line.trim()}');
        }
      }
    }

    expect(
      found.difference(allowed),
      isEmpty,
      reason: 'a local DateTime serialises without an offset and Postgres '
          'reads it into a timestamptz as UTC. Stamp DateTime.now().toUtc() '
          'for anything the server stores, or add the occurrence above with '
          'the reason it never reaches a timestamptz.',
    );
  });

  /// The named columns, each with the count of writes that must carry a UTC
  /// stamp. Counting rather than merely finding keeps a second, un-converted
  /// write to the same column from hiding behind a converted one — which is
  /// exactly the shape of the two mark-read paths.
  const utcStamps = <String, ({String file, int count})>{
    'NotificationRow.colReadAt':
        (file: '../../packages/api_client/lib/src/api_client.dart', count: 2),
    'ExerciseRow.colLastModifiedAt':
        (file: '../../packages/api_client/lib/src/api_client.dart', count: 1),
    "'completed_at'": (file: 'lib/training_service.dart', count: 1),
    "'skipped_at'": (file: 'lib/training_service.dart', count: 1),
  };

  group('the writes named in the round-3 bug hunt stamp UTC', () {
    utcStamps.forEach((column, spec) {
      test(column, () {
        final src = File(spec.file).readAsStringSync();
        // `archiveCoachThread` binds the stamp to a local first, so match the
        // column and the conversion within the same statement rather than
        // demanding they be adjacent.
        final stmt = RegExp(
          '${RegExp.escape(column)}[^;]*?DateTime\\.now\\(\\)\\.toUtc\\(\\)',
          dotAll: true,
        );
        final loose = RegExp(
          '${RegExp.escape(column)}[^;]*?DateTime\\.now\\(\\)',
          dotAll: true,
        );
        expect(loose.allMatches(src).length, spec.count,
            reason: 'the set of now()-stamped writes to $column changed — '
                'update the expected count deliberately');
        expect(stmt.allMatches(src).length, spec.count,
            reason: 'every now() write to $column must go through toUtc()');
      });
    });
  });

  test('archiveCoachThread stamps UTC', () {
    final src = File('../../packages/api_client/lib/src/api_client.dart')
        .readAsStringSync();
    final start = src.indexOf('Future<void> archiveCoachThread(');
    expect(start, greaterThan(-1));
    final body = src.substring(start, src.indexOf('\n  /// ', start));
    expect(body.contains('DateTime.now().toUtc().toIso8601String()'), isTrue);
  });
}
