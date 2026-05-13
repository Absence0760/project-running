/// Pure run-streak computation. A "streak" is a sequence of
/// consecutive *local* days that each contain at least one run.
///
/// Strava-style grace rule: a missing today does not break the
/// streak — the streak continues to count as long as yesterday had a
/// run. The streak only resets when a full day goes by without one.
///
/// Mirrors `apps/web/src/lib/streaks.ts`. Keep in lockstep — the
/// shared-library-syncer agent watches the pair.

class RunStreaks {
  /// Days in the user's current active streak (0 if broken).
  final int current;

  /// Longest historical streak (>= current).
  final int best;

  const RunStreaks({required this.current, required this.best});

  @override
  bool operator ==(Object other) =>
      other is RunStreaks && other.current == current && other.best == best;

  @override
  int get hashCode => Object.hash(current, best);

  @override
  String toString() => 'RunStreaks(current: $current, best: $best)';
}

/// Local YYYY-MM-DD key for the given `DateTime`.
String _localDayKey(DateTime d) {
  final local = d.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Walk one local day backwards from `d`. DST-safe via the
/// year/month/day constructor (subtracting 24 hours would skew on
/// the spring/fall transitions).
DateTime _previousLocalDay(DateTime d) {
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day - 1);
}

/// Compute `{ current, best }` from a list of run start timestamps.
///
/// [runStarts] are the runs' `started_at` instants. Order doesn't
/// matter — the helper bucketises by local day and dedupes.
/// [today] anchors "current" (usually `DateTime.now()`). Future-dated
/// runs are clamped to <= today's local date.
RunStreaks computeRunStreaks(List<DateTime> runStarts, DateTime today) {
  if (runStarts.isEmpty) return const RunStreaks(current: 0, best: 0);

  final todayKey = _localDayKey(today);

  final dayKeys = <String>{};
  for (final r in runStarts) {
    final k = _localDayKey(r);
    if (k.compareTo(todayKey) <= 0) dayKeys.add(k);
  }
  if (dayKeys.isEmpty) return const RunStreaks(current: 0, best: 0);

  final sortedKeys = dayKeys.toList()..sort();

  // Best streak — walk the sorted set, increment on consecutive days,
  // reset on gap, track max.
  var best = 1;
  var run = 1;
  for (var i = 1; i < sortedKeys.length; i++) {
    final prev = sortedKeys[i - 1];
    final here = sortedKeys[i];
    final parts = prev.split('-').map(int.parse).toList();
    final expected =
        _localDayKey(DateTime(parts[0], parts[1], parts[2] + 1));
    if (here == expected) {
      run += 1;
      if (run > best) best = run;
    } else {
      run = 1;
    }
  }

  // Current streak — walk back from today. Strava grace: if today
  // has no run, start counting from yesterday.
  final localToday = today.toLocal();
  var anchor = DateTime(localToday.year, localToday.month, localToday.day);
  if (!dayKeys.contains(_localDayKey(anchor))) {
    anchor = _previousLocalDay(anchor);
    if (!dayKeys.contains(_localDayKey(anchor))) {
      return RunStreaks(current: 0, best: best);
    }
  }
  var current = 0;
  while (dayKeys.contains(_localDayKey(anchor))) {
    current += 1;
    anchor = _previousLocalDay(anchor);
  }
  return RunStreaks(current: current, best: best);
}
