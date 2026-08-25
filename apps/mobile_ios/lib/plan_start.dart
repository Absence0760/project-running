/// Start-date alignment for the plan wizard. `generatePlan` hard-anchors day
/// 0 of the start week to the Sunday long run — every day role in
/// `_generateWeek` is an OFFSET from the start date, not a real weekday — so a
/// plan that starts on a Wednesday puts the long run midweek and the rest day
/// on Thursday, whatever the generator's own comments say.
///
/// Dart twin of `apps/web/src/lib/training/plan_start.ts` — keep the algorithm,
/// edge cases, outputs, and test counts in lockstep. The web twin works in ISO
/// `yyyy-mm-dd` because its input is an `<input type="date">` value; the phone
/// picker hands over a `DateTime`, so this side takes one. That input type is
/// the only difference.
library;

/// Snap a date forward to the upcoming Sunday — a no-op when it already is
/// one. Stepped through the year/month/day constructor rather than by adding
/// a fixed 24-hour `Duration`, so a span crossing a DST transition still
/// lands on local midnight.
DateTime nextSunday(DateTime d) {
  final off = (DateTime.sunday - d.weekday) % 7;
  return DateTime(d.year, d.month, d.day + off);
}

/// True when a date falls on a Sunday (local time).
bool isSunday(DateTime d) => d.weekday == DateTime.sunday;
