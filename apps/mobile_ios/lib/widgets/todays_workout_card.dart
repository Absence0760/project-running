import 'package:flutter/material.dart';

import '../training.dart';
import '../training_service.dart';

/// Priority card on the Run-tab idle state when the user's active plan has a
/// workout scheduled for today. Beats the last-run summary, which is already
/// behind the upcoming-event card in priority.
class TodaysWorkoutCard extends StatelessWidget {
  final ActivePlanOverview overview;
  final VoidCallback? onTap;
  const TodaysWorkoutCard({super.key, required this.overview, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = overview.todayWorkout!;
    final kind = workoutKindFromDb(w.kind);
    final done = w.completedRunId != null;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surface,
              ),
              child: Icon(
                done ? Icons.check_circle : _iconFor(kind),
                color: theme.colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    done ? 'DONE TODAY' : "TODAY'S WORKOUT",
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    workoutKindLabel(kind),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (w.targetDistanceM != null) ...[
                        Icon(Icons.straighten,
                            size: 13, color: theme.colorScheme.onPrimary),
                        const SizedBox(width: 3),
                        Text(fmtKm(w.targetDistanceM),
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                            )),
                        const SizedBox(width: 10),
                      ],
                      if (w.targetPaceSecPerKm != null) ...[
                        Icon(Icons.speed,
                            size: 13, color: theme.colorScheme.onPrimary),
                        const SizedBox(width: 3),
                        Text('@ ${fmtPace(w.targetPaceSecPerKm)}',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                            )),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(WorkoutKind k) => switch (k) {
        WorkoutKind.easy || WorkoutKind.recovery => Icons.directions_walk,
        WorkoutKind.long => Icons.directions_run,
        WorkoutKind.tempo => Icons.speed,
        WorkoutKind.interval => Icons.timelapse,
        WorkoutKind.marathonPace => Icons.flag,
        WorkoutKind.race => Icons.emoji_events,
        WorkoutKind.rest => Icons.self_improvement,
      };
}
