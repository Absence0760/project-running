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
