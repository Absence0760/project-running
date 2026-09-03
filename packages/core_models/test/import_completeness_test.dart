import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// Mirror of `apps/web/src/lib/integrations/import_completeness.test.ts`,
/// case for case.
void main() {
  test('a body this build cannot read is partial, never complete', () {
    for (final body in <Object?>[null, 'ok', 42, <Object?>[], {'imported': 3}]) {
      expect(parseImportCompleteness(body).complete, isFalse,
          reason: '$body');
    }
  });

  test('only an explicit true claims the import was whole', () {
    expect(parseImportCompleteness({'complete': true}).complete, isTrue);
    for (final v in <Object?>[false, 'true', 1, null]) {
      expect(parseImportCompleteness({'complete': v}).complete, isFalse,
          reason: '$v');
    }
  });

  test('an embedded error forces partial beside a complete flag', () {
    expect(
      parseImportCompleteness({'complete': true, 'error': 'upstream 502'})
          .complete,
      isFalse,
    );
    // A blank error is not an error.
    expect(
      parseImportCompleteness({'complete': true, 'error': '  '}).complete,
      isTrue,
    );
  });

  test('counts are non-negative integers or zero', () {
    final r =
        parseImportCompleteness({'imported': 12, 'skipped': 3, 'complete': true});
    expect(r.imported, 12);
    expect(r.skipped, 3);
    for (final bad in <Object?>[-1, 1.5, '4', null, double.nan, double.infinity]) {
      expect(parseImportCompleteness({'imported': bad}).imported, 0,
          reason: '$bad');
    }
  });

  test('total is carried when the function sent one', () {
    expect(
      parseImportCompleteness({'imported': 12, 'skipped': 8, 'total': 60}).total,
      60,
    );
    // Absent means unknown, not zero.
    expect(parseImportCompleteness({'imported': 12}).total, isNull);
    for (final bad in <Object?>[-1, 2.5, '60', double.nan, double.infinity]) {
      expect(parseImportCompleteness({'total': bad}).total, isNull,
          reason: '$bad');
    }
  });

  test('a total below what was already processed is no total at all', () {
    expect(
      parseImportCompleteness({'imported': 12, 'skipped': 0, 'total': 5}).total,
      isNull,
    );
    expect(
      parseImportCompleteness({'imported': 12, 'skipped': 3, 'total': 15}).total,
      15,
    );
    expect(
      parseImportCompleteness({'imported': 12, 'skipped': 3, 'total': 14}).total,
      isNull,
    );
  });

  // The primitives this library exports are the ones `strava_sync_result.dart`
  // grades its own counts with. A copy there would drift silently — nothing
  // compares two libraries on the same platform — so this pins that the sync
  // parser still reads them from here rather than having grown its own.
  test('the strava sync parser composes on these primitives, it does not copy them',
      () {
    final src = File('lib/src/strava_sync_result.dart').readAsStringSync();
    expect(src, contains("import 'import_completeness.dart';"),
        reason: 'strava_sync_result.dart no longer imports the shared '
            'count/text primitives');
    expect(RegExp(r'^(int _count|String\? _text)\(', multiLine: true).hasMatch(src),
        isFalse,
        reason: 'strava_sync_result.dart has grown a private copy of a '
            'primitive this library owns');
  });
}
