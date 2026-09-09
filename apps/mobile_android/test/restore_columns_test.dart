import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/backup.dart';
import '../lib/restore_columns.dart';

/// The allowlists are only useful if they are the SAME column sets the schema
/// has, so the coverage half reads them out of the generated row classes
/// rather than restating them. That is what makes a column a migration ADDS
/// fail here instead of being silently discarded off every archive that
/// carries it — the job `satisfies Record<keyof Insertable<T>, true>` does on
/// the web side, which Dart has no structural analogue for.
const _generated =
    'packages/core_models/lib/src/generated/db_rows.dart';
const _backup = 'apps/mobile_android/lib/backup.dart';

File _repoFile(String path) {
  // The suite runs from `apps/mobile_android` on Android and
  // `apps/mobile_ios` on the twin, so walk up to the repo root.
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/$path');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('could not locate $path from ${Directory.current.path}');
}

Set<String> _generatedColumns(String className) {
  final src = _repoFile(_generated).readAsStringSync();
  final start = src.indexOf('class $className {');
  expect(start, greaterThanOrEqualTo(0),
      reason: '$className is gone from $_generated — renamed?');
  final end = src.indexOf('\n\n', start);
  final body = src.substring(start, end);
  final names = RegExp(r"static const String col\w+ = '([^']+)';")
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();
  expect(names, isNotEmpty,
      reason: 'parsed no columns off $className — generator output changed?');
  return names;
}

void main() {
  group('keepKnownColumns', () {
    test('drops a name this schema has no home for and keeps the rest', () {
      // `runs.kind` was dropped by 20261206_001. An archive written before it
      // carries the key, and PostgREST refuses the WHOLE row for it.
      final kept = keepKnownColumns(
        <String, dynamic>{
          'id': 'r1',
          'kind': 'run',
          'distance_m': 5000,
        },
        kRunRestoreColumns,
      );
      expect(kept.row, <String, dynamic>{'id': 'r1', 'distance_m': 5000});
      expect(kept.dropped, <String>['kind']);
    });

    test('a null value on a known column is kept, not read as absent', () {
      final kept = keepKnownColumns(
        <String, dynamic>{'id': 'r1', 'route_id': null},
        kRunRestoreColumns,
      );
      expect(kept.row.containsKey('route_id'), isTrue);
      expect(kept.row['route_id'], isNull);
      expect(kept.dropped, isEmpty);
    });

    test('a row of nothing but unknown names lands nothing and reports all', () {
      final kept = keepKnownColumns(
        <String, dynamic>{'kind': 'run', 'legacy_pace': 300},
        kRunRestoreColumns,
      );
      expect(kept.row, isEmpty);
      expect(kept.dropped, <String>['kind', 'legacy_pace']);
    });
  });

  group('the allowlists are the schema', () {
    test('runs', () {
      expect(kRunRestoreColumns, _generatedColumns('RunRow'));
    });
    test('routes', () {
      expect(kRouteRestoreColumns, _generatedColumns('RouteRow'));
    });
    test('user_profiles', () {
      expect(kProfileRestoreColumns, _generatedColumns('UserProfileRow'));
    });
  });

  group('noteDroppedColumns', () {
    test('one sorted warning per section, never one per row', () {
      final result = RestoreResult();
      BackupService.noteDroppedColumns(
        'runs',
        <String>['legacy_pace', 'kind'],
        result,
      );
      expect(result.warnings, hasLength(1));
      expect(
        result.warnings.single,
        'runs: dropped kind, legacy_pace — not columns of this schema',
      );
    });

    test('nothing dropped says nothing', () {
      final result = RestoreResult();
      BackupService.noteDroppedColumns('runs', <String>[], result);
      expect(result.warnings, isEmpty);
    });
  });

  test('every online-restore upsert is handed a filtered row', () {
    // The helper being right is not the fix; the three call sites using it is.
    // Each upsert in the online path must send what `keepKnownColumns`
    // returned, or an archive column this schema has no home for still fails
    // the whole row — after that run's track blob has reached Storage.
    final src = _repoFile(_backup).readAsStringSync();
    final start = src.indexOf('    // Profile first.');
    final end = src.indexOf('    // Gym + food hydrate');
    expect(start, greaterThanOrEqualTo(0),
        reason: 'online-restore region markers moved — the guard reads nothing');
    expect(end, greaterThan(start));
    final region = src.substring(start, end);

    final calls = RegExp(r'(?:upsertRunRowRaw|upsert)\(\s*([A-Za-z_][\w.]*)\s*\)')
        .allMatches(region)
        .map((m) => m.group(1)!)
        .toList();
    expect(calls, hasLength(3),
        reason: 'expected the profile / run / route upserts, found $calls');
    for (final arg in calls) {
      expect(arg, 'known.row',
          reason: 'an online-restore upsert sends $arg rather than the row '
              'keepKnownColumns filtered');
    }
  });
}
