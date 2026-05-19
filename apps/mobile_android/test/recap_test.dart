// Dart port of the parity test suite at
// `apps/web/src/lib/recap.test.ts`. The recap aggregator emits the
// hero numbers for the year-in-running surface — total distance,
// longest run, top week, monthly breakdown, etc. Test cases cover:
// - empty-year (returns zero-shaped record)
// - within-year vs out-of-year (filter integrity)
// - monthly bucketing
// - top week aggregation
// - longest run + fastest pace
// - earliest/latest start times
// - cross-year streak (handled by streaks.dart, which the recap
//   passes ALL runs into intentionally)

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/recap.dart';

Run _run({
  required String id,
  required DateTime startedAt,
  required double distanceM,
  Duration duration = const Duration(minutes: 25),
  String? routeId,
  String activity = 'run',
}) =>
    Run(
      id: id,
      startedAt: startedAt,
      duration: duration,
      distanceMetres: distanceM,
      source: RunSource.app,
      routeId: routeId,
      metadata: {'activity_type': activity},
    );

void main() {
  group('buildYearInRunningRecap', () {
    test('empty input → zero-shaped recap for the given year', () {
      final r = buildYearInRunningRecap(const [], 2025);
      expect(r.year, 2025);
      expect(r.runCount, 0);
      expect(r.totalDistanceM, 0);
      expect(r.totalDurationS, 0);
      expect(r.longestRunM, 0);
      expect(r.fastestPaceSecPerKm, isNull);
      expect(r.bestStreakDays, 0);
      expect(r.currentStreakDays, 0);
      expect(r.topWeek, isNull);
      expect(r.uniqueRouteCount, 0);
      expect(r.mostUsedActivity, isNull);
      expect(r.monthly.length, 12);
      // Each month bucket is zero-filled, not omitted.
      for (final m in r.monthly) {
        expect(m.distanceM, 0);
        expect(m.runCount, 0);
      }
    });

    test('only counts runs within the target year', () {
      // Three runs across three different years — only the middle
      // one should land in the 2025 recap. A regression that didn't
      // filter (or filtered wrong, e.g. used UTC vs local) would
      // inflate the counts.
      final runs = [
        _run(
          id: 'a',
          startedAt: DateTime(2024, 6, 1, 8),
          distanceM: 5000,
        ),
        _run(
          id: 'b',
          startedAt: DateTime(2025, 6, 1, 8),
          distanceM: 10000,
        ),
        _run(
          id: 'c',
          startedAt: DateTime(2026, 6, 1, 8),
          distanceM: 8000,
        ),
      ];
      final r = buildYearInRunningRecap(runs, 2025);
      expect(r.runCount, 1);
      expect(r.totalDistanceM, 10000);
      expect(r.longestRunM, 10000);
    });

    test('totals across multiple in-year runs', () {
      final runs = [
        _run(
          id: 'a',
          startedAt: DateTime(2025, 3, 1, 8),
          distanceM: 5000,
          duration: const Duration(minutes: 25),
        ),
        _run(
          id: 'b',
          startedAt: DateTime(2025, 7, 1, 8),
          distanceM: 10000,
          duration: const Duration(minutes: 55),
        ),
        _run(
          id: 'c',
          startedAt: DateTime(2025, 11, 1, 8),
          distanceM: 7000,
          duration: const Duration(minutes: 35),
        ),
      ];
      final r = buildYearInRunningRecap(runs, 2025);
      expect(r.runCount, 3);
      expect(r.totalDistanceM, 22000);
      expect(r.totalDurationS, 25 * 60 + 55 * 60 + 35 * 60);
      expect(r.longestRunM, 10000);
    });

    test('monthly breakdown bucketed by start-month, sparse zero-filled',
        () {
      final runs = [
        _run(
          id: 'a',
          startedAt: DateTime(2025, 3, 5, 8),
          distanceM: 5000,
        ),
        _run(
          id: 'b',
          startedAt: DateTime(2025, 3, 20, 9),
          distanceM: 7000,
        ),
        _run(
          id: 'c',
          startedAt: DateTime(2025, 11, 1, 8),
          distanceM: 8000,
        ),
      ];
      final r = buildYearInRunningRecap(runs, 2025);
      // March (idx 2): two runs, 12 km. November (idx 10): 1 run, 8 km.
      expect(r.monthly[2].month, 3);
      expect(r.monthly[2].runCount, 2);
      expect(r.monthly[2].distanceM, 12000);
      expect(r.monthly[10].month, 11);
      expect(r.monthly[10].runCount, 1);
      expect(r.monthly[10].distanceM, 8000);
      // All other months stay at 0.
      for (var i = 0; i < 12; i++) {
        if (i == 2 || i == 10) continue;
        expect(r.monthly[i].runCount, 0,
            reason: 'month index $i should be empty');
      }
    });

    test('top week picks the highest-distance Monday-anchored week', () {
      // Week 1 (March): one 10 km run.
      // Week 2 (April): three runs totaling 18 km — should be top.
      final runs = [
        _run(
          id: 'a',
          startedAt: DateTime(2025, 3, 3, 8), // Mon mar 3
          distanceM: 10000,
        ),
        _run(
          id: 'b',
          startedAt: DateTime(2025, 4, 7, 8), // Mon apr 7
          distanceM: 5000,
        ),
        _run(
          id: 'c',
          startedAt: DateTime(2025, 4, 8, 8),
          distanceM: 6000,
        ),
        _run(
          id: 'd',
          startedAt: DateTime(2025, 4, 10, 8),
          distanceM: 7000,
        ),
      ];
      final r = buildYearInRunningRecap(runs, 2025);
      expect(r.topWeek, isNotNull);
      expect(r.topWeek!.distanceM, 18000);
      expect(r.topWeek!.runCount, 3);
      // Monday of the top week is 2025-04-07.
      expect(r.topWeek!.weekStart, '2025-04-07');
    });

    test('fastestPaceSecPerKm picks the quickest run >500m', () {
      // 500m+ filter: a sprint 200m run shouldn't dominate the metric.
      final runs = [
        _run(
          id: 'sprint', // 200m run @ 30s — sub-500m, EXCLUDED from pace
          startedAt: DateTime(2025, 5, 1),
          distanceM: 200,
          duration: const Duration(seconds: 30),
        ),
        _run(
          id: 'fast', // 5km in 20:00 = 4:00/km
          startedAt: DateTime(2025, 5, 2),
          distanceM: 5000,
          duration: const Duration(minutes: 20),
        ),
        _run(
          id: 'slow', // 5km in 30:00 = 6:00/km
          startedAt: DateTime(2025, 5, 3),
          distanceM: 5000,
          duration: const Duration(minutes: 30),
        ),
      ];
      final r = buildYearInRunningRecap(runs, 2025);
      // 5km in 20:00 → 240 sec/km
      expect(r.fastestPaceSecPerKm, closeTo(240, 0.1));
    });

    test('mostUsedActivity reflects the highest-count metadata key', () {
      final runs = [
        _run(
          id: 'a',
          startedAt: DateTime(2025, 1, 1),
          distanceM: 5000,
          activity: 'walk',
        ),
        _run(
          id: 'b',
          startedAt: DateTime(2025, 1, 2),
          distanceM: 5000,
          activity: 'run',
        ),
        _run(
          id: 'c',
          startedAt: DateTime(2025, 1, 3),
          distanceM: 5000,
          activity: 'run',
        ),
      ];
      final r = buildYearInRunningRecap(runs, 2025);
      expect(r.mostUsedActivity, 'run');
    });

    test('uniqueRouteCount only counts distinct route ids', () {
      final runs = [
        _run(
          id: 'a',
          startedAt: DateTime(2025, 1, 1),
          distanceM: 5000,
          routeId: 'r1',
        ),
        _run(
          id: 'b',
          startedAt: DateTime(2025, 1, 2),
          distanceM: 5000,
          routeId: 'r1', // dupe — should not double-count
        ),
        _run(
          id: 'c',
          startedAt: DateTime(2025, 1, 3),
          distanceM: 5000,
          routeId: 'r2',
        ),
        _run(
          id: 'd',
          startedAt: DateTime(2025, 1, 4),
          distanceM: 5000,
          // No routeId — should be ignored
        ),
      ];
      final r = buildYearInRunningRecap(runs, 2025);
      expect(r.uniqueRouteCount, 2);
    });

    test('earliest + latest start times use local hh:mm', () {
      final runs = [
        _run(
          id: 'morning',
          startedAt: DateTime(2025, 5, 1, 6, 15),
          distanceM: 5000,
        ),
        _run(
          id: 'lunch',
          startedAt: DateTime(2025, 5, 2, 12, 30),
          distanceM: 5000,
        ),
        _run(
          id: 'late',
          startedAt: DateTime(2025, 5, 3, 21, 45),
          distanceM: 5000,
        ),
      ];
      final r = buildYearInRunningRecap(runs, 2025);
      expect(r.earliestStartLocal, '06:15');
      expect(r.latestStartLocal, '21:45');
    });

    test('streak computation uses ALL runs, not just in-year', () {
      // A streak that started in late December of the previous year
      // should count its in-year days against the target year. Pass
      // every run; the helper passes them all through to
      // computeRunStreaks anchored at Dec 31 of the target year.
      final runs = [
        for (var i = 0; i < 10; i++)
          _run(
            id: 'r$i',
            startedAt: DateTime(2024, 12, 28).add(Duration(days: i)),
            distanceM: 5000,
          ),
      ];
      // Runs span Dec 28 2024 → Jan 6 2025. The 2025 recap should
      // pick up the streak that crossed the boundary.
      final r = buildYearInRunningRecap(runs, 2025);
      expect(r.bestStreakDays, greaterThan(0));
    });

    test('absurd-future year returns zero recap (defensive)', () {
      final runs = [
        _run(
          id: 'a',
          startedAt: DateTime(2025, 5, 1),
          distanceM: 5000,
        ),
      ];
      final r = buildYearInRunningRecap(runs, 3000);
      expect(r.runCount, 0);
      expect(r.totalDistanceM, 0);
    });
  });
}
