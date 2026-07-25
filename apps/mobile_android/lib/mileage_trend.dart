import 'package:core_models/core_models.dart';

import 'l10n/date_format.dart';

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

/// Minimum number of buckets to show on the yearly chart even when
/// most years have zero runs — keeps a single-year user from seeing
/// a lonely bar.
const int _kYearlyMinBuckets = 5;

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
  /// Minimum number of buckets to return — back-fills empty
  /// buckets (distanceM=0) going back from `now` when the actual
  /// data set is sparser. User request: "ensure if there is little
  /// to no data a minimum of 3 weeks, 3 months, and 3 years are
  /// shown." Default 0 (no pad) preserves the pure-aggregation
  /// shape for downstream callers; the dashboard rendering card
  /// opts in to `minBuckets: 3`.
  int minBuckets = 0,
  /// Back-compat for the original "pad yearly to 5" caller; when
  /// true on the yearly view, pads to `_kYearlyMinBuckets` (5)
  /// instead of `minBuckets`. Preserves the existing dashboard
  /// behaviour where the yearly card wanted 5-year context.
  bool padYearlyToMin = false,
  String localeTag = 'en',
}) {
  final groups = <String, _Bucket>{};
  for (final r in runs) {
    final d = r.startedAt.toLocal();
    final key = _keyFor(d, view);
    final bucket = groups[key];
    if (bucket == null) {
      groups[key] = _Bucket(
        startsAt: _startOfBucket(d, view),
        label: _labelFor(d, view, localeTag),
        distanceM: r.distanceMetres.round(),
      );
    } else {
      bucket.distanceM += r.distanceMetres.round();
    }
  }
  final ordered = groups.values.toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  // Determine the effective minimum: yearly + padYearlyToMin
  // overrides minBuckets with the legacy 5-year minimum; otherwise
  // the new `minBuckets` (default 3) applies to every view.
  final effectiveMin = (padYearlyToMin && view == MileageView.yearly)
      ? _kYearlyMinBuckets
      : minBuckets;

  // Back-fill empty buckets going back from `now`. Walks N-1 buckets
  // into the past from the anchor bucket of `now`, inserting an
  // empty bucket for any key that's missing. Handles the "no runs"
  // case (ordered is empty → anchor is the current week/month/year,
  // we back-fill from there).
  if (effectiveMin > 0) {
    // The window always ENDS at the bucket containing `now`, even when nothing
    // was logged in it. It used to end at the last bucket WITH DATA, so an
    // idle runner's rightmost bar was a three-week-old total — and the card
    // labels that bar "this week". Back-fill then walks back from now, which
    // is what this parameter has always claimed to do.
    final anchor = _startOfBucket(now, view);
    final existingKeys =
        ordered.map((b) => _keyForDate(b.startsAt, view)).toSet();
    if (!existingKeys.contains(_keyForDate(anchor, view))) {
      ordered.add(_Bucket(
        startsAt: anchor,
        label: _labelFor(anchor, view, localeTag),
        distanceM: 0,
      ));
      existingKeys.add(_keyForDate(anchor, view));
    }
    var cursor = anchor;
    while (ordered.length < effectiveMin) {
      cursor = _previousBucketStart(cursor, view);
      final key = _keyForDate(cursor, view);
      if (existingKeys.contains(key)) continue;
      ordered.add(_Bucket(
        startsAt: cursor,
        label: _labelFor(cursor, view, localeTag),
        distanceM: 0,
      ));
      existingKeys.add(key);
    }
    ordered.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

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

/// Step back one bucket in the chosen view. Weekly: -7 days from a
/// Monday-anchored start. Monthly: previous month-start. Yearly:
/// previous January 1st.
DateTime _previousBucketStart(DateTime d, MileageView view) {
  switch (view) {
    case MileageView.weekly:
      // Calendar arithmetic, not 7×24 h — a week spanning a DST transition is
      // 167 or 169 hours, so a fixed Duration walks the boundary off local
      // midnight and the back-filled bars are labelled a week early. Same
      // reasoning as weekStartLocal in goals.dart.
      return DateTime(d.year, d.month, d.day - 7);
    case MileageView.monthly:
      return DateTime(d.year, d.month - 1);
    case MileageView.yearly:
      return DateTime(d.year - 1);
  }
}

/// Key string for back-fill dedupe. Uses the same shape as
/// `_keyFor(run.startedAt, view)` so the existing-set lookup works.
String _keyForDate(DateTime d, MileageView view) {
  switch (view) {
    case MileageView.weekly:
      // Already at start-of-bucket (Monday); same shape as _keyFor.
      final iso = d.toIso8601String().substring(0, 10);
      return iso;
    case MileageView.monthly:
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    case MileageView.yearly:
      return d.year.toString();
  }
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

String _labelFor(DateTime d, MileageView view, String localeTag) {
  switch (view) {
    case MileageView.weekly:
      return formatDateShort(_mondayOf(d), localeTag);
    case MileageView.monthly:
      final yy = (d.year % 100).toString().padLeft(2, '0');
      return "${formatMonthAbbr(d, localeTag)} '$yy";
    case MileageView.yearly:
      return d.year.toString();
  }
}

DateTime _mondayOf(DateTime d) {
  // DateTime.weekday: Mon=1..Sun=7. Step back (weekday - 1) days with the
  // year/month/day constructor so the boundary is local midnight even when the
  // week spans a DST transition — a fixed Duration lands on 23:00 the previous
  // day and mis-buckets every run in the seam. See goals.dart weekStartLocal.
  final local = DateTime(d.year, d.month, d.day);
  return DateTime(local.year, local.month, local.day - (local.weekday - 1));
}
