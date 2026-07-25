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

  group('back-fill window', () {
    test('the window ends at the bucket containing now, not the last with data',
        () {
      // Idle runner: last logged eight days ago. The card labels the final
      // bucket "this week", so ending on the last bucket WITH DATA reported a
      // stale total as the current one.
      final out = aggregateMileage(
        [_run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 10000)],
        view: MileageView.weekly,
        now: now,
        minBuckets: 3,
      );
      expect(out.last.startsAt, DateTime(2026, 5, 18),
          reason: "the last bar must be now's week (Mon 18 May)");
      expect(out.last.distanceM, 0);
      expect(out.map((p) => p.distanceM), contains(10000));
    });

    test('a run in the current bucket is not duplicated by the anchor', () {
      final out = aggregateMileage(
        [_run(startedAt: DateTime(2026, 5, 19, 7), distanceM: 4000)],
        view: MileageView.weekly,
        now: now,
        minBuckets: 3,
      );
      expect(out.where((p) => p.startsAt == DateTime(2026, 5, 18)), hasLength(1));
      expect(out.last.distanceM, 4000);
    });

    // DST safety. These invariants hold in every timezone, but they can only
    // FAIL in one that observes a transition — CI runs UTC, so the source-level
    // guard in architecture_guards_test.dart is what actually catches a
    // regression. Verified failing under TZ=America/New_York before the fix.
    test('every weekly bucket starts at local midnight on a Monday', () {
      for (final anchor in [
        DateTime(2026, 3, 12, 12), // week after a US spring-forward
        DateTime(2026, 11, 5, 12), // week after a US fall-back
        DateTime(2026, 3, 29, 12), // week of the EU spring-forward
      ]) {
        final out = aggregateMileage(
          const [],
          view: MileageView.weekly,
          now: anchor,
          minBuckets: 5,
        );
        for (final p in out) {
          expect(p.startsAt.hour, 0, reason: '${p.startsAt} is not midnight');
          expect(p.startsAt.minute, 0);
          expect(p.startsAt.weekday, DateTime.monday,
              reason: '${p.startsAt} is not a Monday');
        }
        // Consecutive buckets are exactly one calendar week apart.
        for (var i = 1; i < out.length; i++) {
          final prev = out[i - 1].startsAt;
          expect(out[i].startsAt, DateTime(prev.year, prev.month, prev.day + 7));
        }
      }
    });

    test('a run in a DST transition week lands in that week, exactly once', () {
      for (final day in [DateTime(2026, 3, 8, 3, 30), DateTime(2026, 11, 1, 23, 30)]) {
        final out = aggregateMileage(
          [_run(startedAt: day, distanceM: 6000)],
          view: MileageView.weekly,
          now: DateTime(day.year, day.month, day.day + 3, 12),
          minBuckets: 3,
        );
        final carrying = out.where((p) => p.distanceM == 6000).toList();
        expect(carrying, hasLength(1), reason: 'run at $day was mis-bucketed');
        final start = carrying.single.startsAt;
        expect(start.weekday, DateTime.monday);
        expect(start.isAfter(day), isFalse);
        expect(DateTime(start.year, start.month, start.day + 7).isAfter(day), isTrue);
      }
    });
  });
}
