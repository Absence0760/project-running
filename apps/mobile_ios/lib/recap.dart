/// "Year in running" recap — pure aggregator. Mobile twin of
/// `apps/web/src/lib/recap.ts`; keep in lockstep.
///
/// Takes a year's worth of `Run` rows and emits the headline numbers
/// a wrap-up card needs: total distance, total runs, total time,
/// top week, longest run, longest streak, monthly breakdown.

import 'package:core_models/core_models.dart';

import 'streaks.dart';

class RecapMonthBucket {
  final int month; // 1-based (1=Jan … 12=Dec)
  final double distanceM;
  final int durationS;
  final int runCount;

  const RecapMonthBucket({
    required this.month,
    required this.distanceM,
    required this.durationS,
    required this.runCount,
  });
}

class RecapWeekTop {
  final String weekStart; // YYYY-MM-DD Monday
  final double distanceM;
  final int runCount;

  const RecapWeekTop({
    required this.weekStart,
    required this.distanceM,
    required this.runCount,
  });
}

class YearInRunningRecap {
  final int year;
  final int runCount;
  final double totalDistanceM;
  final int totalDurationS;
  final int bestStreakDays;
  final int currentStreakDays;
  final double longestRunM;
  final double? fastestPaceSecPerKm;
  final String? earliestStartLocal; // hh:mm
  final String? latestStartLocal;
  final List<RecapMonthBucket> monthly; // length 12
  final RecapWeekTop? topWeek;
  final int uniqueRouteCount;
  final String? mostUsedActivity;

  const YearInRunningRecap({
    required this.year,
    required this.runCount,
    required this.totalDistanceM,
    required this.totalDurationS,
    required this.bestStreakDays,
    required this.currentStreakDays,
    required this.longestRunM,
    required this.fastestPaceSecPerKm,
    required this.earliestStartLocal,
    required this.latestStartLocal,
    required this.monthly,
    required this.topWeek,
    required this.uniqueRouteCount,
    required this.mostUsedActivity,
  });
}

/// Monday of the local week as a YYYY-MM-DD string.
String _mondayOf(DateTime d) {
  final local = DateTime(d.year, d.month, d.day);
  final dow = (local.weekday + 6) % 7; // 0=Mon, 6=Sun (matches JS)
  // Actually weekday in Dart: Mon=1, Sun=7. So (weekday - 1) gives
  // 0=Mon, 6=Sun. The (weekday + 6) % 7 form would be 0 for Mon (1)
  // which matches. Both work. Keep the bitshift-style for parity
  // with the web ts.
  final mon = local.subtract(Duration(days: dow));
  final y = mon.year.toString().padLeft(4, '0');
  final m = mon.month.toString().padLeft(2, '0');
  final day = mon.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

double _elevationOf(Run r) {
  // Run.metadata.elevation_m is the canonical key (jsonb).
  // audit/metadata-keys (May 2026) dropped the `elevation_gain_m`
  // fallback: no writer in the codebase ever set it, the key was
  // not registered in docs/backend/metadata.md, and the fallback branch was
  // dead code that confused dead-key audits.
  final m = r.metadata;
  if (m == null) return 0;
  final raw = m['elevation_m'];
  if (raw is num) return raw.toDouble();
  return 0;
}

/// Build the year-in-running aggregate. Pass ALL runs, not just
/// the target year — internal filter lets the streak computation
/// extend across the year boundary.
YearInRunningRecap buildYearInRunningRecap(List<Run> runs, int year) {
  final inYear = <Run>[];
  for (final r in runs) {
    // Classify by the run's *local* calendar year — the per-month / per-week
    // breakdown below all works off `startedAt.toLocal()`, so filtering on the
    // raw UTC year would misfile a New Year's Eve evening run (UTC next-year)
    // into the wrong recap.
    if (r.startedAt.toLocal().year == year) inYear.add(r);
  }

  double totalDistance = 0;
  int totalDuration = 0;
  double longest = 0;
  double? fastestPace;
  int? earliestMin;
  int? latestMin;
  DateTime? earliestRun;
  DateTime? latestRun;

  final activityCounts = <String, int>{};
  final monthly = <int, _MonthAccum>{
    for (var i = 1; i <= 12; i++) i: _MonthAccum(),
  };
  final weeklyTotals = <String, _WeekAccum>{};
  final uniqueRoutes = <String>{};

  for (final r in inYear) {
    final d = r.startedAt.toLocal();
    totalDistance += r.distanceMetres;
    totalDuration += r.duration.inSeconds;
    _elevationOf(r); // tally exists if future fields land here
    if (r.distanceMetres > longest) longest = r.distanceMetres;

    if (r.distanceMetres > 500 && r.duration.inSeconds > 0) {
      final pace = r.duration.inSeconds / (r.distanceMetres / 1000);
      if (fastestPace == null || pace < fastestPace) fastestPace = pace;
    }

    final startMin = d.hour * 60 + d.minute;
    if (earliestMin == null || startMin < earliestMin) {
      earliestMin = startMin;
      earliestRun = d;
    }
    if (latestMin == null || startMin > latestMin) {
      latestMin = startMin;
      latestRun = d;
    }

    final md = monthly[d.month]!;
    md.distance += r.distanceMetres;
    md.duration += r.duration.inSeconds;
    md.runCount += 1;

    final wk = _mondayOf(d);
    final w = weeklyTotals.putIfAbsent(wk, _WeekAccum.new);
    w.distance += r.distanceMetres;
    w.runCount += 1;

    if (r.routeId != null) uniqueRoutes.add(r.routeId!);

    final activity =
        (r.metadata?['activity_type'] as String?) ?? 'run';
    activityCounts[activity] = (activityCounts[activity] ?? 0) + 1;
  }

  RecapWeekTop? topWeek;
  weeklyTotals.forEach((weekStart, w) {
    if (topWeek == null || w.distance > topWeek!.distanceM) {
      topWeek = RecapWeekTop(
        weekStart: weekStart,
        distanceM: w.distance,
        runCount: w.runCount,
      );
    }
  });

  String? mostUsedActivity;
  activityCounts.forEach((name, count) {
    if (mostUsedActivity == null ||
        count > (activityCounts[mostUsedActivity] ?? 0)) {
      mostUsedActivity = name;
    }
  });

  final endOfYear = DateTime(year, 12, 31, 23, 59);
  final streaks = computeRunStreaks(
    runs.map((r) => r.startedAt).toList(),
    endOfYear,
  );

  final monthlyList = <RecapMonthBucket>[
    for (var i = 1; i <= 12; i++)
      RecapMonthBucket(
        month: i,
        distanceM: monthly[i]!.distance,
        durationS: monthly[i]!.duration,
        runCount: monthly[i]!.runCount,
      ),
  ];

  return YearInRunningRecap(
    year: year,
    runCount: inYear.length,
    totalDistanceM: totalDistance,
    totalDurationS: totalDuration,
    bestStreakDays: streaks.best,
    currentStreakDays: streaks.current,
    longestRunM: longest,
    fastestPaceSecPerKm: fastestPace,
    earliestStartLocal: earliestRun == null ? null : _hhmm(earliestRun),
    latestStartLocal: latestRun == null ? null : _hhmm(latestRun),
    monthly: monthlyList,
    topWeek: topWeek,
    uniqueRouteCount: uniqueRoutes.length,
    mostUsedActivity: mostUsedActivity,
  );
}

class _MonthAccum {
  double distance = 0;
  int duration = 0;
  int runCount = 0;
}

class _WeekAccum {
  double distance = 0;
  int runCount = 0;
}
