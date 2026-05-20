import 'package:core_models/core_models.dart';

/// One bucket on the mileage-trend chart. [label] is the short
/// human-readable axis label (week start "5 May", month "May '26",
/// year "2026"); [distanceM] is the summed run distance in metres
/// across runs that fell in this bucket. Storage is in metres so the
/// render side can honour the user's distance-unit preference.
class MileagePeriod {
  final String label;
  final int distanceM;
  /// Sort key so the renderer can keep buckets chronological. The
  /// label alone isn't sortable: "Jan '26" sorts lexically before
  /// "May '25" even though it's later.
  final DateTime startsAt;

  const MileagePeriod({
    required this.label,
    required this.distanceM,
    required this.startsAt,
  });
}

/// Granularity of the mileage trend chart. Mirrors web's
/// `mileageView` state.
enum MileageView { weekly, monthly, yearly }

/// Group a list of runs into [MileagePeriod] buckets matching [view].
/// Returns the most recent [maxBuckets] buckets in chronological
/// order. Empty when [runs] is empty.
///
/// Weeks start Monday — same anchor as `lib/goals.dart` so the goal
/// progress card and the trend chart line up exactly. Months are
/// keyed by `YYYY-MM` internally; years by `YYYY`.
List<MileagePeriod> aggregateMileage(
  List<Run> runs, {
  required MileageView view,
  required DateTime now,
  int maxBuckets = 12,
}) {
  if (runs.isEmpty) return const [];
  // Bucket key → (sortKey, label, summedDistance).
  final groups = <String, _Bucket>{};
  for (final r in runs) {
    final d = r.startedAt.toLocal();
    final key = _keyFor(d, view);
    final bucket = groups[key];
    if (bucket == null) {
      groups[key] = _Bucket(
        startsAt: _startOfBucket(d, view),
        label: _labelFor(d, view),
        distanceM: r.distanceMetres.round(),
      );
    } else {
      bucket.distanceM += r.distanceMetres.round();
    }
  }
  // Sort chronologically; keep only the most recent N.
  final ordered = groups.values.toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  final start = ordered.length > maxBuckets
      ? ordered.length - maxBuckets
      : 0;
  return [
    for (var i = start; i < ordered.length; i++)
      MileagePeriod(
        label: ordered[i].label,
        distanceM: ordered[i].distanceM,
        startsAt: ordered[i].startsAt,
      ),
  ];
}

class _Bucket {
  final DateTime startsAt;
  final String label;
  int distanceM;
  _Bucket({
    required this.startsAt,
    required this.label,
    required this.distanceM,
  });
}

String _keyFor(DateTime d, MileageView view) {
  switch (view) {
    case MileageView.weekly:
      final start = _mondayOf(d);
      return 'W${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    case MileageView.monthly:
      return 'M${d.year}-${d.month.toString().padLeft(2, '0')}';
    case MileageView.yearly:
      return 'Y${d.year}';
  }
}

DateTime _startOfBucket(DateTime d, MileageView view) {
  switch (view) {
    case MileageView.weekly:
      return _mondayOf(d);
    case MileageView.monthly:
      return DateTime(d.year, d.month);
    case MileageView.yearly:
      return DateTime(d.year);
  }
}

String _labelFor(DateTime d, MileageView view) {
  switch (view) {
    case MileageView.weekly:
      final m = _mondayOf(d);
      return '${m.day} ${_monthAbbr(m.month)}';
    case MileageView.monthly:
      final yy = (d.year % 100).toString().padLeft(2, '0');
      return "${_monthAbbr(d.month)} '$yy";
    case MileageView.yearly:
      return d.year.toString();
  }
}

DateTime _mondayOf(DateTime d) {
  // DateTime.weekday: Mon=1..Sun=7. Subtract (weekday - 1) days, zero
  // out the time so the bucket boundary is midnight local time.
  final local = DateTime(d.year, d.month, d.day);
  return local.subtract(Duration(days: local.weekday - 1));
}

const _monthAbbrs = <String>[
  '', // 1-indexed
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _monthAbbr(int month) => _monthAbbrs[month];
