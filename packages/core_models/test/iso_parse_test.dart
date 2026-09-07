import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// decisions § 1344 + § 1377. `DateTime.tryParse` ROLLS an out-of-range
/// component over through the calendar instead of refusing it, so an unusable
/// column yields a confident WRONG value rather than no value — and a wrong
/// timestamp survives every downstream non-null and `> 0` check a real one
/// would. These pin the refusal, and the acceptance of everything the platform
/// answers correctly, at the one place in the tree that parses the text.
void main() {
  group('parseIsoStrict refuses what tryParse rolls over', () {
    test('an impossible month, day, hour, minute and second are all refused',
        () {
      for (final text in [
        '2026-13-45T99:99:99Z',
        '2026-06-32',
        '2026-02-30',
        '2027-02-29',
        '2026-00-10',
        '2026-06-00',
        '2026-06-14T25:00:00Z',
        '2026-06-14T12:60:00Z',
        '2026-06-14T12:00:61Z',
      ]) {
        expect(parseIsoStrict(text), isNull, reason: text);
        // The control the refusal is FOR: the platform answers every one of
        // these, and answers wrongly.
        expect(DateTime.tryParse(text), isNotNull, reason: text);
      }
    });

    test('the end-of-day 24:00 form is refused', () {
      // Legal ISO 8601, nothing in this tree emits it, and it is
      // indistinguishable from the rollover this exists to catch.
      expect(parseIsoStrict('2026-06-14T24:00:00Z'), isNull);
      expect(DateTime.tryParse('2026-06-14T24:00:00Z'), isNotNull);
    });

    test('an out-of-range zone offset is refused', () {
      expect(parseIsoStrict('2026-06-14T07:00:00+24:00'), isNull);
      expect(parseIsoStrict('2026-06-14T07:00:00+02:60'), isNull);
    });

    test('29 February is a date in a leap year and not in a common one', () {
      expect(parseIsoStrict('2024-02-29'), DateTime(2024, 2, 29));
      expect(parseIsoStrict('2027-02-29'), isNull);
    });
  });

  group('parseIsoStrict accepts everything the platform reads correctly', () {
    test('every spelling the SDK grammar admits survives', () {
      for (final text in [
        '2026-06-14',
        '20260614',
        '2026-06-14T07:00:00Z',
        '2026-06-14T07:00:00z',
        '2026-06-14 07:00:00Z',
        '2026-06-14T07:00',
        '2026-06-14T07',
        '2026-06-14T07:00:00.123456Z',
        '2026-06-14T07:00:00,123Z',
        '2026-06-14T070000Z',
        '2026-06-14T07:00:00+02:00',
        '2026-06-14T07:00:00-0430',
        '2026-06-14T07:00:00 +02:00',
        '+002026-06-14T07:00:00Z',
      ]) {
        expect(parseIsoStrict(text), DateTime.parse(text), reason: text);
      }
    });

    test('text the platform cannot read at all is still refused', () {
      for (final text in ['', 'yesterday', '14/06/2026', '2026-6-14']) {
        expect(parseIsoStrict(text), isNull, reason: text);
      }
    });

    test('the zone the platform assigns is preserved, not normalised', () {
      // `parseCalendarDate` depends on this: a `date` column normalised to UTC
      // moves the DAY for every device ahead of UTC (§ 1344).
      expect(parseIsoStrict('2026-06-14')!.isUtc, isFalse);
      expect(parseIsoStrict('2026-06-14T07:00:00Z')!.isUtc, isTrue);
      expect(parseIsoStrict('2026-06-14T09:00:00+02:00'),
          DateTime.utc(2026, 6, 14, 7));
    });
  });

  group('parseIsoStrictValue reads a row field', () {
    test('a non-String or empty field is absent rather than an error', () {
      for (final v in [null, '', 42, <String, dynamic>{}, true]) {
        expect(parseIsoStrictValue(v), isNull, reason: '$v');
      }
    });

    test('a usable field is the same answer parseIsoStrict gives', () {
      expect(parseIsoStrictValue('2026-06-14T07:00:00Z'),
          DateTime.utc(2026, 6, 14, 7));
      expect(parseIsoStrictValue('2026-06-32'), isNull);
    });
  });
}
