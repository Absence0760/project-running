// Mirror of web `apps/web/src/lib/nutrition/diary_day.test.ts` — same cases in
// the same order, so a divergence between the two diaries fails on one side.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/diary_day.dart';

void main() {
  final now = DateTime(2026, 8, 13, 14, 22, 9, 250); // Thu 13 Aug 2026, local

  test('isoDateOf zero-pads month and day', () {
    expect(isoDateOf(DateTime(2026, 1, 3)), '2026-01-03');
    expect(isoDateOf(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('parseIsoDate accepts a real calendar date', () {
    expect(parseIsoDate('2026-08-13'), const CalendarDate(2026, 8, 13));
    expect(parseIsoDate('2024-02-29'), const CalendarDate(2024, 2, 29));
  });

  test('parseIsoDate rejects anything that is not a real zero-padded calendar date',
      () {
    for (final bad in <String?>[
      null,
      '',
      'today',
      '2026-8-3', // unpadded
      '2026-13-01', // month out of range
      '2026-00-10',
      '2026-02-30', // DateTime would normalise this into March
      '2026-02-29', // 2026 is not a leap year
      '0026-02-01', // two-digit years mean 1900+y to the web sibling's Date
      '2026-08-13T00:00:00',
      ' 2026-08-13',
    ]) {
      expect(parseIsoDate(bad), isNull, reason: 'expected null for $bad');
    }
  });

  test('resolveDiaryDate keeps a real past date and falls back to today otherwise',
      () {
    expect(resolveDiaryDate('2026-08-10', now), '2026-08-10');
    expect(resolveDiaryDate('2026-08-13', now), '2026-08-13');
    expect(resolveDiaryDate(null, now), '2026-08-13');
    expect(resolveDiaryDate('nonsense', now), '2026-08-13');
    expect(resolveDiaryDate('2026-02-30', now), '2026-08-13');
  });

  test('resolveDiaryDate clamps a future date to today — nobody can have eaten tomorrow',
      () {
    expect(resolveDiaryDate('2026-08-14', now), '2026-08-13');
    expect(resolveDiaryDate('2099-01-01', now), '2026-08-13');
  });

  test('stepDiaryDate walks the calendar across month, year and leap-day edges',
      () {
    expect(stepDiaryDate('2026-08-01', -1, now), '2026-07-31');
    expect(stepDiaryDate('2026-03-01', -1, DateTime(2026, 8, 13)), '2026-02-28');
    expect(stepDiaryDate('2024-03-01', -1, DateTime(2026, 8, 13)), '2024-02-29');
    expect(stepDiaryDate('2026-01-01', -1, now), '2025-12-31');
    expect(stepDiaryDate('2025-12-31', 1, now), '2026-01-01');
    expect(stepDiaryDate('2026-08-01', -7, now), '2026-07-25');
  });

  test('stepDiaryDate never steps past today', () {
    expect(stepDiaryDate('2026-08-13', 1, now), '2026-08-13');
    expect(stepDiaryDate('2026-08-12', 5, now), '2026-08-13');
    expect(stepDiaryDate('2026-08-12', 1, now), '2026-08-13');
  });

  test('stepDiaryDate resolves an unparseable day to today', () {
    expect(stepDiaryDate('rubbish', -1, now), '2026-08-13');
  });

  test('isDiaryToday and canStepForward agree on the boundary', () {
    expect(isDiaryToday('2026-08-13', now), isTrue);
    expect(isDiaryToday('2026-08-12', now), isFalse);
    expect(canStepForward('2026-08-13', now), isFalse);
    expect(canStepForward('2026-08-12', now), isTrue);
  });

  test('diaryWindow spans local midnight to the next local midnight', () {
    final w = diaryWindow('2026-08-13');
    expect(w, isNotNull);
    expect(w!.start, DateTime(2026, 8, 13));
    expect(w.end, DateTime(2026, 8, 14));
  });

  test('diaryWindow of n days starts n-1 days earlier and keeps the same end',
      () {
    final w = diaryWindow('2026-08-13', 7);
    expect(w, isNotNull);
    expect(w!.start, DateTime(2026, 8, 7));
    expect(w.end, DateTime(2026, 8, 14));
  });

  test('diaryWindow fails closed on an unusable day or a non-positive span', () {
    expect(diaryWindow('2026-02-30'), isNull);
    expect(diaryWindow('nope'), isNull);
    expect(diaryWindow('2026-08-13', 0), isNull);
  });

  test('isWithinWindow includes the start instant and excludes the end instant',
      () {
    final w = diaryWindow('2026-08-13')!;
    expect(isWithinWindow(w.start.toUtc().toIso8601String(), w), isTrue);
    expect(isWithinWindow(w.end.toUtc().toIso8601String(), w), isFalse);
    expect(
      isWithinWindow(
          DateTime(2026, 8, 13, 23, 59, 59).toUtc().toIso8601String(), w),
      isTrue,
    );
    expect(
      isWithinWindow(
          DateTime(2026, 8, 12, 23, 59, 59).toUtc().toIso8601String(), w),
      isFalse,
    );
  });

  test('isWithinWindow compares instants, not strings — the boundary row is kept',
      () {
    final w = diaryWindow('2026-08-13')!;
    final startIso = w.start.toUtc().toIso8601String();
    // Postgres' rendering of the very same moment the window starts at.
    final pgStyle = startIso.replaceAll('Z', '+00:00');
    expect(isWithinWindow(pgStyle, w), isTrue);
    // The string compare this replaces drops it, because '+' sorts below '.'.
    expect(pgStyle.compareTo(startIso) >= 0, isFalse);
  });

  test('isWithinWindow rejects a missing or unparseable timestamp', () {
    final w = diaryWindow('2026-08-13')!;
    expect(isWithinWindow(null, w), isFalse);
    expect(isWithinWindow('', w), isFalse);
    expect(isWithinWindow('not a time', w), isFalse);
  });

  test('trailingDates returns n dates oldest first, ending on the day itself',
      () {
    expect(trailingDates('2026-08-13', 7), [
      '2026-08-07',
      '2026-08-08',
      '2026-08-09',
      '2026-08-10',
      '2026-08-11',
      '2026-08-12',
      '2026-08-13',
    ]);
    expect(trailingDates('2026-03-02', 3),
        ['2026-02-28', '2026-03-01', '2026-03-02']);
    expect(trailingDates('2026-08-13', 1), ['2026-08-13']);
  });

  test('trailingDates buckets match isoDateOf, so an entry lands in its own day',
      () {
    final days = trailingDates('2026-08-13', 7);
    final entryAt = DateTime(2026, 8, 9, 23, 30);
    expect(days.contains(isoDateOf(entryAt)), isTrue);
  });

  test('trailingDates is empty for an unusable day or a non-positive count', () {
    expect(trailingDates('rubbish', 7), isEmpty);
    expect(trailingDates('2026-08-13', 0), isEmpty);
  });

  test('entryTimestampFor on today is exactly now', () {
    expect(entryTimestampFor('2026-08-13', now), now);
    expect(entryTimestampFor('rubbish', now), now);
  });

  test('entryTimestampFor on a past day keeps the clock time and lands inside that day',
      () {
    final at = entryTimestampFor('2026-08-10', now);
    expect(isoDateOf(at), '2026-08-10');
    expect(at.hour, 14);
    expect(at.minute, 22);
    final w = diaryWindow('2026-08-10')!;
    expect(at.isBefore(w.start), isFalse);
    expect(at.isBefore(w.end), isTrue);
  });

  test('entryTimestampFor is monotonic across a back-filling session', () {
    final first =
        entryTimestampFor('2026-08-10', DateTime(2026, 8, 13, 14, 22, 9));
    final second =
        entryTimestampFor('2026-08-10', DateTime(2026, 8, 13, 14, 22, 11));
    expect(second.isAfter(first), isTrue);
  });

  test('waterDayKey keeps the shipped unpadded shape so no stored count is orphaned',
      () {
    // The key format that shipped: `${d.year}-${d.month}-${d.day}`.
    final d = DateTime(2026, 8, 3);
    expect(waterDayKey('2026-08-03'), '${d.year}-${d.month}-${d.day}');
    expect(waterDayKey('2026-08-03'), '2026-8-3');
    expect(waterDayKey('2026-12-31'), '2026-12-31');
  });

  test('waterDayKey passes an unusable day through rather than colliding on a fallback',
      () {
    expect(waterDayKey('rubbish'), 'rubbish');
  });

  test('msUntilNextLocalMidnight lands exactly on the next local midnight', () {
    final n = DateTime(2026, 8, 13, 14, 22, 9, 250);
    final at = n.add(Duration(milliseconds: msUntilNextLocalMidnight(n)));
    expect(at, DateTime(2026, 8, 14));
    expect(isoDateOf(at), '2026-08-14');
    // One millisecond earlier is still the day the diary is labelling "Today".
    expect(isoDateOf(at.subtract(const Duration(milliseconds: 1))),
        isoDateOf(n));
  });

  test('msUntilNextLocalMidnight is always a positive, bounded delay', () {
    // A zero or negative delay would make a rollover re-arm itself in a tight
    // loop; anything beyond a 25 h day means it stopped stepping calendar days.
    // Sampled across the whole clock, including both boundaries.
    for (final t in [
      [0, 0, 0, 0],
      [0, 0, 0, 1],
      [12, 30, 15, 500],
      [23, 59, 59, 999],
    ]) {
      final n = DateTime(2026, 8, 13, t[0], t[1], t[2], t[3]);
      final delay = msUntilNextLocalMidnight(n);
      expect(delay > 0, isTrue, reason: 'delay must be positive at ${t[0]}:${t[1]}');
      expect(delay <= 25 * 3600000, isTrue,
          reason: 'delay must stay inside one calendar day at ${t[0]}:${t[1]}');
    }
  });

  test('msUntilNextLocalMidnight crosses a month and a year end', () {
    final monthEnd = DateTime(2026, 8, 31, 22);
    expect(
      monthEnd.add(Duration(milliseconds: msUntilNextLocalMidnight(monthEnd))),
      DateTime(2026, 9, 1),
    );
    final yearEnd = DateTime(2026, 12, 31, 22);
    expect(
      yearEnd.add(Duration(milliseconds: msUntilNextLocalMidnight(yearEnd))),
      DateTime(2027, 1, 1),
    );
  });
}
