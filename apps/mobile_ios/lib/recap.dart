/// "Year in running" recap — pure aggregator. Mobile twin of
/// `apps/web/src/lib/runs/recap.ts`; keep in lockstep (algorithm, edge
/// cases, outputs, test counts).
///
/// Takes a year's (or month's) worth of `Run` rows and emits the headline
/// numbers a wrap-up card needs: total distance, total runs, total time,
/// top week, longest run, longest streak, monthly breakdown, the earned
/// trophy grid, and the photo / personal-record counts the page supplies.

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

/// A "trophy" earned over the period — the Strava-Year-in-Sport-style
/// badge grid. Derived purely from the aggregate (plus the optional photo /
/// personal-record counts the page supplies). Only *earned* badges are
/// emitted; at most one per category (the highest tier reached).
class RecapBadge {
  final String id;
  final String icon; // material-symbols glyph name
  final String label;
  final String detail;

  const RecapBadge({
    required this.id,
    required this.icon,
    required this.label,
    required this.detail,
  });
}

/// Counts the recap can't derive from `Run` rows alone — the page fetches
/// them and passes them in. Both default to 0 so the pure aggregate still
/// works standalone.
class RecapExtras {
  final int photoCount;
  final int personalRecordCount;

  const RecapExtras({this.photoCount = 0, this.personalRecordCount = 0});
}

class YearInRunningRecap {
  final int year;

  /// Present only on a monthly recap (1-based). Null on the annual card.
  final int? month;
  final int runCount;
  final double totalDistanceM;
  final int totalDurationS;
  final double totalElevationM;
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
  final int photoCount;
  final int personalRecordCount;
  final List<RecapBadge> badges;

  const YearInRunningRecap({
    required this.year,
    this.month,
    required this.runCount,
    required this.totalDistanceM,
    required this.totalDurationS,
    required this.totalElevationM,
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
    required this.photoCount,
    required this.personalRecordCount,
    required this.badges,
  });
}

/// Inputs the badge tiers read, gathered once during the build.
class _BadgeInputs {
  final double totalDistanceM;
  final int runCount;
  final int bestStreakDays;
  final double totalElevationM;
  final double longestRunM;
  final int activeMonths;
  final int distinctActivities;
  final String? earliestStartLocal;
  final String? latestStartLocal;
  final int photoCount;
  final int personalRecordCount;

  const _BadgeInputs({
    required this.totalDistanceM,
    required this.runCount,
    required this.bestStreakDays,
    required this.totalElevationM,
    required this.longestRunM,
    required this.activeMonths,
    required this.distinctActivities,
    required this.earliestStartLocal,
    required this.latestStartLocal,
    required this.photoCount,
    required this.personalRecordCount,
  });
}

class _BadgeTier {
  final bool when;
  final String id;
  final String icon;
  final String label;
  final String detail;
  const _BadgeTier(this.when, this.id, this.icon, this.label, this.detail);
}

