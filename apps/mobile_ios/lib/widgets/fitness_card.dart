import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

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
/// Mirrors the web `/fitness` summary so the same numbers appear on
/// every surface — tweak `fitness.dart` (the Dart port of
/// `apps/web/src/lib/fitness.ts`) and you'll get the matching change
/// here.
class FitnessCard extends StatelessWidget {
  final List<Run> runs;
  final DateTime now;
  final HrPrefs hrPrefs;
  const FitnessCard({
    super.key,
    required this.runs,
    required this.now,
    this.hrPrefs = const HrPrefs(),
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
    final series = computeTrainingLoadSeries(runs, prefs: hrPrefs, endDate: now);
    final load = (series.isNotEmpty &&
            (series.last.ctl > 0 || series.last.atl > 0))
        ? series.last
        : null;
    final advice = recoveryAdvice(
      load?.tsb,
      load?.ctl,
      returningFromLayoff: isReturningFromLayoff(runs, now: now),
    );

    String fmt(double? v, {int digits = 1}) =>
        v == null ? '—' : formatFixed(v, digits, activeLocaleTag);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.fitnessTitle, style: theme.textTheme.titleMedium),
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
                      label: l10n.fitnessStatVo2Max,
                      value: fmt(snapshot.vo2Max),
                      tooltip: l10n.fitnessStatVo2MaxTooltip,
                    ),
                    FitnessStat(
                      label: l10n.fitnessStatVdot,
                      value: fmt(snapshot.vdot),
                      tooltip: l10n.fitnessStatVdotTooltip,
                    ),
                    FitnessStat(
                      label: l10n.fitnessStatRuns,
                      value: '${snapshot.qualifyingRunCount}',
                      tooltip: l10n.fitnessStatRunsTooltip,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    FitnessStat(
                      label: l10n.fitnessStatCtl,
                      value: fmt(load?.ctl, digits: 0),
                      tooltip: l10n.fitnessStatCtlTooltip,
                    ),
                    FitnessStat(
                      label: l10n.fitnessStatAtl,
                      value: fmt(load?.atl, digits: 0),
                      tooltip: l10n.fitnessStatAtlTooltip,
                    ),
                    FitnessStat(
                      label: l10n.fitnessStatTsb,
                      value: fmt(load?.tsb, digits: 0),
                      tooltip: l10n.fitnessStatTsbTooltip,
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
