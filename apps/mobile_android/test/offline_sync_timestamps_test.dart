import 'package:flutter_test/flutter_test.dart';

import '../lib/offline_sync_store.dart';

/// decisions § 1289 + § 1290. Every store in the [OfflineSyncStore] family
/// read a timestamp out of a row map, and the read existed nineteen times in
/// five behaviourally distinct spellings — six byte-identical `_parseTs`
/// statics, a `_parseTime` and two `startedAt` getters that dropped the UTC
/// normalisation, seven `fromJson` clock reads that cast before parsing, and a
/// `_parseDate` whose missing normalisation is load-bearing (now the shared
/// `parseCalendarDate`, § 1344). Nothing compared
/// any of them. These are the direct cases the store suites only ever reached
/// through a whole refresh or a whole cold load.
void main() {
  group('parseServerTimestamp', () {
    test('a value that is not a string cannot be a timestamp', () {
      expect(parseServerTimestamp(null), isNull);
      expect(parseServerTimestamp(1757116800000), isNull);
      expect(parseServerTimestamp(1.5), isNull);
      expect(parseServerTimestamp(true), isNull);
      expect(parseServerTimestamp(const <String, dynamic>{}), isNull);
      expect(parseServerTimestamp(const <String>[]), isNull);
    });

    test('an absent, empty or unparseable column is no timestamp', () {
      expect(parseServerTimestamp(''), isNull);
      expect(parseServerTimestamp('   '), isNull);
      expect(parseServerTimestamp('not a date'), isNull);
      expect(parseServerTimestamp('2026-06-32T'), isNull);
    });

    test('out-of-range components are REFUSED, not rolled over', () {
      // § 1344. `DateTime.tryParse` normalises an impossible date through the
      // calendar instead of refusing it — `2026-13-45T99:99:99Z` is
      // 2027-02-18T04:40:39Z and `2026-06-32` is the 2nd of July — so a
      // corrupt column yielded a confident wrong answer that passes every
      // downstream non-null check. The old behaviour is asserted beside the
      // new one so the difference is legible, and so the test fails if the
      // platform ever changes underneath it.
      expect(DateTime.tryParse('2026-13-45T99:99:99Z'),
          DateTime.utc(2027, 2, 18, 4, 40, 39),
          reason: 'the platform behaviour this refuses');
      expect(parseServerTimestamp('2026-13-45T99:99:99Z'), isNull);
      expect(parseServerTimestamp('2026-06-32'), isNull);
      for (final raw in [
        '2026-00-01', // month 0
        '2026-13-01', // month 13
        '2026-06-00', // day 0
        '2026-02-30', // day past February
        '2027-02-29', // day past a NON-leap February
        '2026-06-14T24:00:00Z', // ISO end-of-day, still a rollover here
        '2026-06-14T07:60:00Z',
        '2026-06-14T07:00:60Z',
        '2026-06-14T07:00:00+24:00',
        '2026-06-14T07:00:00+02:60',
      ]) {
        expect(parseServerTimestamp(raw), isNull, reason: raw);
      }
    });

    test('a real date at the edge of its month is still accepted', () {
      // The refusal must be a range check, not a narrowing: the day bound is
      // the target month's OWN last day, so a leap day is a date and the same
      // day one year later is not.
      expect(parseServerTimestamp('2024-02-29T00:00:00Z'),
          DateTime.utc(2024, 2, 29));
      expect(parseServerTimestamp('2026-01-31T23:59:59Z'),
          DateTime.utc(2026, 1, 31, 23, 59, 59));
      expect(parseServerTimestamp('2026-12-31T23:59:59.999Z'),
          DateTime.utc(2026, 12, 31, 23, 59, 59, 999));
    });

    test('every shape a PostgREST column actually arrives in survives', () {
      // The refusal is worthless if it also refuses a legitimate value, and
      // the same text reaches these readers in several spellings.
      for (final raw in [
        '2026-06-14T07:00:00+00:00',
        '2026-06-14T07:00:00.000Z',
        '2026-06-14T07:00:00.123456+00:00',
        '2026-06-14 07:00:00+00',
        '2026-06-14T09:00:00+02:00',
        '2026-06-14T07:00:00',
        '2026-06-14',
        '20260614T070000Z',
      ]) {
        expect(parseServerTimestamp(raw), isNotNull, reason: raw);
      }
    });

    test('a PostgREST timestamptz keeps its instant', () {
      final z = parseServerTimestamp('2026-03-12T06:00:00Z');
      expect(z, DateTime.utc(2026, 3, 12, 6));
      final offset = parseServerTimestamp('2026-03-12T08:00:00+02:00');
      expect(offset, DateTime.utc(2026, 3, 12, 6));
      expect(offset!.isUtc, isTrue);
    });

    test('a zone-less column is normalised, so re-serialising states a zone',
        () {
      // The whole point of the `.toUtc()`. `DateTime.tryParse` answers with a
      // LOCAL DateTime when the text carries no zone designator, and
      // `toIso8601String()` then writes no designator either — leaving the
      // next reader (Postgres, resolving it in the session's own TimeZone) to
      // re-anchor the same wall clock somewhere else. The instant assertion is
      // vacuous on a UTC runner; the designator assertion is not.
      final wall = DateTime(2026, 3, 12, 9);
      final parsed = parseServerTimestamp(wall.toIso8601String());
      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isTrue);
      expect(parsed.isAtSameMomentAs(wall), isTrue);
      expect(parsed.toIso8601String(), endsWith('Z'));
      expect(wall.toIso8601String(), isNot(endsWith('Z')));
    });

    test('every answer it gives is in UTC', () {
      for (final raw in [
        '2026-03-12T06:00:00Z',
        '2026-03-12T08:00:00+02:00',
        '2026-03-12T09:00:00',
        '2026-03-12',
      ]) {
        expect(parseServerTimestamp(raw)?.isUtc, isTrue, reason: raw);
      }
    });
  });

  group('parseCalendarDate', () {
    test('a `date` column keeps its calendar DAY', () {
      // The whole reason this is a second reader rather than a call to
      // `parseServerTimestamp`: normalising local midnight to UTC moves the
      // day itself for a device AHEAD of UTC (local midnight at +03:00 is
      // 21:00 the previous day), and `gear.purchased_at` is written back to a
      // `date` column from this value (decisions § 1289 + § 1344). The `isUtc`
      // assertion below is the half that holds on ANY runner: this one is
      // vacuous west of Greenwich, which is where the workstation sits.
      final at = parseCalendarDate('2026-06-14')!;
      expect(at.isUtc, isFalse);
      expect([at.year, at.month, at.day], [2026, 6, 14]);
      expect([at.hour, at.minute], [0, 0]);
    });

    test('an out-of-range day is refused, not rolled into the next month', () {
      // § 1344, and the reason the refusal matters more here than on the
      // timestamp side: this value goes straight back to a `date` column
      // through `api.createGear` / `api.updateGear`, so a rolled-over day
      // becomes the STORED day.
      expect(parseCalendarDate('2026-06-32'), isNull);
      expect(parseCalendarDate('2026-02-30'), isNull);
      expect(parseCalendarDate('2026-13-01'), isNull);
      expect(parseCalendarDate('2026-06-00'), isNull);
      expect(parseCalendarDate('2024-02-29'), isNotNull,
          reason: 'a leap day is a date');
    });

    test('a non-string, empty or unparseable column is no date', () {
      for (final raw in <dynamic>[null, '', '   ', 'not a date', 1, 2.5, true]) {
        expect(parseCalendarDate(raw), isNull, reason: '$raw');
      }
    });
  });

  group('storedClockOrEpoch', () {
    test('a readable clock is the record own clock, in UTC', () {
      expect(storedClockOrEpoch('2026-03-12T06:00:00Z'), DateTime.utc(2026, 3, 12, 6));
      expect(storedClockOrEpoch('2026-03-12T08:00:00+02:00'),
          DateTime.utc(2026, 3, 12, 6));
    });

    test('a clock of the WRONG TYPE reads as no clock, it does not throw', () {
      // The `as String?` cast this replaced threw here, and both the cold-load
      // walk and the backup restore catch — so a record whose clock field was
      // a number was discarded whole, payload and all, while the same record
      // with NO clock field was kept.
      expect(storedClockOrEpoch(1757116800000), kUnknownStoredClock);
      expect(storedClockOrEpoch(1757116800000).isUtc, isTrue);
    });

    test('an absent, empty or unusable clock is the EPOCH, not now', () {
      // It was `now` until § 1342. `now` is later than every
      // `last_modified_at` the server will ever stamp, so the record won
      // newer-wins for good; the epoch loses it, which is what an unknown
      // clock is entitled to.
      for (final raw in <dynamic>[null, '', 'not a date', 1, 2.5, true, <int>[]]) {
        expect(storedClockOrEpoch(raw), kUnknownStoredClock, reason: '$raw');
      }
    });

    test('the unknown clock loses newer-wins against any server stamp', () {
      // The comparison every `replaceFromServer` in the family runs. A clock
      // that wins this freezes the row against the server, because
      // `rewriteAll` persists the winning value and the next launch compares
      // it again.
      for (final serverTs in [
        DateTime.utc(1970, 1, 1, 0, 0, 1),
        DateTime.utc(2026, 3, 12, 6),
        DateTime.now().toUtc(),
      ]) {
        expect(storedClockOrEpoch(null).isAfter(serverTs), isFalse,
            reason: '$serverTs');
      }
      expect(DateTime.now().toUtc().isAfter(DateTime.utc(2026, 3, 12, 6)), isTrue,
          reason: 'the old fallback won this comparison, which is the defect');
    });

    test('the unknown clock sorts LAST in a most-recently-modified list', () {
      // `local_routine_store` / `local_recipe_store` / `local_meal_template_store`
      // all order their library with `b.lastModifiedAt.compareTo(a.…)`. Under
      // the old `now` fallback an unreadable record claimed the head of that
      // list — the freshest thing the user owns.
      final clocks = [
        DateTime.utc(2026, 3, 12, 6),
        storedClockOrEpoch(null),
        DateTime.utc(2025, 1, 1),
      ]..sort((a, b) => b.compareTo(a));
      expect(clocks.last, kUnknownStoredClock);
    });

    test('a zone-less stored clock keeps its instant', () {
      final wall = DateTime(2026, 3, 12, 9);
      final at = storedClockOrEpoch(wall.toIso8601String());
      expect(at.isAtSameMomentAs(wall), isTrue);
      expect(at.isUtc, isTrue);
    });
  });
}
