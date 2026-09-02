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

    test('strips EVERY member of the hyphen family', () {
      // The class used to hold three of these under a comment claiming the
      // family, and the case above exercised two. A macOS or Word autocorrect
      // produces U+2013 or U+2014; a CJK keyboard U+FF0D; a spreadsheet
      // export U+2212 — so the same contact card could be accepted once and
      // refused once.
      const family = [
        '\u002D', '\u2010', '\u2011', '\u2012', '\u2013',
        '\u2014', '\u2015', '\u2212', '\uFE58', '\uFE63', '\uFF0D',
      ];
      for (final dash in family) {
        expect(
          normaliseE164('+44${dash}7700${dash}900123'),
          '+447700900123',
          reason: 'U+${dash.codeUnitAt(0).toRadixString(16).toUpperCase().padLeft(4, '0')}',
        );
      }
    });

    test('strips the invisible characters a paste carries', () {
      // A zero-width space, a soft hyphen or a BOM survives a copy off a web
      // page and no reader can see one to delete it.
      const invisibles = [
        '\u00AD', '\u200B', '\u200C', '\u200D', '\uFEFF', '\u3000', '\u205F',
      ];
      for (final ch in invisibles) {
        expect(
          normaliseE164('+44${ch}7700${ch}900123'),
          '+447700900123',
          reason: 'U+${ch.codeUnitAt(0).toRadixString(16).toUpperCase().padLeft(4, '0')}',
        );
      }
    });

    test('deletes a FULLWIDTH parenthesised trunk zero whole, like the ASCII one',
        () {
      // The bracket sets in _separators and _trunkZero have to match. A
      // bracket the separator class folds but the trunk-zero one does not
      // leaves the 0 behind and yields a different, CONFORMING number that
      // would deliver the overdue alert to nobody.
      expect(normaliseE164('+44\uFF080\uFF09 7700 900123'), '+447700900123');
      expect(normaliseE164('+44 (0) 7700 900123'), '+447700900123');
    });

    test('refuses a separator it does not know rather than guessing', () {
      // An unrecognised separator surfaces as an error the owner can act on;
      // silently dropping an unknown character could change the number.
      expect(normaliseE164('+44_7700_900123'), isNull);
      expect(normaliseE164('+44*7700*900123'), isNull);
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
