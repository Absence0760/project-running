import 'package:api_client/api_client.dart' show ActivityRow;

/// One local-calendar-day bucket of activities for the unified History
/// timeline. `day` is local midnight; `rows` preserves the source order
/// (newest-first, as the `activities` view returns).
class ActivityDay {
  final DateTime day;
  final List<ActivityRow> rows;
  const ActivityDay({required this.day, required this.rows});
}

/// Group reverse-chronological [ActivityRow]s into per-local-day buckets,
/// preserving order within and across days. Mirrors the web History
/// `timelineGroups` derivation (multi_modal.md § History). Pure so the
/// grouping boundaries can be unit-tested without a widget pump.
List<ActivityDay> groupActivitiesByDay(List<ActivityRow> rows) {
  final groups = <ActivityDay>[];
  List<ActivityRow>? current;
  DateTime? currentKey;
  for (final a in rows) {
    final local = a.startedAt.toLocal();
    final key = DateTime(local.year, local.month, local.day);
    if (currentKey == null || currentKey != key) {
      current = <ActivityRow>[];
      currentKey = key;
      groups.add(ActivityDay(day: key, rows: current));
    }
    current!.add(a);
  }
  return groups;
}
