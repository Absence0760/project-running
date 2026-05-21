import 'package:flutter_test/flutter_test.dart';

import '../lib/training_service.dart';

/// Parity tests for the trim-and-null normalisation now applied to
/// `TrainingService.createPlan.notes`. Mirrors web's
/// `apps/web/src/lib/data.ts:createTrainingPlan`, which writes
/// `notes: input.notes?.trim() || null`.
///
/// Before this round, mobile passed `notes?.trim()` — empty-after-trim
/// landed in the DB as `""` instead of `null`. The whole row shape
/// then disagreed with web for the same user input. This pins the
/// helper that backs the fix.
void main() {
  group('TrainingService.trimToNull — web `s?.trim() || null` mirror', () {
    test('null stays null', () {
      expect(TrainingService.trimToNull(null), isNull);
    });

    test('empty string collapses to null', () {
      expect(TrainingService.trimToNull(''), isNull);
    });

    test('whitespace-only collapses to null — this is the bug fix', () {
      // Before: `notes?.trim()` produced `""` for whitespace inputs,
      // so the column had a non-null empty string. Pinning the new
      // behaviour against regression.
      expect(TrainingService.trimToNull('   \t\n  '), isNull);
    });

    test('content with surrounding whitespace is trimmed but preserved', () {
      expect(
        TrainingService.trimToNull('  Race day plan  '),
        'Race day plan',
      );
    });

    test('internal whitespace is preserved (only edges trimmed)', () {
      expect(
        TrainingService.trimToNull('  one   two  three  '),
        'one   two  three',
      );
    });

    test('single non-whitespace character round-trips intact', () {
      // Pin against an over-eager helper that might collapse short
      // values for being "essentially empty".
      expect(TrainingService.trimToNull('x'), 'x');
    });

    test('emoji-only notes round-trip intact', () {
      // A coach pasting `🔥` as their plan notes is a real flow —
      // make sure the helper doesn't drop it.
      expect(TrainingService.trimToNull('🔥'), '🔥');
    });

    test('"0" stays as "0" — the JS `|| null` truthiness trap', () {
      // Same pin as the run-photo caption helper. Web's
      // `s?.trim() || null` relies on the empty string being falsy in
      // JS — a literal "0" is truthy on web, so the Dart port must
      // also preserve it.
      expect(TrainingService.trimToNull('0'), '0');
    });
  });
}
