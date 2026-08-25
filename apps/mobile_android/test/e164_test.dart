import 'package:flutter_test/flutter_test.dart';

import '../lib/e164.dart';

void main() {
  group('normaliseE164', () {
    test('passes an already-bare E.164 number through unchanged', () {
      expect(normaliseE164('+447700900123'), '+447700900123');
    });

    test('strips the spacing people paste off a contact card', () {
      expect(normaliseE164('+44 7700 900 123'), '+447700900123');
    });

    test('strips hyphens, dots, slashes and brackets', () {
      expect(normaliseE164('+1 (555) 010-1234'), '+15550101234');
      expect(normaliseE164('+1.555.010.1234'), '+15550101234');
      expect(normaliseE164('+49 30/1234567'), '+49301234567');
    });

    test('strips non-breaking and narrow-no-break spaces', () {
      expect(normaliseE164('+33 6 12 34 56 78'),
          '+33612345678');
    });

    test('strips the hyphen family, not just ASCII hyphen-minus', () {
      expect(normaliseE164('+44‑7700–900123'), '+447700900123');
    });

    test('reads the ITU access prefix 00 as +', () {
      expect(normaliseE164('0044 7700 900123'), '+447700900123');
    });

    test('deletes a parenthesised trunk zero rather than keeping the digit',
        () {
      // The dangerous case: stripping only the brackets yields
      // +4407700900123, a different number that still passes the CHECK.
      expect(normaliseE164('+44 (0) 7700 900123'), '+447700900123');
      expect(normaliseE164('+44 (0)7700900123'), '+447700900123');
    });

    test('leaves a real bracketed area code alone', () {
      expect(normaliseE164('+61 (2) 5550 1234'), '+61255501234');
    });

    test('refuses a national-format number with no country', () {
      // Guessing a country here would arm the escalation at a stranger.
      expect(normaliseE164('07700900123'), isNull);
      expect(normaliseE164('7700900123'), isNull);
    });

    test('refuses a lone trunk-prefixed number once the (0) is deleted', () {
      expect(normaliseE164('(0)7700900123'), isNull);
    });

    test('refuses letters, extensions and anything else non-numeric', () {
      expect(normaliseE164('+44 7700 900123 ext 12'), isNull);
      expect(normaliseE164('not a phone'), isNull);
    });

    test('refuses a leading zero after the plus (E.164 has no country code 0)',
        () {
      expect(normaliseE164('+0447700900123'), isNull);
    });

    test('refuses numbers outside the 7..15 digit span', () {
      expect(normaliseE164('+123456'), isNull);
      expect(normaliseE164('+1234567'), '+1234567');
      expect(normaliseE164('+123456789012345'), '+123456789012345');
      expect(normaliseE164('+1234567890123456'), isNull);
    });

    test('treats empty, blank and null as no number on file', () {
      expect(normaliseE164(''), isNull);
      expect(normaliseE164('   '), isNull);
      expect(normaliseE164(null), isNull);
    });

    test('exposes the same pattern the column CHECK enforces', () {
      expect(e164Pattern.hasMatch('+447700900123'), isTrue);
      expect(e164Pattern.hasMatch('+44 7700 900123'), isFalse);
    });

    test('is idempotent — normalising its own output changes nothing', () {
      final once = normaliseE164('+44 (0) 7700-900 123');
      expect(once, '+447700900123');
      expect(normaliseE164(once), once);
    });
  });
}
