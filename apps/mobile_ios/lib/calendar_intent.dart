/// Hands a club event to the phone's own calendar.
///
/// Web downloads an RFC 5545 `.ics` file (decisions § 599) because a browser
/// has nothing else to hand it to. A phone has an OS calendar, so the mirror is
/// the platform hand-off — `ACTION_INSERT` on `CalendarContract.Events` on
/// Android, `EKEventEditViewController` on iOS — and the `.ics` text builder
/// owes no Dart twin (§ 24).
///
/// The series crosses the channel as an RRULE value because both platforms
/// already speak that grammar: Android stores it verbatim in `Events.RRULE`,
/// iOS maps it onto an `EKRecurrenceRule`. One representation means one
/// shaping and one place for it to be wrong.
///
/// [buildRrule] mirrors web's `buildRrule` decision for decision, including its
/// refusal to state a monthly series anchored past the 28th. Web's guards for
/// an unparseable UNTIL and a non-integer COUNT have no analogue here — a
/// `DateTime` and an `int` cannot arrive in those states.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'event_occurrence.dart';
import 'recurrence.dart';

@visibleForTesting
const MethodChannel calendarChannel = MethodChannel('run_app/calendar');

/// RFC 5545 BYDAY ordering, so the same weekday set always renders the same
/// rule string.
const List<Weekday> _rruleWeekdayOrder = [
  Weekday.mo,
  Weekday.tu,
  Weekday.we,
  Weekday.th,
  Weekday.fr,
  Weekday.sa,
  Weekday.su,
];

/// A weekly series' first occurrence is at most 7 days past `startsAt`, a
/// biweekly's 14, a monthly's 0 — but a series bounded by `until` can have none
/// at all, so the search window is generous and the empty case is handled.
const Duration _anchorWindow = Duration(days: 400);

/// How far ahead cancelled occurrences are counted for the surface's note —
/// the same one-year horizon the occurrence picker expands over.
const Duration _cancellationHorizon = Duration(days: 365);

/// The whole series restated in the terms a platform recurrence rule needs.
class CalendarSeries {
  /// The rule's first occurrence. RFC 5545 § 3.8.5.3 requires the start to be a
  /// member of the recurrence set and `startsAt` need not be (a Tuesday-created
  /// Saturday series), so this is the first expanded occurrence.
  final DateTime anchor;

  /// The RRULE value, with no `RRULE:` prefix.
  final String rrule;

  /// Called-off occurrences within the next year. Neither `ACTION_INSERT`'s
  /// extras nor `EKRecurrenceRule` carry exception dates, so the hand-off
  /// cannot subtract these the way web's `EXDATE` does — the surface says so
  /// rather than letting the calendar quietly disagree with the club page.
  final List<DateTime> unsubtractedCancellations;

  const CalendarSeries({
    required this.anchor,
    required this.rrule,
    required this.unsubtractedCancellations,
  });
}

/// Render a recurrence as an RRULE value, or null when it cannot be stated
/// faithfully.
///
/// The one shape that fails is a monthly series anchored after the 28th:
/// [expandInstances] clamps a missing day-of-month to the month's last day
/// (Jan 31 -> Feb 28) and BYMONTHDAY has no clamp — it skips the short month
/// outright. A calendar that disagrees with the club page about which dates the
/// club is meeting is worse than no calendar entry.
String? buildRrule({
  required RecurrenceFreq freq,
  List<Weekday> byday = const [],
  int? monthDay,
  int? count,
  DateTime? until,
}) {
  final parts = <String>[];

  if (freq == RecurrenceFreq.monthly) {
    if (monthDay == null || monthDay < 1 || monthDay > 28) return null;
    parts.add('FREQ=MONTHLY');
  } else {
    parts.add('FREQ=WEEKLY');
    if (freq == RecurrenceFreq.biweekly) parts.add('INTERVAL=2');
  }

  // RFC 5545 § 3.3.10 forbids UNTIL and COUNT in one rule.
  if (count != null) {
    if (count < 1) return null;
    parts.add('COUNT=$count');
  } else if (until != null) {
    parts.add('UNTIL=${_rruleUtc(until)}');
  }

  if (freq == RecurrenceFreq.monthly) {
    parts.add('BYMONTHDAY=$monthDay');
  } else if (byday.isNotEmpty) {
    final ordered = [
      for (final w in _rruleWeekdayOrder)
        if (byday.contains(w)) weekdayCode(w),
    ];
    if (ordered.isEmpty) return null;
    parts.add('BYDAY=${ordered.join(',')}');
  }

  return parts.join(';');
}

