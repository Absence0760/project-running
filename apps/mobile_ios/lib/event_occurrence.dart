/// Which occurrences of a recurring event are still ON.
///
/// `event_exceptions` (20261019_001) records a called-off occurrence of a
/// series. Only the event-detail picker ever subtracted them, so the club
/// Events tab and the Run tab's upcoming-event card kept advertising an
/// occurrence the organiser had already called off. Dart twin of web's
/// `apps/web/src/lib/social/event_occurrence.ts` — keep the two in lockstep.
///
/// Web compares two ISO renderings of one instant (`+00:00` vs `.000Z`)
/// through `sameInstant`; here both sides are already `DateTime`s, so
/// `isAtSameMomentAs` is that comparison. Web's `upcomingCancelledOccurrences`
/// has no twin: it backs the organiser's reinstate picker, which mobile does
/// not have.

import 'recurrence.dart';

const _tenYears = Duration(days: 365 * 10);

/// True when [instanceStart] names one of the cancelled instants.
bool isOccurrenceCancelled(
  Iterable<DateTime> cancelled,
  DateTime? instanceStart,
) {
  if (instanceStart == null) return false;
  for (final c in cancelled) {
    if (c.isAtSameMomentAs(instanceStart)) return true;
  }
  return false;
}

/// The next occurrence at or after [after] that has NOT been called off, or
/// null when the series has none left.
///
/// The search budget is `cancelled.length + 1` occurrences: at most that many
/// of the expanded ones can be cancelled, so the last candidate is guaranteed
/// live if a live one exists at all. With nothing cancelled this is exactly
/// [nextInstanceAfter], which is the overwhelmingly common case and stops the
/// walk at the first hit.
DateTime? nextLiveInstance(
  EventRecurrence e,
  List<DateTime> cancelled, [
  DateTime? after,
]) {
  final start = after ?? DateTime.now();
  if (cancelled.isEmpty) return nextInstanceAfter(e, start);
  final candidates =
      expandInstances(e, start, start.add(_tenYears), max: cancelled.length + 1);
  for (final c in candidates) {
    if (!isOccurrenceCancelled(cancelled, c)) return c;
  }
  return null;
}
