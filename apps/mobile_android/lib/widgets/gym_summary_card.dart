import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../local_gym_store.dart';
import '../preferences.dart';
import '../screens/gym_screen.dart' show gymExerciseCount, gymWorkoutVolume;

/// Home "today's lift" summary card (multi_modal.md § Home). Self-hiding is
/// the caller's job — the dashboard only builds this when a gym workout was
/// logged today. Type-coded by the dumbbell glyph + label (not colour
/// alone). Tap opens the Gym surface.
class GymSummaryCard extends StatelessWidget {
  final StoredGymWorkout workout;
  final VoidCallback onTap;
  const GymSummaryCard({super.key, required this.workout, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final title = workout.workout.title?.trim();
    final exercises = gymExerciseCount(workout);
    final volume = gymWorkoutVolume(workout);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(Icons.fitness_center, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.homeTodaysLift,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title == null || title.isEmpty ? l10n.gymUntitled : title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      volume > 0
                          ? '${l10n.gymExercisesShort(exercises)} · '
                              '${WeightFormat.toDisplay(volume.toDouble(), activeWeightUnit).round()} '
                              '${WeightFormat.label(activeWeightUnit)}'
                          : l10n.gymExercisesShort(exercises),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
