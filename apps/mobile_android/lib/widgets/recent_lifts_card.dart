import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_gym_store.dart';
import '../preferences.dart';
import '../screens/gym_screen.dart' show gymExerciseCount, gymWorkoutVolume;

/// Dashboard "Recent lifts" trend card (multi_modal.md § Home). Lists the five
/// most-recent gym sessions; mirrors web `/dashboard`'s recent-lifts card.
/// Self-hiding is the caller's job — the dashboard only builds this when the
/// gym store has a session — but it also renders nothing when handed an empty
/// list (anti-clutter checklist: no empty card, no zeroed stat).
class RecentLiftsCard extends StatelessWidget {
  /// Newest-first, tombstone-free workouts (the gym store's `workouts` getter
  /// already guarantees both).
  final List<StoredGymWorkout> workouts;
  final void Function(String workoutId) onOpenWorkout;
  final VoidCallback onViewAll;

  const RecentLiftsCard({
    super.key,
    required this.workouts,
    required this.onOpenWorkout,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    if (workouts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final recent = workouts.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.dashboardSectionRecentLifts,
                    style: theme.textTheme.titleMedium),
                TextButton(
                  onPressed: onViewAll,
                  child: Text(l10n.dashboardViewAllGym),
                ),
              ],
            ),
            for (final w in recent) _liftRow(context, theme, l10n, tag, w),
          ],
        ),
      ),
    );
  }

  Widget _liftRow(BuildContext context, ThemeData theme, AppLocalizations l10n,
      String tag, StoredGymWorkout w) {
    final title = w.workout.title?.trim();
    final started = w.startedAt;
    final volume = gymWorkoutVolume(w);
    return InkWell(
      onTap: () => onOpenWorkout(w.id),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.fitness_center,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title == null || title.isEmpty ? l10n.gymUntitled : title,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (started != null)
                    Text(
                      formatDateMed(started.toLocal(), tag),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.gymExercisesShort(gymExerciseCount(w)),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                if (volume > 0)
                  Text(
                    '${WeightFormat.toDisplay(volume.toDouble(), activeWeightUnit).round()} ${WeightFormat.label(activeWeightUnit)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
              ],
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
