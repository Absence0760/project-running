import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/screens/period_summary_screen.dart';
import 'package:mobile_android/preferences.dart';

Run _makeRun({
  required DateTime startedAt,
  required double distanceMetres,
  required int durationSeconds,
  String? id,
}) {
  return Run(
    id: id ?? startedAt.toIso8601String(),
    startedAt: startedAt,
    duration: Duration(seconds: durationSeconds),
    distanceMetres: distanceMetres,
    source: RunSource.app,
  );
}

void main() {
  // ── periodStart / periodEnd ──────────────────────────────────────────

  group('periodStart', () {
    test('week: returns Monday 00:00 of the containing week', () {
      // 2026-04-13 is a Monday
      final monday = DateTime(2026, 4, 13, 14, 30);
      expect(periodStart(PeriodType.week, monday), DateTime(2026, 4, 13));

      // 2026-04-17 is a Friday — should still give Monday the 13th
      final friday = DateTime(2026, 4, 17, 9, 0);
      expect(periodStart(PeriodType.week, friday), DateTime(2026, 4, 13));

      // 2026-04-19 is a Sunday
      final sunday = DateTime(2026, 4, 19, 23, 59);
      expect(periodStart(PeriodType.week, sunday), DateTime(2026, 4, 13));
    });

    test('month: returns the 1st of the month', () {
      final mid = DateTime(2026, 7, 15);
      expect(periodStart(PeriodType.month, mid), DateTime(2026, 7, 1));

      final first = DateTime(2026, 1, 1);
      expect(periodStart(PeriodType.month, first), DateTime(2026, 1, 1));
    });
  });

  group('periodEnd', () {
    test('week: returns the following Monday', () {
      final anchor = DateTime(2026, 4, 15); // Wednesday
      expect(periodEnd(PeriodType.week, anchor), DateTime(2026, 4, 20));
    });

    test('month: returns 1st of next month', () {
      final anchor = DateTime(2026, 3, 10);
      expect(periodEnd(PeriodType.month, anchor), DateTime(2026, 4, 1));
    });

    test('month: December wraps to January of next year', () {
      final anchor = DateTime(2026, 12, 25);
      expect(periodEnd(PeriodType.month, anchor), DateTime(2027, 1, 1));
    });
  });

  // ── periodTitle / periodLabel ────────────────────────────────────────

  group('periodTitle', () {
    test('week: "Week of <day> <month>"', () {
      final anchor = DateTime(2026, 4, 15); // Wed -> week starts Mon 13 Apr
      expect(periodTitle(PeriodType.week, anchor), 'Week of 13 Apr');
    });

    test('month: "<month name> <year>"', () {
      final anchor = DateTime(2026, 11, 5);
      expect(periodTitle(PeriodType.month, anchor), 'November 2026');
    });
  });

  group('periodLabel', () {
    test('week: date range "d Mon – d Mon"', () {
      final anchor = DateTime(2026, 4, 13); // Monday
      final label = periodLabel(PeriodType.week, anchor);
      expect(label, '13 Apr – 19 Apr');
    });

    test('month: same as title format', () {
      final anchor = DateTime(2026, 2, 14);
      expect(periodLabel(PeriodType.month, anchor), 'February 2026');
    });
  });

  // ── computePeriodStats ───────────────────────────────────────────────

  group('computePeriodStats', () {
    test('empty list gives zeroes and null pace', () {
      final stats = computePeriodStats([]);
      expect(stats.runCount, 0);
      expect(stats.totalDistanceMetres, 0.0);
      expect(stats.totalDurationSec, 0);
      expect(stats.avgPaceSecPerKm, isNull);
    });

    test('single run', () {
      final runs = [
        _makeRun(
          startedAt: DateTime(2026, 4, 14),
          distanceMetres: 5000,
          durationSeconds: 1500, // 25 min
        ),
      ];
      final stats = computePeriodStats(runs);
      expect(stats.runCount, 1);
      expect(stats.totalDistanceMetres, 5000);
      expect(stats.totalDurationSec, 1500);
      // 1500 / (5000/1000) = 300 sec/km = 5:00/km
      expect(stats.avgPaceSecPerKm, 300);
    });

    test('multiple runs aggregate correctly', () {
      final runs = [
        _makeRun(
          startedAt: DateTime(2026, 4, 14),
          distanceMetres: 5000,
          durationSeconds: 1500,
        ),
        _makeRun(
          startedAt: DateTime(2026, 4, 15),
          distanceMetres: 10000,
          durationSeconds: 3600,
        ),
      ];
      final stats = computePeriodStats(runs);
      expect(stats.runCount, 2);
      expect(stats.totalDistanceMetres, 15000);
      expect(stats.totalDurationSec, 5100);
      // 5100 / (15000/1000) = 340 sec/km
      expect(stats.avgPaceSecPerKm, 340);
    });

    test('very short distance gives null pace', () {
      final runs = [
        _makeRun(
          startedAt: DateTime(2026, 4, 14),
          distanceMetres: 5, // < 10m threshold
          durationSeconds: 60,
        ),
      ];
      final stats = computePeriodStats(runs);
      expect(stats.avgPaceSecPerKm, isNull);
    });
  });

  // ── buildPeriodShareText ─────────────────────────────────────────────

  group('buildPeriodShareText', () {
    test('includes title, run count, distance, and per-run lines', () {
      final runs = [
        _makeRun(
          startedAt: DateTime(2026, 4, 14, 8, 0),
          distanceMetres: 5000,
          durationSeconds: 1500,
          id: 'r1',
        ),
        _makeRun(
          startedAt: DateTime(2026, 4, 16, 7, 0),
          distanceMetres: 8000,
          durationSeconds: 2400,
          id: 'r2',
        ),
      ];

      final text = buildPeriodShareText(
        period: PeriodType.week,
        anchor: DateTime(2026, 4, 14),
        runs: runs,
        unit: DistanceUnit.km,
      );

      expect(text, contains('Week of 13 Apr'));
      expect(text, contains('2 runs'));
      expect(text, contains('13.00 km'));
      expect(text, contains('Avg pace:'));
      expect(text, contains('14 Apr'));
      expect(text, contains('16 Apr'));
    });

    test('single run uses singular "run"', () {
      final runs = [
        _makeRun(
          startedAt: DateTime(2026, 4, 14),
          distanceMetres: 3000,
          durationSeconds: 1000,
          id: 'r1',
        ),
      ];

      final text = buildPeriodShareText(
        period: PeriodType.month,
        anchor: DateTime(2026, 4, 14),
        runs: runs,
        unit: DistanceUnit.km,
      );

      expect(text, contains('April 2026'));
      expect(text, contains('1 run\n'));
    });

    test('empty runs omits per-run lines and pace', () {
      final text = buildPeriodShareText(
        period: PeriodType.week,
        anchor: DateTime(2026, 4, 14),
        runs: [],
        unit: DistanceUnit.km,
      );

      expect(text, contains('0 runs'));
      expect(text, contains('0.00 km'));
      expect(text, isNot(contains('Avg pace:')));
    });

    test('respects miles unit', () {
      final runs = [
        _makeRun(
          startedAt: DateTime(2026, 4, 14),
          distanceMetres: 1609.344, // 1 mile
          durationSeconds: 480, // 8 min
          id: 'r1',
        ),
      ];

      final text = buildPeriodShareText(
        period: PeriodType.week,
        anchor: DateTime(2026, 4, 14),
        runs: runs,
        unit: DistanceUnit.mi,
      );

      expect(text, contains('1.00 mi'));
      expect(text, contains('/mi'));
    });
  });

  // ── formatDurationCoarse ─────────────────────────────────────────────

  group('formatDurationCoarse', () {
    test('minutes and seconds', () {
      expect(formatDurationCoarse(const Duration(minutes: 25, seconds: 30)),
          '25m 30s');
    });

    test('hours and minutes', () {
      expect(formatDurationCoarse(const Duration(hours: 1, minutes: 12)),
          '1h 12m');
    });

    test('exact hours', () {
      expect(formatDurationCoarse(const Duration(hours: 2)), '2h');
    });

    test('zero', () {
      expect(formatDurationCoarse(Duration.zero), '0m 0s');
    });
  });

  // ── shortDate / monthName ────────────────────────────────────────────

  group('shortDate', () {
    test('formats day and abbreviated month', () {
      expect(shortDate(DateTime(2026, 1, 5)), '5 Jan');
      expect(shortDate(DateTime(2026, 12, 31)), '31 Dec');
    });
  });

  group('monthName', () {
    test('returns full month name', () {
      expect(monthName(1), 'January');
      expect(monthName(6), 'June');
      expect(monthName(12), 'December');
    });
  });
}