/// Earned-only trophy grid. Each category lists tiers high→low; the first
/// threshold met wins, so a 1,200 km year shows "1,000 km club", not three
/// distance badges. Pure + deterministic so it's unit-testable. Mirror of
/// `computeRecapBadges` in `recap.ts`.
List<RecapBadge> computeRecapBadges(_BadgeInputs i) {
  final out = <RecapBadge>[];
  final km = i.totalDistanceM / 1000;
  void pick(List<_BadgeTier> tiers) {
    for (final t in tiers) {
      if (t.when) {
        out.add(RecapBadge(id: t.id, icon: t.icon, label: t.label, detail: t.detail));
        return;
      }
    }
  }

  pick([
    _BadgeTier(km >= 2000, 'dist-2000', 'public', '2,000 km', 'Halfway round the planet'),
    _BadgeTier(km >= 1000, 'dist-1000', 'public', '1,000 km club', 'A four-figure year'),
    _BadgeTier(km >= 500, 'dist-500', 'route', '500 km', 'Serious mileage'),
    _BadgeTier(km >= 100, 'dist-100', 'route', 'Century', '100 km on the year'),
  ]);
  pick([
    _BadgeTier(i.runCount >= 200, 'runs-200', 'sprint', '200 runs', 'Almost every other day'),
    _BadgeTier(i.runCount >= 100, 'runs-100', 'sprint', 'Centurion', '100 runs logged'),
    _BadgeTier(i.runCount >= 50, 'runs-50', 'sprint', '50 runs', 'A steady habit'),
  ]);
  pick([
    _BadgeTier(i.longestRunM >= 50000, 'long-ultra', 'military_tech', 'Ultra', '50 km+ in one run'),
    _BadgeTier(i.longestRunM >= 42195, 'long-marathon', 'military_tech', 'Marathon', '42.2 km in one run'),
    _BadgeTier(i.longestRunM >= 21097, 'long-half', 'military_tech', 'Half marathon', '21.1 km in one run'),
  ]);
  pick([
    _BadgeTier(i.bestStreakDays >= 30, 'streak-30', 'local_fire_department', 'Month-long streak', '${i.bestStreakDays} days in a row'),
    _BadgeTier(i.bestStreakDays >= 14, 'streak-14', 'local_fire_department', 'Fortnight streak', '${i.bestStreakDays} days in a row'),
    _BadgeTier(i.bestStreakDays >= 7, 'streak-7', 'local_fire_department', 'Week streak', '${i.bestStreakDays} days in a row'),
  ]);
  pick([
    _BadgeTier(i.totalElevationM >= 8849, 'elev-everest', 'terrain', 'Everested', 'Climbed an Everest'),
    _BadgeTier(i.totalElevationM >= 5000, 'elev-5000', 'terrain', '5,000 m climbed', 'Vertical year'),
  ]);
  pick([
    _BadgeTier(i.activeMonths >= 12, 'months-12', 'calendar_month', 'Every month', 'Active all 12 months'),
    _BadgeTier(i.activeMonths >= 6, 'months-6', 'calendar_month', 'Half the year', 'Active in ${i.activeMonths} months'),
  ]);
  pick([
    _BadgeTier(i.personalRecordCount >= 5, 'pr-5', 'trophy', 'Record breaker', '${i.personalRecordCount} personal records'),
    _BadgeTier(i.personalRecordCount >= 1, 'pr-1', 'trophy', 'New PR', '${i.personalRecordCount} personal record${i.personalRecordCount == 1 ? '' : 's'}'),
  ]);
  pick([
    _BadgeTier(i.photoCount >= 25, 'photo-25', 'photo_camera', 'Storyteller', '${i.photoCount} run photos'),
    _BadgeTier(i.photoCount >= 1, 'photo-1', 'photo_camera', 'Documented', '${i.photoCount} run photo${i.photoCount == 1 ? '' : 's'}'),
  ]);
  pick([
    _BadgeTier(i.distinctActivities >= 3, 'variety', 'category', 'All-rounder', '${i.distinctActivities} activity types'),
  ]);
  pick([
    _BadgeTier(i.earliestStartLocal != null && i.earliestStartLocal!.compareTo('06:00') < 0, 'early', 'wb_twilight', 'Early bird', 'First steps at ${i.earliestStartLocal}'),
  ]);
  pick([
    _BadgeTier(i.latestStartLocal != null && i.latestStartLocal!.compareTo('21:00') >= 0, 'night', 'bedtime', 'Night owl', 'Out at ${i.latestStartLocal}'),
  ]);

  return out;
}

/// Monday of the local week as a YYYY-MM-DD string.
String _mondayOf(DateTime d) {
  final local = DateTime(d.year, d.month, d.day);
  final dow = (local.weekday + 6) % 7; // 0=Mon, 6=Sun (matches JS)
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
  final m = r.metadata;
  if (m == null) return 0;
  final raw = m['elevation_m'];
  if (raw is num) return raw.toDouble();
  return 0;
}