/// The series of [e] as a platform recurrence rule, or null for a one-off event
/// and for a series the rule grammar cannot state exactly.
CalendarSeries? calendarSeriesFor(
  EventRecurrence e, {
  Iterable<DateTime> cancelled = const [],
  DateTime? now,
}) {
  final freq = e.freq;
  if (freq == null) return null;

  final seriesStart = _wholeSecond(e.startsAt);
  final anchors = expandInstances(
    e,
    seriesStart,
    seriesStart.add(_anchorWindow),
    max: 1,
  );
  if (anchors.isEmpty) return null;
  final anchor = anchors.first;

  final end = _resolveSeriesEnd(e);
  final rrule = buildRrule(
    freq: freq,
    byday: freq == RecurrenceFreq.monthly
        ? const []
        : _seriesWeekdays(e, anchor),
    monthDay: freq == RecurrenceFreq.monthly ? anchor.toUtc().day : null,
    count: end.count,
    until: end.until,
  );
  if (rrule == null) return null;

  final from = now ?? DateTime.now();
  final ahead = expandInstances(e, from, from.add(_cancellationHorizon));
  return CalendarSeries(
    anchor: anchor,
    rrule: rrule,
    unsubtractedCancellations: [
      for (final d in ahead)
        if (isOccurrenceCancelled(cancelled, d)) d,
    ],
  );
}

/// The app applies `until` and `count` together; a rule may carry only one.
/// Where both are set, count the real occurrences inside the until-bound so
/// whichever binds first survives the translation.
({int? count, DateTime? until}) _resolveSeriesEnd(EventRecurrence e) {
  final count = e.count;
  final until = e.until;
  if (count != null && until != null) {
    return (
      count:
          expandInstances(e, _wholeSecond(e.startsAt), until, max: count).length,
      until: null,
    );
  }
  return (count: count, until: until);
}

/// [expandInstances] stamps every occurrence at whole-second resolution, so a
/// `starts_at` carrying sub-second precision sorts strictly after its own first
/// occurrence — searching from the raw value silently drops it and anchors the
/// series one period late (and counts one occurrence short).
DateTime _wholeSecond(DateTime d) => DateTime.fromMillisecondsSinceEpoch(
      d.millisecondsSinceEpoch - d.millisecondsSinceEpoch % 1000,
      isUtc: d.isUtc,
    );

/// The BYDAY set, read off the expansion rather than translated from
/// `recurrence_byday`: the stored codes are wall-clock in the event's own zone
/// while the rule is anchored in UTC, so a late-evening event sits on a
/// different UTC weekday than the code the organiser picked. One cycle is
/// enough to see every weekday the series lands on.
List<Weekday> _seriesWeekdays(EventRecurrence e, DateTime anchor) {
  final cycleDays = e.freq == RecurrenceFreq.biweekly ? 15 : 8;
  final cycle = expandInstances(
    e,
    _wholeSecond(e.startsAt),
    // elapsed-time: a loose upper bound on one recurrence cycle, matching the
    // millisecond span web's twin walks — not a calendar step.
    anchor.add(Duration(days: cycleDays)),
    max: 20,
  );
  final seen = {for (final d in cycle) _utcWeekday(d)};
  if (seen.isEmpty) seen.add(_utcWeekday(anchor));
  return [
    for (final w in _rruleWeekdayOrder)
      if (seen.contains(w)) w,
  ];
}

Weekday _utcWeekday(DateTime d) => _rruleWeekdayOrder[d.toUtc().weekday - 1];

String _rruleUtc(DateTime d) {
  final u = d.toUtc();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${p2(u.month)}${p2(u.day)}'
      'T${p2(u.hour)}${p2(u.minute)}${p2(u.second)}Z';
}

/// Open the OS calendar's own new-event editor, pre-filled from the event —
/// one occurrence, or the whole series when [rrule] is set.
///
/// Returns false when the editor could not be opened (no calendar app,
/// calendar access refused on iOS, no native handler) so the caller can say so.
/// Never throws: this is an L4 auxiliary effect hanging off the event page.
Future<bool> addToDeviceCalendar({
  required String title,
  required DateTime start,
  int? durationMin,
  String? description,
  String? location,
  String? url,
  String? rrule,
}) async {
  final startUtc = start.toUtc();
  try {
    final opened = await calendarChannel.invokeMethod<bool>('addEvent', {
      'title': title,
      'startMs': startUtc.millisecondsSinceEpoch,
      if (durationMin != null && durationMin > 0)
        'endMs': startUtc
            .add(Duration(minutes: durationMin))
            .millisecondsSinceEpoch,
      'description': description,
      'location': location,
      'url': url,
      'rrule': rrule,
    });
    return opened == true;
  } catch (e) {
    debugPrint('addToDeviceCalendar failed: $e');
    return false;
  }
}
