import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/text_limits.dart';

/// The caps in `text_limits.dart` are only useful if they are the SAME numbers
/// the database enforces, so the guard reads them out of the migrations rather
/// than restating them. The whole directory, not one file: the registered caps
/// are added by three different migrations, and a guard pointed at one of them
/// can only ever certify the caps that migration happened to contain.
/// Mirrors `apps/web/src/lib/core/text_limits.test.ts`.
const _migrationsDir = 'apps/backend/supabase/migrations';

Directory _migrations() {
  // The suite runs from `apps/mobile_android` on Android and
  // `apps/mobile_ios` on the twin, so walk up to the repo root.
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final d = Directory('${dir.path}/$_migrationsDir');
    if (d.existsSync()) return d;
    dir = dir.parent;
  }
  fail('could not locate $_migrationsDir from ${Directory.current.path}');
}

String _migrationsSql() {
  final files = _migrations()
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files.map((f) => f.readAsStringSync()).join('\n');
}

Map<String, int> _capsFromMigrations() {
  final sql = _migrationsSql();
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
    final caps = _capsFromMigrations();

    test('parsed a cap out of the migrations for every registered constraint',
        () {
      // Without this the per-key loop would pass over nothing if the pattern
      // ever stopped matching (decisions § 534).
      for (final constraint in kTextLimitConstraints.keys) {
        expect(caps, contains(constraint));
      }
    });

    kTextLimitConstraints.forEach((constraint, cap) {
      test('$constraint matches the client cap $cap', () {
        expect(caps[constraint], cap);
      });
    });

    test('the migrations emit a VALIDATE for every registered constraint', () {
      final sql = _migrationsSql();
      for (final constraint in kTextLimitConstraints.keys) {
        expect(sql, contains('validate constraint $constraint'));
      }
    });
  });
}