/// Build the year-in-running aggregate. Pass ALL runs, not just the
/// target year — internal filter lets the streak computation extend
/// across the year boundary.
YearInRunningRecap buildYearInRunningRecap(
  List<Run> runs,
  int year, [
  RecapExtras extras = const RecapExtras(),
]) {
  final inYear = <Run>[];
  for (final r in runs) {
    // Classify by the run's *local* calendar year — the per-month / per-week
    // breakdown below all works off `startedAt.toLocal()`, so filtering on the
    // raw UTC year would misfile a New Year's Eve evening run into the wrong
    // recap.
    if (r.startedAt.toLocal().year == year) inYear.add(r);
  }

  double totalDistance = 0;
  int totalDuration = 0;
  double totalElevation = 0;
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
    totalElevation += _elevationOf(r);

    // "Longest run" + "fastest pace" are run-family headline stats — exclude
    // cycling so a single long, fast bike ride doesn't masquerade as the
    // year's longest run / fastest pace. (Totals + most-used-activity stay
    // all-inclusive.)
    final isRunFamily = ((r.metadata?['activity_type'] as String?) ?? 'run') != 'cycle';
    if (isRunFamily && r.distanceMetres > longest) longest = r.distanceMetres;

    if (isRunFamily && r.distanceMetres > 500 && r.duration.inSeconds > 0) {
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

    final activity = (r.metadata?['activity_type'] as String?) ?? 'run';
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

  final photoCount = extras.photoCount < 0 ? 0 : extras.photoCount;
  final personalRecordCount =
      extras.personalRecordCount < 0 ? 0 : extras.personalRecordCount;
  final earliestStartLocal = earliestRun == null ? null : _hhmm(earliestRun);
  final latestStartLocal = latestRun == null ? null : _hhmm(latestRun);

  final badges = computeRecapBadges(_BadgeInputs(
    totalDistanceM: totalDistance,
    runCount: inYear.length,
    bestStreakDays: streaks.best,
    totalElevationM: totalElevation,
    longestRunM: longest,
    activeMonths: monthlyList.where((m) => m.runCount > 0).length,
    distinctActivities: activityCounts.length,
    earliestStartLocal: earliestStartLocal,
    latestStartLocal: latestStartLocal,
    photoCount: photoCount,
    personalRecordCount: personalRecordCount,
  ));

  return YearInRunningRecap(
    year: year,
    runCount: inYear.length,
    totalDistanceM: totalDistance,
    totalDurationS: totalDuration,
    totalElevationM: totalElevation,
    bestStreakDays: streaks.best,
    currentStreakDays: streaks.current,
    longestRunM: longest,
    fastestPaceSecPerKm: fastestPace,
    earliestStartLocal: earliestStartLocal,
    latestStartLocal: latestStartLocal,
    monthly: monthlyList,
    topWeek: topWeek,
    uniqueRouteCount: uniqueRoutes.length,
    mostUsedActivity: mostUsedActivity,
    photoCount: photoCount,
    personalRecordCount: personalRecordCount,
    badges: badges,
  );
}

/// Monthly recap — same engine, one calendar month. Reuses
/// `buildYearInRunningRecap` over the whole run set and projects out the
/// single requested month. `month` is 1-based. Mirror of
/// `buildMonthInRunningRecap` in `recap.ts`.
YearInRunningRecap buildMonthInRunningRecap(
  List<Run> runs,
  int year,
  int month, [
  RecapExtras extras = const RecapExtras(),
]) {
  final yearRecap = buildYearInRunningRecap(runs, year, extras);
  final bucket = (month >= 1 && month <= 12)
      ? yearRecap.monthly[month - 1]
      : RecapMonthBucket(month: month, distanceM: 0, durationS: 0, runCount: 0);

  final inMonth = <Run>[];
  for (final r in runs) {
    final d = r.startedAt.toLocal();
    if (d.year == year && d.month == month) inMonth.add(r);
  }

  double totalElevation = 0;
  double longest = 0;
  double? fastestPace;
  int? earliestMin;
  int? latestMin;
  DateTime? earliestRun;
  DateTime? latestRun;
  final activityCounts = <String, int>{};
  final weeklyTotals = <String, _WeekAccum>{};
  final uniqueRoutes = <String>{};

  for (final r in inMonth) {
    final d = r.startedAt.toLocal();
    totalElevation += _elevationOf(r);
    final isRunFamily = ((r.metadata?['activity_type'] as String?) ?? 'run') != 'cycle';
    if (isRunFamily && r.distanceMetres > longest) longest = r.distanceMetres;
    if (isRunFamily && r.distanceMetres > 500 && r.duration.inSeconds > 0) {
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
    final wk = _mondayOf(d);
    final w = weeklyTotals.putIfAbsent(wk, _WeekAccum.new);
    w.distance += r.distanceMetres;
    w.runCount += 1;
    if (r.routeId != null) uniqueRoutes.add(r.routeId!);
    final activity = (r.metadata?['activity_type'] as String?) ?? 'run';
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

  // Last day of this month = day 0 of next month.
  final endOfMonth = DateTime(year, month + 1, 0, 23, 59);
  final streaks = computeRunStreaks(
    runs.map((r) => r.startedAt).toList(),
    endOfMonth,
  );

  final photoCount = extras.photoCount < 0 ? 0 : extras.photoCount;
  final personalRecordCount =
      extras.personalRecordCount < 0 ? 0 : extras.personalRecordCount;
  final earliestStartLocal = earliestRun == null ? null : _hhmm(earliestRun);
  final latestStartLocal = latestRun == null ? null : _hhmm(latestRun);

  final badges = computeRecapBadges(_BadgeInputs(
    totalDistanceM: bucket.distanceM,
    runCount: bucket.runCount,
    bestStreakDays: streaks.best,
    totalElevationM: totalElevation,
    longestRunM: longest,
    activeMonths: bucket.runCount > 0 ? 1 : 0,
    distinctActivities: activityCounts.length,
    earliestStartLocal: earliestStartLocal,
    latestStartLocal: latestStartLocal,
    photoCount: photoCount,
    personalRecordCount: personalRecordCount,
  ));

  return YearInRunningRecap(
    year: year,
    month: month,
    runCount: bucket.runCount,
    totalDistanceM: bucket.distanceM,
    totalDurationS: bucket.durationS,
    totalElevationM: totalElevation,
    bestStreakDays: streaks.best,
    currentStreakDays: streaks.current,
    longestRunM: longest,
    fastestPaceSecPerKm: fastestPace,
    earliestStartLocal: earliestStartLocal,
    latestStartLocal: latestStartLocal,
    monthly: yearRecap.monthly,
    topWeek: topWeek,
    uniqueRouteCount: uniqueRoutes.length,
    mostUsedActivity: mostUsedActivity,
    photoCount: photoCount,
    personalRecordCount: personalRecordCount,
    badges: badges,
  );
}

/// Serialise a recap into the frozen-snapshot jsonb the `public_recaps`
/// table stores — the SAME field shape the web `YearInRunningRecap` carries,
/// so the web share page + og:image render a mobile-published recap
/// identically. Aggregate-only (no GPS, no per-run rows).
Map<String, dynamic> recapSnapshotJson(YearInRunningRecap r) => {
      'year': r.year,
      if (r.month != null) 'month': r.month,
      'runCount': r.runCount,
      'totalDistanceM': r.totalDistanceM,
      'totalDurationS': r.totalDurationS,
      'totalElevationM': r.totalElevationM,
      'longestRunM': r.longestRunM,
      'fastestPaceSecPerKm': r.fastestPaceSecPerKm,
      'bestStreakDays': r.bestStreakDays,
      'currentStreakDays': r.currentStreakDays,
      'earliestStartLocal': r.earliestStartLocal,
      'latestStartLocal': r.latestStartLocal,
      'monthly': [
        for (final m in r.monthly)
          {
            'month': m.month,
            'distanceM': m.distanceM,
            'durationS': m.durationS,
            'runCount': m.runCount,
          },
      ],
      'topWeek': r.topWeek == null
          ? null
          : {
              'weekStart': r.topWeek!.weekStart,
              'distanceM': r.topWeek!.distanceM,
              'runCount': r.topWeek!.runCount,
            },
      'uniqueRouteCount': r.uniqueRouteCount,
      'mostUsedActivity': r.mostUsedActivity,
      'photoCount': r.photoCount,
      'personalRecordCount': r.personalRecordCount,
      'badges': [
        for (final b in r.badges)
          {'id': b.id, 'icon': b.icon, 'label': b.label, 'detail': b.detail},
      ],
    };

/// Smallish utility for the share-card copy. Mirror of `recapHeadline`.
String recapHeadline(YearInRunningRecap recap, String kmOrMi) {
  if (recap.runCount == 0) return 'No runs in ${recap.year} yet.';
  final total = kmOrMi == 'mi'
      ? '${(recap.totalDistanceM / 1609.344).round()} mi'
      : '${(recap.totalDistanceM / 1000).round()} km';
  return '${recap.year}: $total across ${recap.runCount} runs.';
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
