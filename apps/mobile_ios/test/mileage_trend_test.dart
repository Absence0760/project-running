import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/mileage_trend.dart';

Run _run({
  required DateTime startedAt,
  required double distanceM,
}) =>
    Run(
      id: 'r-${startedAt.millisecondsSinceEpoch}',
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
      distanceMetres: distanceM,
      source: RunSource.app,
    );

void main() {
  setUpAll(() => initializeDateFormatting());

  final now = DateTime(2026, 5, 19, 12); // Tuesday

  group('aggregateMileage — weekly', () {
    test('returns empty when there are no runs', () {
      final out = aggregateMileage(const [], view: MileageView.weekly, now: now);
      expect(out, isEmpty);
    });

    test('groups same-week runs into a single bucket (Monday anchor)', () {
      // Mon 11 May 2026 + Wed 13 May 2026 → same ISO week (starts
      // Monday 11 May). Total should sum.
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 5000),
          _run(startedAt: DateTime(2026, 5, 13, 6), distanceM: 8000),
        ],
        view: MileageView.weekly,
        now: now,
      );
      expect(out, hasLength(1));
      expect(out.first.distanceM, 13000);
      expect(out.first.label, 'May 11');
    });

    test('separates runs across week boundaries', () {
      // Sunday 10 May → previous week (Mon 4 May); Monday 11 May →
      // new week. Two buckets.
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2026, 5, 10, 7), distanceM: 5000),
          _run(startedAt: DateTime(2026, 5, 11, 6), distanceM: 8000),
        ],
        view: MileageView.weekly,
        now: now,
      );
      expect(out, hasLength(2));
      // Order is chronological.
      expect(out[0].label, 'May 4');
      expect(out[0].distanceM, 5000);
      expect(out[1].label, 'May 11');
      expect(out[1].distanceM, 8000);
    });

    test('caps at the most-recent 12 buckets by default', () {
      // 14 weeks of runs → only the last 12 buckets survive.
      final runs = <Run>[];
      for (var i = 0; i < 14; i++) {
        runs.add(_run(
          startedAt: DateTime(2026, 1, 5).add(Duration(days: 7 * i)),
          distanceM: 1000.0 * (i + 1),
        ));
      }
      final out =
          aggregateMileage(runs, view: MileageView.weekly, now: now);
      expect(out, hasLength(12));
      // Earliest two buckets are dropped — first remaining is the 3rd week.
      expect(out.first.distanceM, 3000);
      expect(out.last.distanceM, 14000);
    });

    test('respects maxBuckets override', () {
      final runs = [
        for (var i = 0; i < 5; i++)
          _run(
            startedAt: DateTime(2026, 1, 5).add(Duration(days: 7 * i)),
            distanceM: 1000,
          ),
      ];
      final out = aggregateMileage(
        runs,
        view: MileageView.weekly,
        now: now,
        maxBuckets: 3,
      );
      expect(out, hasLength(3));
    });
  });

  group('aggregateMileage — monthly', () {
    test('groups same-month runs into one bucket', () {
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2026, 4, 2, 7), distanceM: 5000),
          _run(startedAt: DateTime(2026, 4, 30, 6), distanceM: 8000),
        ],
        view: MileageView.monthly,
        now: now,
      );
      expect(out, hasLength(1));
      expect(out.first.distanceM, 13000);
      expect(out.first.label, "Apr '26");
    });

    test('separates runs across month boundaries with chronological order',
        () {
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2026, 4, 30, 7), distanceM: 5000),
          _run(startedAt: DateTime(2026, 5, 1, 6), distanceM: 8000),
        ],
        view: MileageView.monthly,
        now: now,
      );
      expect(out, hasLength(2));
      expect(out[0].label, "Apr '26");
      expect(out[1].label, "May '26");
    });
  });

  group('aggregateMileage — yearly', () {
    test('groups same-year runs into one bucket', () {
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2025, 1, 5, 7), distanceM: 12000),
          _run(startedAt: DateTime(2025, 12, 31, 6), distanceM: 8000),
        ],
        view: MileageView.yearly,
        now: now,
      );
      expect(out, hasLength(1));
      expect(out.first.label, '2025');
      expect(out.first.distanceM, 20000);
    });

    test('separates runs across year boundaries', () {
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2024, 6, 1, 7), distanceM: 5000),
          _run(startedAt: DateTime(2025, 6, 1, 7), distanceM: 6000),
          _run(startedAt: DateTime(2026, 6, 1, 7), distanceM: 7000),
        ],
        view: MileageView.yearly,
        now: now,
      );
      expect(out.map((p) => p.label).toList(), ['2024', '2025', '2026']);
    });
  });

  // Reason: a user with all runs in one year used to see a single
  // lonely bar in the yearly view. `padYearlyToMin: true` backfills
  // empty prior-year buckets up to the minimum (5) so the chart
  // reads as a year-over-year trend. Default is false so the
  // pure-aggregation shape stays unchanged for non-rendering callers.
  group('padYearlyToMin (yearly view)', () {
    final padNow = DateTime(2026, 6, 1, 12);

    test('single-year input pads to 5 buckets, ending with that year', () {
      final out = aggregateMileage(
        [_run(startedAt: DateTime(2026, 4, 1), distanceM: 5000)],
        view: MileageView.yearly,
        now: padNow,
        padYearlyToMin: true,
      );
      expect(out.length, 5);
      expect(out.map((p) => p.label).toList(),
          ['2022', '2023', '2024', '2025', '2026']);
      // Only the trailing bucket carries the run's distance.
      expect(out.last.distanceM, 5000);
      for (var i = 0; i < out.length - 1; i++) {
        expect(out[i].distanceM, 0,
            reason: 'Backfilled bucket ${out[i].label} must read 0.');
      }
    });

    test('padding does NOT fire when there are 5+ real years', () {
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2022, 6, 1), distanceM: 1000),
          _run(startedAt: DateTime(2023, 6, 1), distanceM: 2000),
          _run(startedAt: DateTime(2024, 6, 1), distanceM: 3000),
          _run(startedAt: DateTime(2025, 6, 1), distanceM: 4000),
          _run(startedAt: DateTime(2026, 6, 1), distanceM: 5000),
        ],
        view: MileageView.yearly,
        now: padNow,
        padYearlyToMin: true,
      );
      expect(out.length, 5,
          reason: '5 real years should pass through unchanged — padding '
              'guard is `< _kYearlyMinBuckets`, not `<=`.');
      expect(out.map((p) => p.distanceM).toList(),
          [1000, 2000, 3000, 4000, 5000]);
    });

    test('padding does NOT fire on weekly / monthly views', () {
      final weekly = aggregateMileage(
        [_run(startedAt: DateTime(2026, 4, 1), distanceM: 5000)],
        view: MileageView.weekly,
        now: padNow,
        padYearlyToMin: true,
      );
      expect(weekly.length, 1,
          reason: 'Weekly view must ignore padYearlyToMin.');
      final monthly = aggregateMileage(
        [_run(startedAt: DateTime(2026, 4, 1), distanceM: 5000)],
        view: MileageView.monthly,
        now: padNow,
        padYearlyToMin: true,
      );
      expect(monthly.length, 1,
          reason: 'Monthly view must ignore padYearlyToMin.');
    });

    test('padYearlyToMin defaults to false (backwards-compat)', () {
      final out = aggregateMileage(
        [_run(startedAt: DateTime(2026, 4, 1), distanceM: 5000)],
        view: MileageView.yearly,
        now: padNow,
      );
      expect(out.length, 1,
          reason: 'Default-off keeps the pure-aggregation shape so '
              'non-rendering callers (tests, analytics) see the same '
              'output they always have.');
    });
  });
}
