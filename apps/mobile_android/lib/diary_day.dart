/// Diary day — which calendar day the nutrition surface is showing, and the
/// fetch windows, storage keys and write timestamps that day implies.
///
/// Dart twin of web `apps/web/src/lib/nutrition/diary_day.ts`.
/// `nutrition_screen` resolved every one of those from `DateTime.now()`, so a
/// forgotten yesterday could never be back-filled and no past day could be
/// reviewed — even though `NutritionMealDetailScreen` is already parameterised
/// by day and `LocalFoodStore.createLocal` already takes a `startedAt`. The
/// data layer was ready; only the surface was today-locked.
///
/// Two rules this module exists to hold:
///
/// - **Days step through the calendar, never by a fixed 24 hours.** A local day
///   is 23 or 25 hours across a DST transition, so a millisecond step repeats
///   or skips a day and an exclusive window end lands at 23:00 of the same day,
///   hiding the last hour's entries ([decisions.md § 589] — that exact bug was
///   fixed in the mobile nutrition day window). Every step here goes through
///   `DateTime(y, m, d + n)`, which normalises through the calendar.
/// - **The diary never shows a future day.** A `started_at` in the future sits
///   outside every "today" window the rings, the Home card and the Coach
///   context read, so a stale viewed day resolves to today rather than to a day
///   nobody can have eaten.
///
/// The web sibling's `DIARY_DATE_PARAM` is web routing (`/nutrition?date=`) and
/// has no mobile analogue; everything else is mirrored function for function.
library;

/// A local calendar date, [m] 1-based so it reads like the ISO string.
class CalendarDate {
  final int y;
  final int m;
  final int d;
  const CalendarDate(this.y, this.m, this.d);

  @override
  bool operator ==(Object other) =>
      other is CalendarDate && other.y == y && other.m == m && other.d == d;

  @override
  int get hashCode => Object.hash(y, m, d);

  @override
  String toString() => 'CalendarDate($y, $m, $d)';
}

/// Local zero-padded `YYYY-MM-DD` for an instant — the diary's day identity.
/// Local, not UTC: a 23:30 entry belongs to the day the user was living, not to
/// tomorrow in Greenwich.
String isoDateOf(DateTime at) {
  final l = at.toLocal();
  final mm = l.month.toString().padLeft(2, '0');
  final dd = l.day.toString().padLeft(2, '0');
  return '${l.year}-$mm-$dd';
}

final RegExp _isoDay = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Strict `YYYY-MM-DD` parse. Null for anything that is not a real calendar
/// date — including one the calendar does not have (`2026-02-30`), which
/// [DateTime] would otherwise normalise into March and show as the wrong day.
CalendarDate? parseIsoDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final match = _isoDay.firstMatch(iso);
  if (match == null) return null;
  final y = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  final d = int.parse(match.group(3)!);
  // Rejected to match the web sibling, where `new Date(26, …)` means 1926 and
  // the round-trip fails, so `0026-02-01` never resolves to a usable day.
  // Dart's own `DateTime(26, …)` would happily accept year 26.
  if (y < 100) return null;
  final probe = DateTime(y, m, d);
  if (probe.year != y || probe.month != m || probe.day != d) return null;
  return CalendarDate(y, m, d);
}

/// The day the diary should show for a stored or restored value: it, when it is
/// a real, non-future calendar date, else today. Fail-safe by design — a stale
/// value lands on today rather than on an empty day the user cannot explain.
String resolveDiaryDate(String? iso, DateTime now) {
  final today = isoDateOf(now);
  if (parseIsoDate(iso) == null) return today;
  // Zero-padded fixed-width dates sort lexicographically in calendar order, so
  // a string compare is the whole future test.
  return iso!.compareTo(today) > 0 ? today : iso;
}

/// [iso] moved [deltaDays] calendar days, clamped so the diary never steps past
/// today. An unparseable input resolves to today.
String stepDiaryDate(String iso, int deltaDays, DateTime now) {
  final today = isoDateOf(now);
  final base = parseIsoDate(iso);
  if (base == null) return today;
  final stepped = isoDateOf(DateTime(base.y, base.m, base.d + deltaDays));
  return stepped.compareTo(today) > 0 ? today : stepped;
}

