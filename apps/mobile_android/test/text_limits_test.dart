import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/text_limits.dart';

/// The caps in `text_limits.dart` are only useful if they are the SAME numbers
/// the database enforces, so the guard reads them out of the migration rather
/// than restating them. Mirrors `apps/web/src/lib/core/text_limits.test.ts`.
const _migration = 'apps/backend/supabase/migrations/'
    '20270502_001_club_and_profile_text_caps.sql';

File _migrationFile() {
  // The suite runs from `apps/mobile_android` on Android and
  // `apps/mobile_ios` on the twin, so walk up to the repo root.
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/$_migration');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('could not locate $_migration from ${Directory.current.path}');
}

Map<String, int> _capsFromMigration() {
  final sql = _migrationFile().readAsStringSync();
  final re = RegExp(
    r'add\s+constraint\s+(\w+)\s+check\s*\([^;]*?char_length\([^)]*\)\s*<=\s*(\d+)',
    caseSensitive: false,
  );
  return {
    for (final m in re.allMatches(sql))
      m.group(1)!: int.parse(m.group(2)!),
  };
}

void main() {
  group('text limits vs the database CHECK constraints', () {
    final caps = _capsFromMigration();

    test('parsed a non-empty set of caps out of the migration', () {
      // Without this the per-key loop would pass over nothing if the pattern
      // ever stopped matching (decisions § 534).
      expect(caps.length, kTextLimitConstraints.length);
    });

    kTextLimitConstraints.forEach((constraint, cap) {
      test('$constraint matches the client cap $cap', () {
        expect(caps[constraint], cap);
      });
    });

    test('the migration emits a VALIDATE for every constraint it adds', () {
      final sql = _migrationFile().readAsStringSync();
      for (final constraint in kTextLimitConstraints.keys) {
        expect(sql, contains('validate constraint $constraint'));
      }
    });
  });
}
