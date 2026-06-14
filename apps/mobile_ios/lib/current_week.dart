/// Current-calendar-week derivation for the dashboard "This Week" strip.
///
/// Unlike the plan-detail current-week strip (which anchors its 7-day window
/// to the plan's `start_date + week_index*7` so its count matches the week
/// card), this strip is the runner's REAL calendar week — the seven days of
/// the week that contains `now`, starting on the user's `week_start` pref —
/// with each day's logged-activity distance + count folded in.
///
/// Dart twin of `apps/web/src/lib/training/current_week.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
library;

enum WeekStart { monday, sunday }

/// The minimum an activity needs to expose for the strip: when it happened
/// and how far it went. [startedAt] is an ISO timestamp; [distanceM] is
/// metres. The dashboard feeds its already-fetched runs straight in.
class WeekActivity {
  final String startedAt;
  final double distanceM;
  const WeekActivity({required this.startedAt, required this.distanceM});
}

/// One day of the strip. [iso] is the local `yyyy-mm-dd` date; [dow] is the
/// JS day-of-week (0 = Sunday) so the caller can index its localized weekday
/// labels; [distanceM] / [count] aggregate the day's activities; [isToday] /
/// [isFuture] drive the cell's highlight + dimming.
class WeekDay {
  final String iso;
  final int dow;
  final double distanceM;
  final int count;
  final bool isToday;
  final bool isFuture;
  const WeekDay({
    required this.iso,
    required this.dow,
    required this.distanceM,
    required this.count,
    required this.isToday,
    required this.isFuture,
  });
}

/// The whole strip: its seven ordered days plus the week's running totals,
/// so a header can show "12.4 km · 3 activities" without re-summing.
class CurrentWeek {
  final List<WeekDay> days;
  final double totalDistanceM;
  final int totalCount;
  const CurrentWeek({
    required this.days,
    required this.totalDistanceM,
    required this.totalCount,
  });
}

/// Local `yyyy-mm-dd` for a date — NOT a UTC ISO string, which would shift
/// across the boundary and bucket a late-evening run into the wrong day.
/// Mirrors the TS twin's `localIso`.
String _localIso(DateTime d) {
  final mo = d.month.toString().padLeft(2, '0');
  final da = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mo-$da';
}

/// JS-style day-of-week (0 = Sunday). Dart's [DateTime.weekday] is
/// 1 = Monday .. 7 = Sunday, so Sunday(7) maps to 0.
int _jsDow(DateTime d) => d.weekday % 7;

/// Midnight (local) at the start of the calendar week containing [now],
/// honouring [weekStart]. Same offset math the web dashboard's inline
/// weekStart derived used before this was lifted to a shared helper.
DateTime _weekStartMidnight(DateTime now, WeekStart weekStart) {
  final dow = _jsDow(now);
  final offset = weekStart == WeekStart.sunday ? dow : (dow + 6) % 7;
  final d = DateTime(now.year, now.month, now.day - offset);
  return d;
}

/// Build the current calendar week from [activities], bucketing each one
/// onto its LOCAL day. Activities outside the week (or with a non-positive
/// distance) are ignored. [now] defaults to the real clock; pass an
/// explicit date in tests for determinism.
CurrentWeek currentWeek(
  List<WeekActivity> activities, [
  WeekStart weekStart = WeekStart.monday,
  DateTime? nowArg,
]) {
  final now = nowArg ?? DateTime.now();
  final start = _weekStartMidnight(now, weekStart);
  final todayIso = _localIso(now);

  final byDay = <String, List<double>>{};
  for (final a in activities) {
    final dist = a.distanceM;
    if (!(dist > 0)) continue;
    final t = DateTime.tryParse(a.startedAt);
    if (t == null) continue;
    final iso = _localIso(t.toLocal());
    (byDay[iso] ??= [0, 0])[0] += dist;
    byDay[iso]![1] += 1;
  }

  final days = <WeekDay>[];
  var totalDistanceM = 0.0;
  var totalCount = 0;
  for (var i = 0; i < 7; i++) {
    final d = DateTime(start.year, start.month, start.day + i);
    final iso = _localIso(d);
    final agg = byDay[iso] ?? [0.0, 0.0];
    final distanceM = agg[0];
    final count = agg[1].toInt();
    days.add(WeekDay(
      iso: iso,
      dow: _jsDow(d),
      distanceM: distanceM,
      count: count,
      isToday: iso == todayIso,
      isFuture: iso.compareTo(todayIso) > 0,
    ));
    totalDistanceM += distanceM;
    totalCount += count;
  }

  return CurrentWeek(
    days: days,
    totalDistanceM: totalDistanceM,
    totalCount: totalCount,
  );
}
