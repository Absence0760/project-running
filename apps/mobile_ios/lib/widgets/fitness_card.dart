import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../fitness.dart';

/// Dashboard "Fitness" card — VO₂ max / VDOT / qualifying-run count
/// on the top row, training-load (CTL / ATL / TSB) on the second, plus
/// a recovery-advice line. Returns nothing when the user has no
/// qualifying runs (otherwise the card is all "—" and noise).
///
/// Mirrors the web `/fitness` summary so the same numbers appear on
/// every surface — tweak `fitness.dart` (the Dart port of
/// `apps/web/src/lib/fitness.ts`) and you'll get the matching change
/// here.
class FitnessCard extends StatelessWidget {
  final List<Run> runs;
  final DateTime now;
  const FitnessCard({super.key, required this.runs, required this.now});

  @override
  Widget build(BuildContext context) {
    final snapshot = computeSnapshot(runs, now: now);
    if (snapshot.qualifyingRunCount == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final advice = recoveryAdvice(
      snapshot.trainingStressBal,
      snapshot.chronicLoad,
      returningFromLayoff: isReturningFromLayoff(runs, now: now),
    );

    String fmt(double? v, {int digits = 1}) =>
        v == null ? '—' : v.toStringAsFixed(digits);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Fitness', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    FitnessStat(
                      label: 'VO₂ max',
                      value: fmt(snapshot.vo2Max),
                      tooltip:
                          'Your aerobic engine: how much oxygen your body can use per minute. Higher is fitter.',
                    ),
                    FitnessStat(
                      label: 'VDOT',
                      value: fmt(snapshot.vdot),
                      tooltip:
                          "Daniels' running-fitness score from your best recent race effort. Drives your training paces.",
                    ),
                    FitnessStat(
                      label: 'Runs',
                      value: '${snapshot.qualifyingRunCount}',
                      tooltip:
                          'Recent runs long enough to count toward your fitness estimate.',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    FitnessStat(
                      label: 'Fitness (CTL)',
                      value: fmt(snapshot.chronicLoad, digits: 0),
                      tooltip:
                          'Your rolling 42-day training load. Builds slowly; this is your endurance base.',
                    ),
                    FitnessStat(
                      label: 'Fatigue (ATL)',
                      value: fmt(snapshot.acuteLoad, digits: 0),
                      tooltip:
                          'Your last 7 days of load. Rises fast after hard sessions and drops with rest.',
                    ),
                    FitnessStat(
                      label: 'Form (TSB)',
                      value: fmt(snapshot.trainingStressBal, digits: 0),
                      tooltip:
                          'Fitness minus fatigue. Positive = fresh and race-ready; negative = carrying fatigue.',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.health_and_safety,
                        size: 18,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          advice,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class FitnessStat extends StatelessWidget {
  final String label;
  final String value;

  /// Optional plain-English explanation of the metric. When set, long-press
  /// (or the semantics tooltip) explains the acronym for newer runners (#25).
  final String? tooltip;
  const FitnessStat({
    super.key,
    required this.label,
    required this.value,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final column = Column(
      children: [
        Text(value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 4),
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            )),
      ],
    );
    if (tooltip == null) return column;
    return Tooltip(
      message: tooltip!,
      triggerMode: TooltipTriggerMode.longPress,
      child: column,
    );
  }
}
