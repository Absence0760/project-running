import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../readiness.dart';
import '../training_load.dart';

/// Dashboard card surfacing the readiness-to-run score derived from
/// the user's training-stress balance. Sleep + resting-HR inputs are
/// nullable today — the pure helper handles partial data so this
/// card grows richer as Health Connect / HealthKit reads come online.
/// Hides itself when there's no TSB signal (insufficient run history).
class ReadinessCard extends StatelessWidget {
  final List<Run> runs;
  final DateTime now;
  final HrPrefs hrPrefs;

  const ReadinessCard({
    super.key,
    required this.runs,
    required this.now,
    this.hrPrefs = const HrPrefs(),
  });

  @override
  Widget build(BuildContext context) {
    // TSB from the same training-load series the chart + fitness card use,
    // so readiness can't disagree with the displayed form number (round-5 pro).
    final series = computeTrainingLoadSeries(runs, prefs: hrPrefs, endDate: now);
    final load = (series.isNotEmpty &&
            (series.last.ctl > 0 || series.last.atl > 0))
        ? series.last
        : null;
    if (load == null) return const SizedBox.shrink();
    final tsb = load.tsb;

    final readiness = computeReadiness(ReadinessInputs(tsb: tsb));
    final theme = Theme.of(context);
    final accent = _bandAccent(readiness.band);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: accent, width: 4),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'READINESS',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.06,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _bandLabel(readiness.band),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${readiness.score}',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              readiness.advice,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (readiness.contributors.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final c in readiness.contributors)
                    _ContributorChip(contribution: c),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _bandAccent(ReadinessBand band) => switch (band) {
        ReadinessBand.high => const Color(0xFF2E7D32),
        ReadinessBand.moderate => const Color(0xFFF59E0B),
        ReadinessBand.low => const Color(0xFFD32F2F),
      };

  static String _bandLabel(ReadinessBand band) => switch (band) {
        ReadinessBand.high => 'high',
        ReadinessBand.moderate => 'moderate',
        ReadinessBand.low => 'low',
      };
}

class _ContributorChip extends StatelessWidget {
  final ReadinessContribution contribution;
  const _ContributorChip({required this.contribution});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = contribution.delta > 0
        ? const Color(0xFF2E7D32)
        : contribution.delta < 0
            ? const Color(0xFFD32F2F)
            : theme.colorScheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          contribution.name,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          contribution.delta > 0
              ? '+${contribution.delta}'
              : '${contribution.delta}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
