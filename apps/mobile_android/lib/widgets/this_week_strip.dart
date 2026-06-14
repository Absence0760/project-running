import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

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
/// (`current_week.dart`, byte-identical twin of web's `current_week.ts`);
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
    final theme = Theme.of(context);
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.dashboardWeekStripTitle,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '$totalLabel · $countLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Row(
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
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
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

    final border = day.isToday
        ? Border.all(color: theme.colorScheme.primary, width: 1.5)
        : Border.all(color: theme.dividerColor);
    final bg = logged
        ? theme.colorScheme.primary.withValues(alpha: 0.10)
        : theme.colorScheme.surface;

    return Semantics(
      label: logged
          ? l10n.dashboardWeekStripDayAria(dow, distLabel!)
          : l10n.dashboardWeekStripDayRestAria(dow),
      child: Opacity(
        opacity: day.isFuture ? 0.55 : 1,
        child: Container(
          height: 76,
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
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: _fill,
                    widthFactor: 0.5,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(3),
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
