import 'package:api_client/api_client.dart' show ActivityRow;
import 'package:flutter/material.dart';

import '../activity_timeline.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart'
    show DistanceUnit, UnitFormat, WeightFormat, activeWeightUnit;

/// Unified reverse-chronological History timeline over the `activities` view
/// (runs + lifts + meals). Mirrors the web `/history` timeline (multi_modal.md
/// § History): day-grouped rows, type coded by a leading glyph + label (never
/// colour alone), each run/lift row tapping into its own detail screen; meals
/// render read-only (no detail screen yet). The caller passes an already
/// kind-filtered list.
class ActivityTimelineList extends StatelessWidget {
  final List<ActivityRow> activities;
  final DistanceUnit unit;
  final void Function(ActivityRow row) onTapRun;
  final void Function(ActivityRow row) onTapLift;
  final Future<void> Function() onRefresh;

  const ActivityTimelineList({
    super.key,
    required this.activities,
    required this.unit,
    required this.onTapRun,
    required this.onTapLift,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));

    if (activities.isEmpty) {
      // AlwaysScrollable so pull-to-refresh still works on the empty view.
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(l10n.historyTimelineEmpty,
                      style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final groups = groupActivitiesByDay(activities);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final g = groups[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(4, i == 0 ? 0 : 16, 4, 6),
                child: Text(
                  _dayLabel(l10n, tag, g.day),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.08,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              for (final a in g.rows) _ActivityRowTile(row: a, unit: unit, onTapRun: onTapRun, onTapLift: onTapLift),
            ],
          );
        },
      ),
    );
  }

  static String _dayLabel(AppLocalizations l10n, String tag, DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return l10n.historyToday;
    if (day == yesterday) return l10n.historyYesterday;
    return formatDateMed(day, tag);
  }
}

class _ActivityRowTile extends StatelessWidget {
  final ActivityRow row;
  final DistanceUnit unit;
  final void Function(ActivityRow row) onTapRun;
  final void Function(ActivityRow row) onTapLift;

  const _ActivityRowTile({
    required this.row,
    required this.unit,
    required this.onTapRun,
    required this.onTapLift,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final (icon, accent) = _glyph(row.kind, theme);
    final (primary, secondary) = _summary(l10n);
    final tappable = row.kind == 'run' || row.kind == 'lift';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.16),
          child: Icon(icon, color: accent, size: 20),
        ),
        title: Text(primary,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall),
        subtitle: secondary.isEmpty
            ? null
            : Text(secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: tappable
            ? Icon(Icons.chevron_right, color: theme.colorScheme.outline)
            : null,
        onTap: switch (row.kind) {
          'run' => () => onTapRun(row),
          'lift' => () => onTapLift(row),
          _ => null,
        },
      ),
    );
  }

  (IconData, Color) _glyph(String kind, ThemeData theme) => switch (kind) {
        'lift' => (Icons.fitness_center, const Color(0xFF4E7C5E)),
        'meal' => (Icons.restaurant, const Color(0xFF9A6B2F)),
        _ => (Icons.directions_run, theme.colorScheme.primary),
      };

  /// Per-kind (primary, secondary) lines from the thin view `summary` jsonb.
  /// Mirrors the web `activitySummary`.
  (String, String) _summary(AppLocalizations l10n) {
    final s = row.summary;
    switch (row.kind) {
      case 'lift':
        final title = s['title'];
        final setCount = (s['set_count'] as num?)?.toInt() ?? 0;
        final volume = (s['volume_kg'] as num?)?.toDouble() ?? 0;
        final parts = <String>[l10n.historySetCount(setCount)];
        if (volume > 0) {
          final v = WeightFormat.toDisplay(volume, activeWeightUnit).round();
          parts.add('$v ${WeightFormat.label(activeWeightUnit)}');
        }
        return (
          (title is String && title.isNotEmpty) ? title : l10n.gymUntitled,
          parts.join('  ·  '),
        );
      case 'meal':
        final name = s['item_name'];
        final kcal = (s['calories'] as num?)?.round();
        return (
          name is String && name.isNotEmpty ? name : '—',
          kcal != null ? l10n.historyKcal(kcal) : '',
        );
      default:
        final dist = (s['distance_m'] as num?)?.toDouble() ?? 0;
        final dur = (s['duration_s'] as num?)?.toInt() ?? 0;
        return (
          UnitFormat.distance(dist, unit),
          dur > 0 ? _formatDuration(Duration(seconds: dur)) : '',
        );
    }
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final sec = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${sec}s';
  }
}
