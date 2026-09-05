// Dart port of the parity test suite at
// `apps/web/src/lib/runs/recap.test.ts`. The recap aggregator emits the
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
  double? elevationM,
}) =>
    Run(
      id: id,
      startedAt: startedAt,
      duration: duration,
      distanceMetres: distanceM,
      source: RunSource.app,
      routeId: routeId,
      metadata: {
        'activity_type': activity,
        if (elevationM != null) 'elevation_m': elevationM,
      },
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

    test('a cycle ride is not the fastest pace / longest run', () {
      final runs = [
        _run(
          id: 'run', // 5km @ 5:00/km = 300 s/km
          startedAt: DateTime(2025, 3, 1),
          distanceM: 5000,
          duration: const Duration(minutes: 25),
        ),
        _run(
          id: 'ride', // 40km @ 2:00/km = 120 s/km — faster + longer, but a bike
          startedAt: DateTime(2025, 4, 1),
          distanceM: 40000,
          duration: const Duration(minutes: 80),
          activity: 'cycle',
        ),
      ];
      final r = buildYearInRunningRecap(runs, 2025);
      expect(r.fastestPaceSecPerKm, closeTo(300, 0.1)); // the run, not the bike
      expect(r.longestRunM, 5000); // the run, not the bike
      expect(r.totalDistanceM, 45000); // totals stay all-inclusive
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
      // computeRunStreaks anchored at Dec 31 of the target year (a past
      // year here, so the anchor is not clamped to now).
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

    test('elevation totals sum the metadata.elevation_m key, falling back to 0',
        () {
      final runs = [
        _run(id: 'a', startedAt: DateTime(2025, 2, 1), distanceM: 5000),
        _run(
          id: 'b',
          startedAt: DateTime(2025, 2, 2),
          distanceM: 5000,
          elevationM: 50,
        ),
      ];
      final r = buildYearInRunningRecap(runs, 2025);
      expect(r.totalElevationM, 50);
    });

    test('a non-finite elevation contributes nothing rather than poisoning the '
        'total', () {
      // The bag is schemaless jsonb; `raw is num` admits a NaN the way the TS
      // half's `Number.isFinite` does not, and one such run would take every
      // other run's climb in the year down with it.
      final runs = [
        _run(
          id: 'a',
          startedAt: DateTime(2025, 2, 1),
          distanceM: 5000,
          elevationM: double.nan,
        ),
        _run(
          id: 'b',
          startedAt: DateTime(2025, 2, 2),
          distanceM: 5000,
          elevationM: 50,
        ),
      ];
      expect(buildYearInRunningRecap(runs, 2025).totalElevationM, 50);
    });

    test('zero runs → null earliest + latest start', () {
      final r = buildYearInRunningRecap(const [], 2025);
      expect(r.earliestStartLocal, isNull);
      expect(r.latestStartLocal, isNull);
    });
  });

  group('extras + badges', () {
    test('extras default to 0 and emit no photo / PR badge', () {
      final r = buildYearInRunningRecap(
        [_run(id: 'a', startedAt: DateTime(2025, 3, 1), distanceM: 5000)],
        2025,
      );
      expect(r.photoCount, 0);
      expect(r.personalRecordCount, 0);
      expect(r.badges.any((b) => b.id.startsWith('photo')), isFalse);
      expect(r.badges.any((b) => b.id.startsWith('pr')), isFalse);
    });

    test('extras surface photo + PR counts and the highest badge tier', () {
      final r = buildYearInRunningRecap(
        [_run(id: 'a', startedAt: DateTime(2025, 3, 1), distanceM: 5000)],
        2025,
        const RecapExtras(photoCount: 30, personalRecordCount: 6),
      );
      expect(r.photoCount, 30);
      expect(r.personalRecordCount, 6);
      expect(r.badges.firstWhere((b) => b.id.startsWith('photo')).id, 'photo-25');
      expect(r.badges.firstWhere((b) => b.id.startsWith('pr')).id, 'pr-5');
    });

    test('negative extras are clamped to a non-negative int', () {
      final r = buildYearInRunningRecap(
        const [],
        2025,
        const RecapExtras(photoCount: -3, personalRecordCount: 2),
      );
      expect(r.photoCount, 0);
      expect(r.personalRecordCount, 2);
    });

    test('one badge per category — the highest tier reached wins', () {
      // 1,200 km should produce the 1,000 km badge only.
      final runs = [
        for (var i = 0; i < 12; i++)
          _run(
            id: 'r$i',
            startedAt: DateTime(2025, (i % 9) + 1, (i % 9) + 1, 10),
            distanceM: 100000,
            duration: const Duration(minutes: 500),
          ),
      ];
      final r = buildYearInRunningRecap(runs, 2025);
      final distBadges =
          r.badges.where((b) => b.id.startsWith('dist-')).toList();
      expect(distBadges.length, 1);
      expect(distBadges.first.id, 'dist-1000');
    });

    test('a marathon-length longest run earns the Marathon trophy', () {
      final r = buildYearInRunningRecap(
        [
          _run(
            id: 'a',
            startedAt: DateTime(2025, 4, 1, 8),
            distanceM: 42300,
            duration: const Duration(hours: 4),
          ),
        ],
        2025,
      );
      expect(r.badges.any((b) => b.id == 'long-marathon'), isTrue);
      expect(r.badges.any((b) => b.id == 'long-ultra'), isFalse);
    });

    test('an early start before 06:00 earns the Early bird trophy', () {
      final r = buildYearInRunningRecap(
        [_run(id: 'a', startedAt: DateTime(2025, 5, 1, 5, 15), distanceM: 5000)],
        2025,
      );
      expect(r.badges.any((b) => b.id == 'early'), isTrue);
      expect(r.badges.any((b) => b.id == 'night'), isFalse);
    });

    test('an empty year earns no trophies', () {
      final r = buildYearInRunningRecap(const [], 2025);
      expect(r.badges.length, 0);
    });
  });

  group('recapHeadline', () {
    test('km vs mi switches the unit string', () {
      final recap = buildYearInRunningRecap(
        [
          _run(
            id: 'a',
            startedAt: DateTime(2025, 1, 1, 10),
            distanceM: 1609344,
            duration: const Duration(seconds: 540000),
          ),
        ],
        2025,
      );
      expect(recapHeadline(recap, 'km'), '2025: 1609 km across 1 runs.');
      expect(recapHeadline(recap, 'mi'), '2025: 1000 mi across 1 runs.');
    });

    test('empty recap shows the "no runs" string', () {
      final recap = buildYearInRunningRecap(const [], 2025);
      expect(recapHeadline(recap, 'km'), 'No runs in 2025 yet.');
    });
  });

  group('buildMonthInRunningRecap', () {
    test('projects out a single month', () {
      final runs = [
        _run(
          id: 'a',
          startedAt: DateTime(2025, 3, 5, 10),
          distanceM: 5000,
          duration: const Duration(minutes: 25),
        ),
        _run(
          id: 'b',
          startedAt: DateTime(2025, 3, 20, 10),
          distanceM: 7000,
          duration: const Duration(minutes: 35),
        ),
        _run(
          id: 'c',
          startedAt: DateTime(2025, 6, 1, 10),
          distanceM: 10000,
        ),
      ];
      final r = buildMonthInRunningRecap(runs, 2025, 3);
      expect(r.month, 3);
      expect(r.runCount, 2);
      expect(r.totalDistanceM, 12000);
      expect(r.totalDurationS, 60 * 60);
      expect(r.longestRunM, 7000);
    });

    test('empty month → zeros, keeps the 12-month strip', () {
      final runs = [
        _run(id: 'c', startedAt: DateTime(2025, 6, 1, 10), distanceM: 10000),
      ];
      final r = buildMonthInRunningRecap(runs, 2025, 3);
      expect(r.month, 3);
      expect(r.runCount, 0);
      expect(r.totalDistanceM, 0);
      expect(r.longestRunM, 0);
      expect(r.monthly.length, 12);
      expect(r.monthly[5].distanceM, 10000);
    });

    test('a cycle ride is not the month longest run / fastest pace', () {
      final runs = [
        _run(
          id: 'run',
          startedAt: DateTime(2025, 4, 1, 10),
          distanceM: 5000,
          duration: const Duration(minutes: 25),
        ),
        _run(
          id: 'ride',
          startedAt: DateTime(2025, 4, 2, 10),
          distanceM: 40000,
          duration: const Duration(minutes: 80),
          activity: 'cycle',
        ),
      ];
      final r = buildMonthInRunningRecap(runs, 2025, 4);
      expect(r.longestRunM, 5000);
      expect(r.fastestPaceSecPerKm, closeTo(300, 0.1));
      expect(r.totalDistanceM, 45000);
    });

    test('extras flow through to month badges', () {
      final r = buildMonthInRunningRecap(
        [_run(id: 'a', startedAt: DateTime(2025, 5, 1, 10), distanceM: 5000)],
        2025,
        5,
        const RecapExtras(photoCount: 30, personalRecordCount: 6),
      );
      expect(r.photoCount, 30);
      expect(r.personalRecordCount, 6);
      expect(r.badges.firstWhere((b) => b.id.startsWith('photo')).id, 'photo-25');
      expect(r.badges.firstWhere((b) => b.id.startsWith('pr')).id, 'pr-5');
    });

    test('out-of-range month is zero, never throws', () {
      final r = buildMonthInRunningRecap(
        [_run(id: 'a', startedAt: DateTime(2025, 5, 1, 10), distanceM: 5000)],
        2025,
        13,
      );
      expect(r.runCount, 0);
      expect(r.totalDistanceM, 0);
    });
  });

  group('recapSnapshotJson', () {
    test('serialises the aggregate-only shape the public_recaps table stores', () {
      final r = buildYearInRunningRecap(
        [
          _run(
            id: 'a',
            startedAt: DateTime(2025, 3, 1, 8),
            distanceM: 42300,
            duration: const Duration(hours: 4),
          ),
        ],
        2025,
        const RecapExtras(photoCount: 3, personalRecordCount: 2),
      );
      final json = recapSnapshotJson(r);
      // The field set matches the web YearInRunningRecap so the web share
      // page + og:image render a mobile-published recap identically.
      expect(json['year'], 2025);
      expect(json.containsKey('month'), isFalse); // annual recap → no month key
      expect(json['runCount'], 1);
      expect(json['totalDistanceM'], 42300);
      expect((json['monthly'] as List).length, 12);
      expect(json['badges'], isA<List>());
      // Aggregate-only: no GPS / per-run keys leak into the snapshot.
      expect(json.containsKey('track'), isFalse);
      expect(json.containsKey('runs'), isFalse);
    });

    test('a monthly recap carries the month key', () {
      final r = buildMonthInRunningRecap(
        [_run(id: 'a', startedAt: DateTime(2025, 3, 1, 8), distanceM: 5000)],
        2025,
        3,
      );
      final json = recapSnapshotJson(r);
      expect(json['month'], 3);
    });
  });

  // The flip side of the boundary rule: a streak has to *reach* the period
  // to be the period's streak. computeRunStreaks clamps only at the anchor
  // day, so the whole of the runner's history used to be in scope and a
  // long-dead streak became "your best streak" on a card titled with a year
  // it never touched — and shipped in the published snapshot.
  group('out-of-period streaks', () {
    /// A 40-day streak in early 2024, then a short one inside the period.
    List<Run> staleStreakRuns() => [
          for (var i = 0; i < 40; i++)
            _run(
              id: 'old-$i',
              startedAt: DateTime(2024, 2, 1 + i, 10),
              distanceM: 5000,
            ),
          for (var i = 0; i < 3; i++)
            _run(
              id: 'new-$i',
              startedAt: DateTime(2026, 3, 10 + i, 10),
              distanceM: 5000,
            ),
        ];

    test('a streak from a previous year is not this year\'s best', () {
      final r = buildYearInRunningRecap(staleStreakRuns(), 2026);
      expect(r.runCount, 3);
      expect(r.bestStreakDays, 3,
          reason: 'the 2024 streak must not headline the 2026 card');
    });

    test('an out-of-period streak earns no trophy', () {
      final r = buildYearInRunningRecap(staleStreakRuns(), 2026);
      expect(
        r.badges.where((b) => b.id.startsWith('streak')),
        isEmpty,
        reason: 'a 2024 streak must not put a streak trophy on the 2026 grid',
      );
    });

    test('a year with no runs at all has no streak', () {
      final r = buildYearInRunningRecap(staleStreakRuns(), 2025);
      expect(r.runCount, 0);
      expect(r.bestStreakDays, 0);
      expect(r.currentStreakDays, 0);
    });

    test('a streak from an earlier month is not this month\'s best', () {
      // The 3-day streak sits in March; the April card must not claim it.
      final r = buildMonthInRunningRecap(staleStreakRuns(), 2026, 4);
      expect(r.runCount, 0);
      expect(r.bestStreakDays, 0);
      expect(r.badges.where((b) => b.id.startsWith('streak')), isEmpty);
    });

    test('the month the streak ran in still reports it', () {
      final r = buildMonthInRunningRecap(staleStreakRuns(), 2026, 3);
      expect(r.runCount, 3);
      expect(r.bestStreakDays, 3);
    });

    test('the published snapshot carries the period-bounded streak', () {
      final json = recapSnapshotJson(
        buildYearInRunningRecap(staleStreakRuns(), 2026),
      );
      expect(json['bestStreakDays'], 3);
    });
  });

  // Mirrors `recap.test.ts`'s anchor cases (decisions § 1221 / § 1239). The
  // anchor used to be 31 Dec of the card's year unconditionally, so for the
  // year you are living in the walk looked for a run on 31 Dec, then on its
  // grace day of 30 Dec, found neither, and reported 0 for every live streak.
  group('current-streak anchor', () {
    /// A 4-day streak ending on the stated `now`.
    List<Run> liveStreakRuns() => [
          for (var i = 0; i < 4; i++)
            _run(
              id: 'live-$i',
              startedAt: DateTime(2026, 3, 7 + i, 7),
              distanceM: 5000,
            ),
        ];

    final now = DateTime(2026, 3, 10, 9); // 10 Mar 2026, 09:00 local

    test('the card for the year you are IN reports the live streak', () {
      final r = buildYearInRunningRecap(
          liveStreakRuns(), 2026, const RecapExtras(), now);
      expect(r.currentStreakDays, 4,
          reason: 'a streak running up to and including today is the current '
              'streak');
      expect(r.bestStreakDays, 4);
    });

    test('the grace day keeps a streak alive on a morning before the run', () {
      final r = buildYearInRunningRecap(
          liveStreakRuns().sublist(0, 3), 2026, const RecapExtras(), now);
      expect(r.currentStreakDays, 3);
    });

    /// The web suite's `BOUNDARY_STREAK_DAYS`: a 7-day streak straddling the
    /// year end, four of whose days are in 2025.
    List<Run> boundaryStreakRuns() => [
          for (final d in [
            DateTime(2025, 12, 28, 10),
            DateTime(2025, 12, 29, 10),
            DateTime(2025, 12, 30, 10),
            DateTime(2025, 12, 31, 10),
            DateTime(2026, 1, 1, 10),
            DateTime(2026, 1, 2, 10),
            DateTime(2026, 1, 3, 10),
          ])
            _run(
                id: 'b-${d.year}-${d.month}-${d.day}',
                startedAt: d,
                distanceM: 5000),
        ];

    test('a past year still clamps at its own 31 Dec', () {
      // The 2025 card counts the four days up to its own year end rather than
      // being dragged forward to `now`, and the 2026 half is excluded because
      // it falls after the anchor.
      final r = buildYearInRunningRecap(
          boundaryStreakRuns(), 2025, const RecapExtras(), now);
      expect(r.currentStreakDays, 4);
    });

    test('the month you are IN reports the live streak', () {
      final r = buildMonthInRunningRecap(
          liveStreakRuns(), 2026, 3, const RecapExtras(), now);
      expect(r.currentStreakDays, 4);
    });

    test('a finished month still clamps at its own last day', () {
      final r = buildMonthInRunningRecap(
          boundaryStreakRuns(), 2025, 12, const RecapExtras(), now);
      expect(r.currentStreakDays, 4);
    });

    test('a month already over reports no current streak', () {
      // March 2026 held a streak that ended on the 10th; read from September
      // the anchor is the month's own 31 Mar, two clear days past the last run,
      // so the card reports no live streak rather than the length it had.
      final r = buildMonthInRunningRecap(
          liveStreakRuns(), 2026, 3, const RecapExtras(), DateTime(2026, 9, 5));
      expect(r.currentStreakDays, 0);
      expect(r.bestStreakDays, 4);
    });

    test('recapSnapshotJson carries the live streak, not a zero', () {
      // `recapSnapshotJson` writes `public_recaps`, so the anchor defect made a
      // phone-published snapshot of an in-progress period render a zero on the
      // web share page while the web-built one rendered the real streak.
      final json = recapSnapshotJson(buildYearInRunningRecap(
          liveStreakRuns(), 2026, const RecapExtras(), now));
      expect(json['currentStreakDays'], 4);
    });
  });
}
