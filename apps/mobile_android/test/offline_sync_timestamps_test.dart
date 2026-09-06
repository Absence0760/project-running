import 'package:flutter_test/flutter_test.dart';

import '../lib/offline_sync_store.dart';

/// decisions § 1289 + § 1290. Every store in the [OfflineSyncStore] family
/// read a timestamp out of a row map, and the read existed nineteen times in
/// five behaviourally distinct spellings — six byte-identical `_parseTs`
/// statics, a `_parseTime` and two `startedAt` getters that dropped the UTC
/// normalisation, seven `fromJson` clock reads that cast before parsing, and a
/// `_parseDate` whose missing normalisation is load-bearing. Nothing compared
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

    test('out-of-range components ROLL OVER, they are not rejected', () {
      // Pinning what `DateTime.tryParse` actually does rather than what the
      // name suggests: a string that is syntactically an ISO timestamp but
      // names an impossible instant is normalised through the calendar, not
      // refused. So a corrupt column can yield a confident wrong answer here,
      // and no caller in the family may treat a non-null return as proof the
      // column was sane — they only ever compare it or store it.
      expect(parseServerTimestamp('2026-13-45T99:99:99Z'),
          DateTime.utc(2027, 2, 18, 4, 40, 39));
      expect(parseServerTimestamp('2026-06-32')!.isAtSameMomentAs(
          DateTime(2026, 7, 2)), isTrue);
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

  group('storedClockOrNow', () {
    test('a readable clock is the record own clock, in UTC', () {
      expect(storedClockOrNow('2026-03-12T06:00:00Z'), DateTime.utc(2026, 3, 12, 6));
      expect(storedClockOrNow('2026-03-12T08:00:00+02:00'),
          DateTime.utc(2026, 3, 12, 6));
    });

    test('a clock of the WRONG TYPE reads as no clock, it does not throw', () {
      // The `as String?` cast this replaced threw here, and both the cold-load
      // walk and the backup restore catch — so a record whose clock field was
      // a number was discarded whole, payload and all, while the same record
      // with NO clock field was kept.
      final before = DateTime.now().toUtc();
      final at = storedClockOrNow(1757116800000);
      final after = DateTime.now().toUtc();
      expect(at.isUtc, isTrue);
      expect(at.isBefore(before), isFalse);
      expect(at.isAfter(after), isFalse);
    });

    test('an absent, empty or unparseable clock all read as now', () {
      for (final raw in <dynamic>[null, '', 'not a date', 1, 2.5, true, <int>[]]) {
        final before = DateTime.now().toUtc();
        final at = storedClockOrNow(raw);
        final after = DateTime.now().toUtc();
        expect(at.isUtc, isTrue, reason: '$raw');
        expect(at.isBefore(before), isFalse, reason: '$raw');
        expect(at.isAfter(after), isFalse, reason: '$raw');
      }
    });

    test('a zone-less stored clock keeps its instant', () {
      final wall = DateTime(2026, 3, 12, 9);
      final at = storedClockOrNow(wall.toIso8601String());
      expect(at.isAtSameMomentAs(wall), isTrue);
      expect(at.isUtc, isTrue);
    });
  });
}
