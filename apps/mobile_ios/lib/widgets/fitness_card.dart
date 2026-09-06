import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show ChartCardHeader, StatTile;

import '../fitness.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../training_load.dart';

/// Dashboard "Fitness" card — VO₂ max / VDOT / qualifying-run count
/// on the top row, training-load (CTL / ATL / TSB) on the second, plus
/// a recovery-advice line. Returns nothing when the user has no
/// qualifying runs (otherwise the card is all "—" and noise).
///
/// Renders the same numbers as the web `/fitness` summary. The lockstep is
/// not this widget's: it belongs to the registered `fitness` pair, whose Dart
/// half is `fitness.dart` — edit there and the matching change appears here.
class FitnessCard extends StatelessWidget {
  final List<Run> runs;
  final DateTime now;
  final HrPrefs hrPrefs;

  /// The training-load series the dashboard already computed (once, with the
  /// decided lift set). When provided, the card reads CTL/ATL/TSB + advice from
  /// it so its numbers match the chart exactly — and the O(runs) aggregation
  /// isn't re-run here. Standalone callers (e.g. tests) omit it and the card
  /// falls back to computing a run-only series itself.
  final List<TrainingLoadPoint>? loadSeries;
  const FitnessCard({
    super.key,
    required this.runs,
    required this.now,
    this.hrPrefs = const HrPrefs(),
    this.loadSeries,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = computeSnapshot(runs, now: now);
    if (snapshot.qualifyingRunCount == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // CTL / ATL / TSB + the advice come from the SAME training-load series
    // the chart below uses, so the number, the advice, and the curve can't
    // contradict each other (round-5 pro). VO₂max / VDOT / qualifying stay
    // on computeSnapshot.
    final series =
        loadSeries ?? computeTrainingLoadSeries(runs, prefs: hrPrefs, endDate: now);
    final load = (series.isNotEmpty &&
            (series.last.ctl > 0 || series.last.atl > 0))
        ? series.last
        : null;
    final returningFromLayoff = isReturningFromLayoff(runs, now: now);
    final advice = recoveryAdvice(
      load?.tsb,
      load?.ctl,
      returningFromLayoff: returningFromLayoff,
    );
    // Forward-looking companion to the advice line: days of easy running
    // until the next hard session. Shown only when currently loaded
    // (≥1 day out) and not a comeback (advice already says rebuild slowly).
    final daysToHard = returningFromLayoff
        ? null
        : daysUntilNextHardSession(load?.atl, load?.ctl);

    String fmt(double? v, {int digits = 1}) =>
        v == null ? '—' : formatFixed(v, digits, activeLocaleTag);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChartCardHeader(title: l10n.fitnessTitle),
            const SizedBox(height: 10),
            // Each stat is Expanded so the row degrades by ellipsizing
            // labels instead of overflowing — the expanded (tablet)
            // dashboard mounts this card in a ~half-width grid column.
            Row(
              children: [
                Expanded(
                  child: FitnessStat(
                    label: l10n.fitnessStatVo2Max,
                    value: fmt(snapshot.vo2Max),
                    tooltip: l10n.fitnessStatVo2MaxTooltip,
                  ),
                ),
                Expanded(
                  child: FitnessStat(
                    label: l10n.fitnessStatVdot,
                    value: fmt(snapshot.vdot),
                    tooltip: l10n.fitnessStatVdotTooltip,
                  ),
                ),
                Expanded(
                  child: FitnessStat(
                    label: l10n.fitnessStatRuns,
                    value: '${snapshot.qualifyingRunCount}',
                    tooltip: l10n.fitnessStatRunsTooltip,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FitnessStat(
                    label: l10n.fitnessStatCtl,
                    value: fmt(load?.ctl, digits: 0),
                    tooltip: l10n.fitnessStatCtlTooltip,
                  ),
                ),
                Expanded(
                  child: FitnessStat(
                    label: l10n.fitnessStatAtl,
                    value: fmt(load?.atl, digits: 0),
                    tooltip: l10n.fitnessStatAtlTooltip,
                  ),
                ),
                Expanded(
                  child: FitnessStat(
                    label: l10n.fitnessStatTsb,
                    value: fmt(load?.tsb, digits: 0),
                    tooltip: l10n.fitnessStatTsbTooltip,
                  ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          advice,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                        if (daysToHard != null && daysToHard >= 1) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Next hard session in ~$daysToHard '
                            '${daysToHard == 1 ? 'day' : 'days'} of easy running.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FitnessStat extends StatelessWidget {
  final String label;
  final String value;

  /// Optional plain-English explanation of the metric. When set, a tap opens
  /// a dialog with the explanation (and the long-press tooltip still works) so
  /// the acronym is discoverable for newer runners without a hidden gesture
  /// (#25, #267). An info glyph beside the label signals the affordance.
  final String? tooltip;
  const FitnessStat({
    super.key,
    required this.label,
    required this.value,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final hasTip = tooltip != null;
    final tile = StatTile.large(
      label: label,
      value: value,
      labelTrailing: hasTip
          ? Icon(Icons.info_outline,
              size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)
          : null,
    );
    if (!hasTip) return tile;
    return Tooltip(
      message: tooltip!,
      triggerMode: TooltipTriggerMode.longPress,
      child: InkWell(
        onTap: () => _showExplanation(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: tile,
        ),
      ),
    );
  }

  void _showExplanation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(label),
        content: Text(tooltip!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      ),
    );
  }
}
