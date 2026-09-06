import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../current_week.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';

/// Dashboard "This Week" calendar-week activity ribbon — the mobile twin of
/// web's `ThisWeekStrip.svelte`. Renders the seven days of the REAL calendar
/// week containing [now] (starting on the user's `week_start_day` pref), each
/// cell scaled by that day's logged distance, with the busiest day filling
/// the track. Distinct from `current_week_strip.dart`, which anchors to the
/// plan's week bucket on the plan-detail screen, not the calendar.
///
/// The day-bucketing + windowing live in the pure `currentWeek` helper
/// (`current_week.dart`, the Dart half of a registered parity pair with web's
/// `current_week.ts` — same algorithm, edge cases, outputs and test counts,
/// not the same bytes; "byte-identical" in this repo means the iOS twin of a
/// Dart file, decisions § 39);
/// this widget is presentation only. Self-hides nothing — a zeroed week still
/// renders the empty frame, matching web.
class ThisWeekStrip extends StatelessWidget {
  final List<Run> runs;
  final DistanceUnit unit;
  final String weekStartDay;
  final DateTime now;

  const ThisWeekStrip({
    super.key,
    required this.runs,
    required this.unit,
    required this.weekStartDay,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tag = activeLocaleTag;

    final ws = weekStartDay == 'sunday' ? WeekStart.sunday : WeekStart.monday;
    final week = currentWeek(
      [
        for (final r in runs)
          WeekActivity(
            startedAt: r.startedAt.toIso8601String(),
            distanceM: r.distanceMetres,
          ),
      ],
      ws,
      now,
    );

    final maxDistance = week.days.fold<double>(
      0,
      (m, d) => d.distanceM > m ? d.distanceM : m,
    );

    final totalLabel = UnitFormat.distance(week.totalDistanceM, unit);
    final countLabel = l10n.dashboardWeekStripCount(week.totalCount);

    return Semantics(
      label: l10n.dashboardWeekStripTitle,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ChartCardHeader(
              title: l10n.dashboardWeekStripTitle,
              note: '$totalLabel · $countLabel',
            ),
          ),
          // IntrinsicHeight, not a fixed cell height: the cells must stay
          // uniform, but the tallest one has to be able to grow past 76 when
          // the OS text scale makes two label lines plus the fill lane
          // exceed it. Sizing each cell independently would desynchronise
          // the row (a "·" rest day is shorter than a "12.34 km" day).
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final day in week.days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _DayCell(
                        day: day,
                        maxDistance: maxDistance,
                        unit: unit,
                        tag: tag,
                        l10n: l10n,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  /// The bar lane's height — exactly the slack the old fixed 76 px cell left
  /// after its border, padding and two label lines at 1.0x text scale, now
  /// named so the cell grows around it instead of the lane shrinking away.
  static const double _fillLaneHeight = 30;

  final WeekDay day;
  final double maxDistance;
  final DistanceUnit unit;
  final String tag;
  final AppLocalizations l10n;

  const _DayCell({
    required this.day,
    required this.maxDistance,
    required this.unit,
    required this.tag,
    required this.l10n,
  });

  /// Fill fraction (0..1) for the bar, floored at a visible sliver for a
  /// logged-but-tiny day. Mirrors web's `barPct` / 100.
  double get _fill {
    if (maxDistance <= 0 || day.distanceM <= 0) return 0;
    final f = day.distanceM / maxDistance;
    return f < 0.08 ? 0.08 : f;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A WeekDay carries only its ISO date; build a DateTime to localize the
    // weekday label. Parsing the local-date ISO yields local midnight.
    final date = DateTime.parse(day.iso);
    final dow = formatDow(date, tag);
    final logged = day.count > 0;
    final distLabel =
        logged ? UnitFormat.distance(day.distanceM, unit) : null;

    final palette = ChartPalette.of(context);
    // "Today" is a state marker, not data, so it keeps the interaction accent —
    // and staying off the chart palette is what keeps it from reading as a bar.
    final border = day.isToday
        ? Border.all(color: theme.colorScheme.primary, width: 1.5)
        : Border.all(color: theme.dividerColor);
    final bg = logged
        ? palette.ramp.first.withValues(alpha: 0.18)
        : theme.colorScheme.surface;

    return Semantics(
      label: logged
          ? l10n.dashboardWeekStripDayAria(dow, distLabel!)
          : l10n.dashboardWeekStripDayRestAria(dow),
      child: Opacity(
        opacity: day.isFuture ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: bg,
            border: border,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dow,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
              // A fixed lane, not Expanded: the bar IS the data, and under
              // the old fixed 76 px cell the two label lines ate the whole
              // cell at 2x OS text scale, leaving the lane zero-high — the
              // chart rendered blank exactly for the users who most need it.
              SizedBox(
                height: _fillLaneHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: _fill,
                    widthFactor: 0.5,
                    child: Container(
                      decoration: BoxDecoration(
                        color: palette.bar,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                logged ? distLabel! : '·',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: logged
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
