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
                    FitnessStat(label: 'VO₂ max', value: fmt(snapshot.vo2Max)),
                    FitnessStat(label: 'VDOT', value: fmt(snapshot.vdot)),
                    FitnessStat(
                      label: 'Runs',
                      value: '${snapshot.qualifyingRunCount}',
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
                    ),
                    FitnessStat(
                      label: 'Fatigue (ATL)',
                      value: fmt(snapshot.acuteLoad, digits: 0),
                    ),
                    FitnessStat(
                      label: 'Form (TSB)',
                      value: fmt(snapshot.trainingStressBal, digits: 0),
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
  const FitnessStat({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
  }
}
