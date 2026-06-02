import 'package:core_models/core_models.dart';

import 'l10n/date_format.dart';

/// One item in the History tab's vertical scroll. Either a month
/// section header ("May 2026") or a single run tile. Splitting the
/// pre-computed list out of the ListView keeps the itemBuilder
/// arithmetic readable and the grouping logic unit-testable.
sealed class HistoryItem {
  const HistoryItem();
}

class HistoryMonthHeader extends HistoryItem {
  /// Display label — "May 2026" / "Apr 2025". The current year is
  /// elided to a shorter "May" so the active month feels less
  /// shouty in the list.
  final String label;
  /// Year + month that produced this header. Held alongside the
  /// label so tests can pin the boundary deterministically (label
  /// shape may change without breaking the grouping contract).
  final int year;
  final int month;

  const HistoryMonthHeader({
    required this.label,
    required this.year,
    required this.month,
  });
}

class HistoryRun extends HistoryItem {
  final Run run;
  const HistoryRun(this.run);
}

/// Walk [runs] (assumed newest-first) and emit a flat list of
/// `HistoryMonthHeader` + `HistoryRun` items. A header is inserted
/// each time the run's calendar month differs from the previous
/// emitted run's month. Year for the current year is omitted from
/// the label.
///
/// [now] is parameterised so unit tests can pin the current-year
/// shortening behaviour.
List<HistoryItem> buildHistoryItems(
  List<Run> runs, {
  required DateTime now,
  String localeTag = 'en',
}) {
  final out = <HistoryItem>[];
  int? lastYear;
  int? lastMonth;
  for (final r in runs) {
    final d = r.startedAt.toLocal();
    if (d.year != lastYear || d.month != lastMonth) {
      out.add(HistoryMonthHeader(
        label: _monthLabel(d, now, localeTag),
        year: d.year,
        month: d.month,
      ));
      lastYear = d.year;
      lastMonth = d.month;
    }
    out.add(HistoryRun(r));
  }
  return out;
}

/// Aggregate stats over a filtered run list — used by the History
/// tab's summary chip above the filter row. Numbers stay in raw
/// units so the renderer can honour the user's km/mi preference.
class HistoryFilterSummary {
  final int runCount;
  final double totalDistanceM;
  final Duration totalDuration;

  const HistoryFilterSummary({
    required this.runCount,
    required this.totalDistanceM,
    required this.totalDuration,
  });

  static const HistoryFilterSummary empty = HistoryFilterSummary(
    runCount: 0,
    totalDistanceM: 0,
    totalDuration: Duration.zero,
  );
}

HistoryFilterSummary summariseRuns(List<Run> runs) {
  if (runs.isEmpty) return HistoryFilterSummary.empty;
  var distance = 0.0;
  var totalS = 0;
  for (final r in runs) {
    distance += r.distanceMetres;
    totalS += r.duration.inSeconds;
  }
  return HistoryFilterSummary(
    runCount: runs.length,
    totalDistanceM: distance,
    totalDuration: Duration(seconds: totalS),
  );
}

String _monthLabel(DateTime d, DateTime now, String localeTag) {
  final name = formatMonthName(d, localeTag);
  return d.year == now.year ? name : '$name ${d.year}';
}