bool isDiaryToday(String iso, DateTime now) => iso == isoDateOf(now);

/// Milliseconds from [now] to the next local midnight — the one instant at
/// which the day the diary calls "Today" stops being today.
///
/// Stepped through the calendar like every other step in this module, so a DST
/// day is 23 or 25 hours long and the wakeup still lands on midnight. A fixed
/// 86400000 would fire an hour early on a fall-back day and an hour late on a
/// spring-forward one ([decisions.md § 589]).
int msUntilNextLocalMidnight(DateTime now) {
  final l = now.toLocal();
  final next = DateTime(l.year, l.month, l.day + 1);
  return next.difference(l).inMilliseconds;
}

/// Whether the diary can step forward — false on today, and on any day a stale
/// value resolved forward to today.
bool canStepForward(String iso, DateTime now) =>
    iso.compareTo(isoDateOf(now)) < 0;

class DiaryWindow {
  /// Inclusive start instant (local midnight of the window's first day).
  final DateTime start;

  /// Exclusive end instant (local midnight of the day *after* the viewed day).
  final DateTime end;
  const DiaryWindow(this.start, this.end);
}

/// Half-open `[start, end)` instant window covering the [days] calendar days
/// ending on — and including — [iso]. Null when [iso] is not a calendar date,
/// so a caller that skipped [resolveDiaryDate] fetches nothing rather than a
/// wrong day.
DiaryWindow? diaryWindow(String iso, [int days = 1]) {
  final base = parseIsoDate(iso);
  if (base == null || days < 1) return null;
  return DiaryWindow(
    DateTime(base.y, base.m, base.d - (days - 1)),
    DateTime(base.y, base.m, base.d + 1),
  );
}

/// Whether a row's `started_at` falls inside a diary window.
///
/// Compared as **instants**, never as strings. Postgres hands back
/// `2026-08-13T04:00:00+00:00` while the store writes `…T04:00:00.000Z`; those
/// are the same moment but `'+' < '.'`, so a lexicographic compare drops a row
/// landing exactly on the boundary — which for a local-midnight window is
/// precisely the row most likely to be there. A malformed timestamp is out.
bool isWithinWindow(String? startedAt, DiaryWindow window) {
  if (startedAt == null || startedAt.isEmpty) return false;
  final at = DateTime.tryParse(startedAt);
  if (at == null) return false;
  return !at.isBefore(window.start) && at.isBefore(window.end);
}

/// The [n] local dates ending on — and including — [iso], oldest first. These
/// are the trend chart's buckets, so they must be the same `YYYY-MM-DD` an
/// entry's `started_at` maps to through [isoDateOf].
List<String> trailingDates(String iso, int n) {
  final base = parseIsoDate(iso);
  if (base == null || n < 1) return const [];
  return [
    for (var i = n - 1; i >= 0; i--)
      isoDateOf(DateTime(base.y, base.m, base.d - i)),
  ];
}

/// The `started_at` an entry logged while viewing [iso] should carry.
///
/// On today it is simply now, so meal ordering keeps its real clock time. On a
/// past day it is the same wall-clock time on that date: inside the day in
/// every case, and monotonic across a logging session so several back-filled
/// items keep the order they were entered. On a spring-forward date a
/// non-existent local time normalises forward an hour — still the same day,
/// which is all the window cares about.
DateTime entryTimestampFor(String iso, DateTime now) {
  final base = parseIsoDate(iso);
  if (base == null || isDiaryToday(iso, now)) return now;
  final n = now.toLocal();
  return DateTime(
    base.y,
    base.m,
    base.d,
    n.hour,
    n.minute,
    n.second,
    n.millisecond,
  );
}

/// Day component of the water tracker's `SharedPreferences` key.
///
/// Deliberately **not** the zero-padded [isoDateOf] form: the shipped key was
/// built from unpadded `d.month` / `d.day`, and padding it here would orphan
/// the count of everyone who had already drunk something on the day this
/// shipped. The ugliness buys continuity; nothing else reads it.
String waterDayKey(String iso) {
  final base = parseIsoDate(iso);
  if (base == null) return iso;
  return '${base.y}-${base.m}-${base.d}';
}
