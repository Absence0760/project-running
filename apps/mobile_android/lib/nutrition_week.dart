/// Weekly intake summary — is the last 7 days of logging trending over or
/// under the daily calorie goal?
///
/// Dart twin of `apps/web/src/lib/nutrition/nutrition_week.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
///
/// Averages over *logged* days only, so an unlogged day never reads as a fake
/// deficit (this is also the reference-average the trend bars draw).
///
/// The non-obvious choice: the delta compares the logged-day average to
/// *today's* full calorie goal. Past days had their own (unstored) goals, so
/// this is an honest "typical day vs goal" read, not a per-day reconciliation.
///
/// Pure functions, no Flutter / Supabase deps.
library;

class WeeklyIntakeSummary {
  final int loggedDays;

  /// Mean intake across logged days (0 when nothing is logged).
  final int avgCalories;

  /// Signed avg − target over logged days: positive = over goal (surplus),
  /// negative = under (deficit). Null when there's no target or no logged day.
  final int? deltaPerDay;

  const WeeklyIntakeSummary({
    required this.loggedDays,
    required this.avgCalories,
    required this.deltaPerDay,
  });
}

WeeklyIntakeSummary weeklyIntakeSummary(List<num> dailyCalories, num? targetCalories) {
  final logged = dailyCalories.where((c) => c > 0).toList();
  final loggedDays = logged.length;
  final avgCalories =
      loggedDays > 0 ? (logged.reduce((s, c) => s + c) / loggedDays).round() : 0;
  final deltaPerDay = targetCalories != null && targetCalories > 0 && loggedDays > 0
      ? avgCalories - targetCalories.round()
      : null;
  return WeeklyIntakeSummary(
    loggedDays: loggedDays,
    avgCalories: avgCalories,
    deltaPerDay: deltaPerDay,
  );
}
