import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/column_limits.dart';
import '../lib/preferences.dart' show WeightFormat, WeightUnit;

/// Mirrors `apps/web/src/lib/core/column_limits.test.ts`. The bound-vs-CHECK
/// comparison itself lives in `scripts/check_shared_constants.mjs`, which
/// replays the migrations; this suite pins the shape and the source guard a
/// Dart map needs and a typed TS record gets for free.
void main() {
  group('column limits', () {
    test('every key names a table and a column', () {
      // The key IS the locator the migration-replaying guard resolves, so a
      // key that is not `<table>.<column>` is a bound nothing can check.
      for (final key in kColumnLimits.keys) {
        expect(RegExp(r'^[a-z_]+\.[a-z_]+$').hasMatch(key), isTrue,
            reason: key);
      }
    });

    test('every value limit is a non-empty inclusive range', () {
      for (final entry in kColumnLimits.entries) {
        if (entry.value.isLength) continue;
        expect(entry.value.min!, lessThan(entry.value.max), reason: entry.key);
      }
    });

    test('every length limit is a positive integer', () {
      for (final entry in kColumnLimits.entries) {
        if (!entry.value.isLength) continue;
        expect(entry.value.max, isA<int>(), reason: entry.key);
        expect(entry.value.max, greaterThan(0), reason: entry.key);
      }
    });

    test('the accessors refuse the other kind, and an unknown key', () {
      expect(() => columnLength('body_metrics.weight_kg'), throwsArgumentError);
      expect(() => columnMin('club_posts.body'), throwsArgumentError);
      expect(() => columnMax('club_posts.body'), throwsArgumentError);
      expect(() => columnLength('no_such.column'), throwsArgumentError);
    });

    test('withinColumnLimit is inclusive at both ends', () {
      const key = 'body_metrics.weight_kg';
      expect(withinColumnLimit(key, columnMin(key).toDouble()), isTrue);
      expect(withinColumnLimit(key, columnMax(key).toDouble()), isTrue);
      expect(withinColumnLimit(key, columnMin(key) - 0.01), isFalse);
      expect(withinColumnLimit(key, columnMax(key) + 0.01), isFalse);
    });

    test('withinColumnLimit: a non-finite value is outside every range', () {
      for (final entry in kColumnLimits.entries) {
        if (entry.value.isLength) continue;
        expect(withinColumnLimit(entry.key, double.nan), isFalse,
            reason: entry.key);
        expect(withinColumnLimit(entry.key, double.infinity), isFalse,
            reason: entry.key);
        expect(withinColumnLimit(entry.key, double.negativeInfinity), isFalse,
            reason: entry.key);
      }
    });

    test('every key any source file asks for is in the map', () {
      // Dart resolves the key at run time where TypeScript resolves
      // `ColumnLimitKey` at compile time, so a typo'd key is a crash on the
      // screen that carries the field rather than a build failure. This is
      // that check.
      final lib = Directory('${Directory.current.path}/lib');
      final asked = <String>{};
      for (final f in lib.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        for (final m in RegExp(
                r"""\b(?:columnMin|columnMax|columnLength|withinColumnLimit|boundsIn)\(\s*'([a-z_]+\.[a-z_]+)'""")
            .allMatches(src)) {
          asked.add(m.group(1)!);
        }
      }
      expect(asked, isNotEmpty,
          reason: 'no call site found — the pattern stopped matching');
      for (final key in asked) {
        expect(kColumnLimits.containsKey(key), isTrue, reason: key);
      }
    });
  });

  group('WeightFormat.boundsIn', () {
    test('kg is the stored bound unchanged', () {
      final b = WeightFormat.boundsIn('body_metrics.weight_kg', WeightUnit.kg);
      expect(b.min, columnMin('body_metrics.weight_kg'));
      expect(b.max, columnMax('body_metrics.weight_kg'));
    });

    test('the lbs range converts back INSIDE the kg range', () {
      // The whole point of rounding the floor up and the ceiling down: every
      // value the displayed range admits must survive the real kg gate, or
      // the field advertises a bound its own validator refuses.
      final b = WeightFormat.boundsIn('body_metrics.weight_kg', WeightUnit.lbs);
      expect(
          withinColumnLimit('body_metrics.weight_kg',
              WeightFormat.toKg(b.min, WeightUnit.lbs)),
          isTrue);
      expect(
          withinColumnLimit('body_metrics.weight_kg',
              WeightFormat.toKg(b.max, WeightUnit.lbs)),
          isTrue);
      // The failure this pins is the floor: 44.0 lb is 19.96 kg, which the
      // gate refuses.
      expect(
          withinColumnLimit(
              'body_metrics.weight_kg', WeightFormat.toKg(44, WeightUnit.lbs)),
          isFalse);
      expect(b.min, greaterThan(44));
    });
  });
}
