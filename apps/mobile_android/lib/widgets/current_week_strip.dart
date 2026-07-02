import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../training.dart';
import '../training_labels.dart';

/// Web `isWorkoutCompleted` twin — a planned workout is done when a tracked
/// run is linked OR the runner manually marked it complete.
bool _isWorkoutCompleted(PlanWorkoutRow wo) =>
    wo.completedRunId != null || wo.manuallyCompleted;

/// Focused current-week 7-day ribbon for `plan_detail_screen`, mirroring web's
/// `CurrentWeekStrip.svelte`. The 7-day window is anchored to the plan's
/// CURRENT week bucket (`startDate + weekIndex*7`), NOT the real calendar week,
/// so the strip's completion count matches the week card's count exactly. The
/// row is Monday-first to match the month `PlanCalendar` on the same screen.
class CurrentWeekStrip extends StatelessWidget {
  final DateTime startDate;
  final int weekIndex;
  final List<PlanWorkoutRow> weekWorkouts;
  final void Function(PlanWorkoutRow workout)? onSelect;

  const CurrentWeekStrip({
    super.key,
    required this.startDate,
    required this.weekIndex,
    required this.weekWorkouts,
    this.onSelect,
  });

  static String _toIso(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  static Color _kindColor(ThemeData theme, WorkoutKind k) {
    switch (k) {
      case WorkoutKind.easy:
      case WorkoutKind.recovery:
        return theme.colorScheme.outline;
      case WorkoutKind.long:
      case WorkoutKind.race:
        return theme.colorScheme.primary;
      case WorkoutKind.tempo:
        return const Color(0xFFC98ECF);
      case WorkoutKind.interval:
      case WorkoutKind.walkRun:
        return const Color(0xFFD97A54);
      case WorkoutKind.marathonPace:
        return const Color(0xFFE6A96B);
      case WorkoutKind.rest:
        return theme.dividerColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final today = _toIso(DateTime.now());

    final byDate = <String, PlanWorkoutRow>{
      for (final w in weekWorkouts) _toIso(w.scheduledDate): w,
    };
    final weekStart = startDate.add(Duration(days: weekIndex * 7));
    final cells = [
      for (var i = 0; i < 7; i++) weekStart.add(Duration(days: i)),
    ];

    final done = weekWorkouts.where(_isWorkoutCompleted).length;
    final active = weekWorkouts
        .where((w) => w.kind != 'rest' && !isWorkoutSkipped(w.skippedAt))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.planDetailCurrentWeek,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text('$done / $active',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
        Row(
          children: [
            for (final d in cells)
              Expanded(
                child: _buildCell(
                  theme,
                  l10n,
                  tag,
                  d,
                  byDate[_toIso(d)],
                  today,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCell(
    ThemeData theme,
    AppLocalizations l10n,
    String tag,
    DateTime day,
    PlanWorkoutRow? wo,
    String today,
  ) {
    final isToday = _toIso(day) == today;
    final kind = wo == null ? null : workoutKindFromDb(wo.kind);
    final kindColor = kind == null ? null : _kindColor(theme, kind);
    final isDone = wo != null && _isWorkoutCompleted(wo);

    final base = Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        color: wo == null
            ? Colors.transparent
            : (isDone
                ? theme.colorScheme.tertiaryContainer
                : theme.colorScheme.surfaceContainerHigh),
        border: Border.all(
          color: isToday ? theme.colorScheme.primary : theme.dividerColor,
          width: isToday ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      foregroundDecoration: wo != null
          ? BoxDecoration(
              border: Border(left: BorderSide(color: kindColor!, width: 3)),
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            formatDow(day, tag),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              fontSize: 9,
            ),
          ),
          if (wo != null) ...[
            Text(
              workoutKindLabel(l10n, kind!).toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: kindColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (wo.targetDistanceM != null && wo.kind != 'rest')
              Text(
                fmtKm(wo.targetDistanceM, 1),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 9,
                ),
              ),
            if (isDone)
              Align(
                alignment: Alignment.bottomRight,
                child: Icon(Icons.check_circle,
                    size: 11, color: theme.colorScheme.tertiary),
              ),
          ],
        ],
      ),
    );

    if (wo == null) return base;
    return InkWell(
      onTap: onSelect == null ? null : () => onSelect!(wo),
      borderRadius: BorderRadius.circular(6),
      child: base,
    );
  }
}
