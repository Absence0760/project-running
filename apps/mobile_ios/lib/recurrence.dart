// Client-side expansion of the enum-recurrence model used by Phase 2 events.
// Dart port of apps/web/src/lib/social/recurrence.ts. The two implementations must
// stay in sync so web and Android render the same instance timestamps for a
// given event row. See docs/architecture/decisions.md #10.

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

/// [base] advanced by [months] whole months, clamping the day-of-month to the
/// target month's last day so a day-31 anchor lands on Feb-28/29 instead of
/// overflowing into the following month (DateTime(y, 2, 31) → March). [useUtc]
/// reads + builds in UTC wall-clock so the result is viewer-independent for a
/// timezoned event (see expandInstances).
int _monthsBetween(DateTime a, DateTime b, bool useUtc) {
  final bb = useUtc ? b.toUtc() : b.toLocal();
  return (bb.year - a.year) * 12 + (bb.month - a.month);
}

/// Step whole CALENDAR days from a midnight cursor.
///
/// `add(Duration(days: n))` adds absolute 24-hour blocks. Across a DST
/// fall-back a local midnight lands at 23:00 the PREVIOUS day, so the local
/// calendar day repeats and every later offset is shifted by one — which
/// flips `weekIndex % 2` and moves a biweekly series onto entirely different
/// dates from the week of the transition onward. Web steps with
/// `Date.setDate()`, which is calendar-based; this must match it, because the
/// instance start is the per-occurrence RSVP capacity key and the live-race
/// arm key, so every viewer has to compute the identical instant.
DateTime _addDaysCalendar(DateTime dayStart, int days, bool useUtc) => useUtc
    ? DateTime.utc(dayStart.year, dayStart.month, dayStart.day + days)
    : DateTime(dayStart.year, dayStart.month, dayStart.day + days);

DateTime _addMonthsClamped(DateTime base, int months, bool useUtc) {
  final total = base.month - 1 + months;
  final year = base.year + (total ~/ 12);
  final month = total % 12 + 1;
  final lastDay = (useUtc ? DateTime.utc(year, month + 1, 0) : DateTime(year, month + 1, 0)).day;
  final day = base.day < lastDay ? base.day : lastDay;
  return useUtc
      ? DateTime.utc(year, month, day, base.hour, base.minute, base.second)
      : DateTime(year, month, day, base.hour, base.minute, base.second);
}

class EventRecurrence {
  final DateTime startsAt;
  final RecurrenceFreq? freq;
  final List<Weekday>? byday;
  final DateTime? until;
  final int? count;

  /// IANA timezone the event's wall-clock is expressed in (events.timezone,
  /// migration 20270111_001). When non-null, expandInstances anchors the
  /// recurrence fields to UTC so every viewer computes the same instant; null
  /// (legacy rows) keeps the original viewer-local stamping. See the comment
  /// on [expandInstances].
  final String? timezone;

  const EventRecurrence({
    required this.startsAt,
    this.freq,
    this.byday,
    this.until,
    this.count,
    this.timezone,
  });
}

