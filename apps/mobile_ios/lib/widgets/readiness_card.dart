import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, ChartCardHeader;

import '../l10n/gen/app_localizations.dart';
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

  /// The training-load series the dashboard already computed (once, with the
  /// decided lift set). When provided, the card's TSB comes from it so
  /// readiness can't disagree with the displayed form number or the chart —
  /// and the O(runs) aggregation isn't re-run. Standalone callers omit it.
  final List<TrainingLoadPoint>? loadSeries;

  const ReadinessCard({
    super.key,
    required this.runs,
    required this.now,
    this.hrPrefs = const HrPrefs(),
    this.loadSeries,
  });

  @override
  Widget build(BuildContext context) {
    // TSB from the same training-load series the chart + fitness card use,
    // so readiness can't disagree with the displayed form number (round-5 pro).
    final series =
        loadSeries ?? computeTrainingLoadSeries(runs, prefs: hrPrefs, endDate: now);
    final load = (series.isNotEmpty &&
            (series.last.ctl > 0 || series.last.atl > 0))
        ? series.last
        : null;
    if (load == null) return const SizedBox.shrink();
    final tsb = load.tsb;

    final readiness = computeReadiness(ReadinessInputs(tsb: tsb));
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accent = _bandAccent(AppSemanticColors.of(context), readiness.band);

    return Card(
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
            ChartCardHeader(
              title: l10n.readinessCardHeader,
              action: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _bandLabel(l10n, readiness.band),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
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
                color: theme.colorScheme.onSurfaceVariant,
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

  static Color _bandAccent(AppSemanticColors semantic, ReadinessBand band) =>
      switch (band) {
        ReadinessBand.high => semantic.success,
        ReadinessBand.moderate => semantic.warning,
        ReadinessBand.low => semantic.danger,
      };

  static String _bandLabel(AppLocalizations l10n, ReadinessBand band) =>
      switch (band) {
        ReadinessBand.high => l10n.readinessBandHigh,
        ReadinessBand.moderate => l10n.readinessBandModerate,
        ReadinessBand.low => l10n.readinessBandLow,
      };
}

class _ContributorChip extends StatelessWidget {
  final ReadinessContribution contribution;
  const _ContributorChip({required this.contribution});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.ofTheme(theme);
    final color = contribution.delta > 0
        ? semantic.success
        : contribution.delta < 0
            ? semantic.danger
            : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            contribution.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
