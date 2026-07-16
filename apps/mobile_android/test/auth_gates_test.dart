import 'package:flutter_test/flutter_test.dart';
import '../lib/auth_gates.dart';

// Mirror of the checkPasswordPair half of
// `apps/web/src/lib/core/auth_gates.test.ts` — 17 cases, one per web test.
//
// The pair check is the only thing standing between a mistyped password and
// an account its owner can never sign into, so the cases below pin the
// contract fairly hard: precedence, exactness, and the boundary.
void main() {
  group('checkPasswordPair', () {
    test('minPasswordLength is 6, matching GoTrue\'s default', () {
      // config.toml sets no minimum_password_length, so GoTrue's default of
      // 6 governs. If this constant moves, a password this helper accepts
      // gets rejected by the auth server.
      expect(minPasswordLength, 6);
    });

    test('matching passwords over the minimum → ok', () {
      expect(checkPasswordPair('correct horse', 'correct horse'), isNull);
    });

    test('matching passwords at exactly the minimum → ok (boundary is inclusive)', () {
      final at = 'a' * minPasswordLength;
      expect(checkPasswordPair(at, at), isNull);
    });

    test('matching passwords one short of the minimum → tooShort', () {
      final under = 'a' * (minPasswordLength - 1);
      expect(checkPasswordPair(under, under), PasswordPairReason.tooShort);
    });

    test('both fields empty → tooShort', () {
      // The empty pair matches, so without the length check first this would
      // sail through as ok.
      expect(checkPasswordPair('', ''), PasswordPairReason.tooShort);
    });

    test('differing passwords, both long enough → mismatch', () {
      expect(
        checkPasswordPair('longenough1', 'longenough2'),
        PasswordPairReason.mismatch,
      );
    });

    test('too short AND mismatched → tooShort wins (length is checked first)', () {
      // Reporting "passwords do not match" to someone whose real problem is a
      // 3-character password sends them round the loop again.
      expect(checkPasswordPair('abc', 'xyz'), PasswordPairReason.tooShort);
    });

    test('valid password, empty confirmation → mismatch', () {
      // The submit-time shape when the user tabs past the second field.
      expect(checkPasswordPair('longenough', ''), PasswordPairReason.mismatch);
    });

    test('empty password, filled confirmation → tooShort (password is the field being minted)', () {
      expect(checkPasswordPair('', 'longenough'), PasswordPairReason.tooShort);
    });

    test('comparison is case-sensitive', () {
      // A stuck caps-lock on one field only is a real way to do this.
      expect(
        checkPasswordPair('Secret123', 'secret123'),
        PasswordPairReason.mismatch,
      );
    });

    test('trailing whitespace is significant — not trimmed', () {
      // The headline reason this helper exists. A trailing space is a real
      // character in a password: trimming would call these equal and then
      // store whichever string the caller passed on, so the user's saved
      // password would differ from what they believe they typed.
      expect(
        checkPasswordPair('secret1 ', 'secret1'),
        PasswordPairReason.mismatch,
      );
    });

    test('leading whitespace is significant — not trimmed', () {
      expect(
        checkPasswordPair(' secret1', 'secret1'),
        PasswordPairReason.mismatch,
      );
    });

    test('an all-whitespace password that matches and is long enough → ok', () {
      // This helper validates the PAIR, not password quality. Strength rules
      // are GoTrue's business; inventing one here would reject a password the
      // auth server would have happily accepted.
      final spaces = ' ' * minPasswordLength;
      expect(checkPasswordPair(spaces, spaces), isNull);
    });

    test('a transposition typo is caught', () {
      // The concrete real-world case: same characters, two swapped.
      expect(
        checkPasswordPair('runner123', 'runenr123'),
        PasswordPairReason.mismatch,
      );
    });

    test('matching non-ASCII passwords → ok, and near-misses still mismatch', () {
      expect(checkPasswordPair('påssw0rd', 'påssw0rd'), isNull);
      expect(
        checkPasswordPair('påssw0rd', 'passw0rd'),
        PasswordPairReason.mismatch,
      );
    });

    test('length counts UTF-16 code units, so a short emoji password is accepted', () {
      // '🏃🏃🏃' is 3 glyphs but 6 code units, so .length clears the minimum.
      // Documented rather than defended: GoTrue measures the same way, so
      // this helper and the auth server agree — the property that matters.
      // Dart's String.length is UTF-16 code units too, so the twin agrees
      // with web here by construction.
      const emoji = '🏃🏃🏃';
      expect(emoji.length, minPasswordLength);
      expect(checkPasswordPair(emoji, emoji), isNull);
    });

    test('a long passphrase round-trips', () {
      final long = 'a-very-long-passphrase-' * 10;
      expect(checkPasswordPair(long, long), isNull);
      expect(checkPasswordPair(long, '$long!'), PasswordPairReason.mismatch);
    });
  });
}