/// Expand a recurrence into instance start times within [from, to]. Returns
/// `[startsAt]` for non-recurring events if it's in-window, else `[]`.
///
/// A recurring instance's start is its per-occurrence capacity key
/// (20261018_001) and live-race arm key — every viewer MUST compute the
/// IDENTICAL instant, or two spectators in different zones RSVP against
/// different keys and a cross-TZ viewer sees a live race as "not armed". The
/// wall-clock the organiser meant is fixed in the EVENT's zone, not the
/// viewer's. The old `.toLocal()` + local-field stamping built the instant in
/// the VIEWER's zone, so it drifted by the viewer-vs-event offset. When the
/// event carries a timezone (e.timezone, 20270111_001) we read + stamp the
/// fields in UTC — a zone-independent anchor identical on every viewer and
/// both platforms (the server's discovery filter likewise normalises via `at
/// time zone`). Legacy rows with no timezone keep the original local-zone
/// stamping so their already-placed RSVPs don't shift. Mirrors
/// apps/web/src/lib/social/recurrence.ts — keep the two in lockstep.
///
/// A legacy instance is therefore a LOCAL `DateTime`, and that is fine here:
/// it names the same absolute instant web's `new Date(y, m, d, …)` does. It
/// stops being fine at SERIALISATION, because `toIso8601String()` writes no
/// zone designator for a local `DateTime` where JS's `toISOString()` always
/// emits `Z` — so the wire form is normalised at the boundary that owns it
/// (`instanceStartKey` in `api_client`), not here, where changing it would
/// move the pair away from its twin (decisions § 1343).
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
  final useUtc = e.timezone != null;
  final hardCap = e.count ?? 1 << 30;
  final results = <DateTime>[];
  // The walk always starts at startsAt (occurrences before [from] still count
  // toward `count`), so its iteration budget has to reach the far end of the
  // requested window. Budgeting off [max] — a RESULT count — stopped the walk
  // [max] periods after the series began, so nextInstanceAfter (max = 1)
  // reported "no next occurrence" for every series older than a fortnight.
  final scanEnd = (e.until != null && e.until!.isBefore(to)) ? e.until! : to;

  if (e.freq == RecurrenceFreq.monthly) {
    // Read the anchor in the chosen clock so day-of-month + time-of-day match
    // the organiser's intended wall-clock (UTC) or the viewer's (legacy local).
    // `.toLocal()` on the legacy path, exactly as the weekly branch below:
    // startsAt is parsed from a +00:00 string so it carries a UTC flag, and
    // _addMonthsClamped would otherwise read UTC day-of-month / time-of-day
    // fields and rebuild them as a LOCAL DateTime — shifting every instance by
    // the viewer's offset and, for a late-UTC anchor, onto the wrong day.
    final base = useUtc ? e.startsAt.toUtc() : e.startsAt.toLocal();
    final monthBudget = _monthsBetween(base, scanEnd, useUtc) + 1;
    var produced = 0;
    for (var i = 0; produced < hardCap; i++) {
      if (i > monthBudget) break;
      // Anchor on startsAt's day-of-month and step `i` whole months from it,
      // clamping to the target month's last day (Jan-31 → Feb-28/29). Stepping
      // a running cursor instead would let a clamp permanently shrink the
      // day-of-month (Jan-31 → Feb-28 → Mar-28), drifting off the intended day.
      final cursor = _addMonthsClamped(base, i, useUtc);
      if (e.until != null && cursor.isAfter(e.until!)) break;
      // count caps TOTAL occurrences from startsAt, not the ones inside
      // [from, to]. Counting only in-window occurrences let a count-limited
      // series resurrect phantom instances past its real end when viewed after
      // it had started (from = now > startsAt).
      produced++;
      if (cursor.isAfter(to)) break;
      if (!cursor.isBefore(from)) {
        results.add(cursor);
        if (results.length >= max) break;
      }
    }
    return results;
  }

  final stepDays = e.freq == RecurrenceFreq.biweekly ? 14 : 7;
  // Anchor on the Monday of startsAt's week so weekIndex * 7 == elapsed weeks.
  // Must match the web twin's Monday anchor (recurrence.ts: (getDay()+6)%7) —
  // a Sunday anchor here disagreed with web on which calendar weeks are "even"
  // for biweekly events whose byday set crosses the weekend, producing
  // different instance dates on the two platforms. `weekday - 1` (Dart weekday
  // is 1=Mon..7=Sun) is the exact offset web computes. For a timezoned event
  // the date fields are read in UTC (viewer-independent); legacy rows convert
  // to local so the fields match the user's wall-clock day.
  final start = useUtc ? e.startsAt.toUtc() : e.startsAt.toLocal();
  final byday = (e.byday == null || e.byday!.isEmpty)
      ? [_dartWeekday(start)]
      : e.byday!;
  final startDayOnly = useUtc
      ? DateTime.utc(start.year, start.month, start.day)
      : DateTime(start.year, start.month, start.day);
  final anchor = _addDaysCalendar(startDayOnly, -(start.weekday - 1), useUtc);
  // The stamp below rebuilds the instant from whole seconds, so a startsAt
  // carrying a non-zero millisecond makes its OWN first candidate sort before
  // it and the series' first occurrence disappears everywhere — picker,
  // listings, RSVP keys. The candidate is not-before the start at the only
  // resolution the stamp has, so compare at that resolution. `%` is floor-based
  // for a positive divisor, so a pre-epoch startsAt truncates downward too.
  final startSecondMs = e.startsAt.millisecondsSinceEpoch -
      e.startsAt.millisecondsSinceEpoch % 1000;

  final dayBudget = scanEnd.difference(anchor).inDays + stepDays + 1;
  var produced = 0;
  for (var dayOffset = 0; dayOffset <= dayBudget; dayOffset++) {
    final d = _addDaysCalendar(anchor, dayOffset, useUtc);
    if (d.isBefore(startDayOnly)) {
      continue;
    }
    // Early break — `d` is the candidate day at midnight (in the chosen
    // clock), the actual instance is `stamped` (at startsAt's time-of-day) up
    // to a day later in absolute time. Once `d` is more than a day past the
    // boundary, no future `stamped` can fall before it.
    // elapsed-time: a day of absolute slack on the early-break bound, not a
    // calendar step — matches web, which budgets its scan in whole ms days.
    if (e.until != null && d.isAfter(e.until!.add(const Duration(days: 1)))) {
      break;
    }
    // elapsed-time: the same absolute slack on the scan-end bound.
    if (d.isAfter(to.add(const Duration(days: 1)))) break;

    final weekIndex = dayOffset ~/ 7;
    if (weekIndex % (stepDays ~/ 7) != 0) continue;
    if (!byday.contains(_dartWeekday(d))) continue;

    final stamped = useUtc
        ? DateTime.utc(d.year, d.month, d.day, start.hour, start.minute, start.second)
        : DateTime(d.year, d.month, d.day, start.hour, start.minute, start.second);
    // Precise boundary checks against the absolute instance time.
    // Comparing `d` directly against `until` was zone-dependent: a UTC
    // host saw `d == until` so the loop didn't break, then stamped at
    // startsAt's hour-of-day landed past until; an EDT host saw `d`
    // already after until and broke a day early. Compare stamped.
    if (e.until != null && stamped.isAfter(e.until!)) continue;
    if (stamped.isAfter(to)) continue;
    if (stamped.millisecondsSinceEpoch < startSecondMs) continue;

    // Count every real occurrence toward count — not just the in-window ones —
    // so a count-limited series stops at its true end even when the window
    // starts after startsAt (see the monthly branch above).
    produced++;
    if (!stamped.isBefore(from)) {
      results.add(stamped);
      if (results.length >= max) break;
    }
    if (produced >= hardCap) break;
  }
  return results;
}

DateTime? nextInstanceAfter(EventRecurrence e, [DateTime? after]) {
  final start = after ?? DateTime.now();
  // elapsed-time: a ten-year search horizon, mirroring web's
  // `after.getTime() + 10 * 365 * 24 * 3600 * 1000`.
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
