// Client-side expansion of the enum-recurrence model used by Phase 2 events.
// Dart port of apps/web/src/lib/recurrence.ts. The two implementations must
// stay in sync so web and Android render the same instance timestamps for a
// given event row. See docs/decisions.md #10.

enum Weekday { mo, tu, we, th, fr, sa, su }

enum RecurrenceFreq { weekly, biweekly, monthly }

const _isoCodes = <Weekday, String>{
  Weekday.mo: 'MO',
  Weekday.tu: 'TU',
  Weekday.we: 'WE',
  Weekday.th: 'TH',
  Weekday.fr: 'FR',
  Weekday.sa: 'SA',
  Weekday.su: 'SU',
};

const _weekdayLabels = <Weekday, String>{
  Weekday.mo: 'Mon',
  Weekday.tu: 'Tue',
  Weekday.we: 'Wed',
  Weekday.th: 'Thu',
  Weekday.fr: 'Fri',
  Weekday.sa: 'Sat',
  Weekday.su: 'Sun',
};

Weekday? weekdayFromCode(String code) {
  for (final e in _isoCodes.entries) {
    if (e.value == code) return e.key;
  }
  return null;
}

String weekdayCode(Weekday w) => _isoCodes[w]!;
String weekdayLabel(Weekday w) => _weekdayLabels[w]!;

/// DateTime.weekday is 1=Mon..7=Sun. Normalise to our enum.
Weekday _dartWeekday(DateTime d) {
  switch (d.weekday) {
    case DateTime.monday:
      return Weekday.mo;
    case DateTime.tuesday:
      return Weekday.tu;
    case DateTime.wednesday:
      return Weekday.we;
    case DateTime.thursday:
      return Weekday.th;
    case DateTime.friday:
      return Weekday.fr;
    case DateTime.saturday:
      return Weekday.sa;
    default:
      return Weekday.su;
  }
}

RecurrenceFreq? recurrenceFromString(String? s) {
  switch (s) {
    case 'weekly':
      return RecurrenceFreq.weekly;
    case 'biweekly':
      return RecurrenceFreq.biweekly;
    case 'monthly':
      return RecurrenceFreq.monthly;
    default:
      return null;
  }
}

class EventRecurrence {
  final DateTime startsAt;
  final RecurrenceFreq? freq;
  final List<Weekday>? byday;
  final DateTime? until;
  final int? count;

  const EventRecurrence({
    required this.startsAt,
    this.freq,
    this.byday,
    this.until,
    this.count,
  });
}

/// Expand a recurrence into instance start times within [from, to]. Returns
/// `[startsAt]` for non-recurring events if it's in-window, else `[]`.
List<DateTime> expandInstances(
  EventRecurrence e,
  DateTime from,
  DateTime to, {
  int max = 100,
}) {
  if (e.freq == null) {
    return (e.startsAt.compareTo(from) >= 0 && e.startsAt.compareTo(to) <= 0)
        ? [e.startsAt]
        : [];
  }
  final hardCap = e.count ?? 1 << 30;
  final results = <DateTime>[];

  if (e.freq == RecurrenceFreq.monthly) {
    var cursor = e.startsAt;
    for (var i = 0; i < max * 12 && results.length < hardCap; i++) {
      if (e.until != null && cursor.isAfter(e.until!)) break;
      if (cursor.isAfter(to)) break;
      if (!cursor.isBefore(from)) {
        results.add(cursor);
        if (results.length >= max) break;
      }
      cursor = DateTime(
        cursor.year,
        cursor.month + 1,
        cursor.day,
        cursor.hour,
        cursor.minute,
        cursor.second,
      );
    }
    return results;
  }

  final stepDays = e.freq == RecurrenceFreq.biweekly ? 14 : 7;
  final byday = (e.byday == null || e.byday!.isEmpty)
      ? [_dartWeekday(e.startsAt)]
      : e.byday!;
  // Anchor on the Sunday of startsAt's week so weekIndex * 7 == elapsed weeks.
  // startsAt may be a UTC DateTime from Supabase; convert to local so the
  // extracted date fields match the user's wall-clock day.
  final localStart = e.startsAt.toLocal();
  final anchor = DateTime(localStart.year, localStart.month, localStart.day)
      .subtract(Duration(days: localStart.weekday % 7));

  for (var dayOffset = 0; dayOffset < max * stepDays * 7; dayOffset++) {
    final d = anchor.add(Duration(days: dayOffset));
    if (d.isBefore(
      DateTime(localStart.year, localStart.month, localStart.day),
    )) {
      continue;
    }
    if (e.until != null && d.isAfter(e.until!)) break;
    if (d.isAfter(to)) break;

    final weekIndex = dayOffset ~/ 7;
    if (weekIndex % (stepDays ~/ 7) != 0) continue;
    if (!byday.contains(_dartWeekday(d))) continue;

    final stamped = DateTime(
      d.year,
      d.month,
      d.day,
      localStart.hour,
      localStart.minute,
      localStart.second,
    );
    if (stamped.isBefore(e.startsAt)) continue;
    if (!stamped.isBefore(from)) {
      results.add(stamped);
      if (results.length >= max || results.length >= hardCap) break;
    }
  }
  return results;
}

DateTime? nextInstanceAfter(EventRecurrence e, [DateTime? after]) {
  final start = after ?? DateTime.now();
  final tenYears = start.add(const Duration(days: 365 * 10));
  final xs = expandInstances(e, start, tenYears, max: 1);
  return xs.isEmpty ? null : xs.first;
}

String describeRecurrence(RecurrenceFreq? freq, List<Weekday>? byday) {
  if (freq == null) return 'One-off event';
  if (freq == RecurrenceFreq.monthly) return 'Repeats monthly';
  final days = (byday == null || byday.isEmpty)
      ? ''
      : [Weekday.mo, Weekday.tu, Weekday.we, Weekday.th, Weekday.fr, Weekday.sa, Weekday.su]
          .where(byday.contains)
          .map(weekdayLabel)
          .join(', ');
  final base = freq == RecurrenceFreq.biweekly ? 'Every other week' : 'Every week';
  return days.isEmpty ? base : '$base · $days';
}

const weekdayChoices = <Weekday>[
  Weekday.mo,
  Weekday.tu,
  Weekday.we,
  Weekday.th,
  Weekday.fr,
  Weekday.sa,
  Weekday.su,
];
