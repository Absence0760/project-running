import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppSemanticColors, ChartCardHeader, StatTile, StatusPill, StatusPillSize;

import '../coach_load.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../plan_ramp.dart';
import '../preferences.dart';
import '../self_load.dart';

/// Dashboard "Training load ramp" card — the runner's own acute:chronic
/// workload ratio, the band it lands in, and what that means. Self-hides on an
/// ungradeable band: a zeroed ratio would read as a reassuring "safe", and the
/// sibling analytics cards hide the same way rather than showing a zeroed stat.
///
/// Mirrors the web `LoadRampCard.svelte`; the grading lives in `self_load.dart`
/// (the Dart twin of `self_load.ts`), so the phone and the web cannot put the
/// same week in different bands.
class LoadRampCard extends StatelessWidget {
  final List<RunForVolume> runs;
  final DateTime now;

  const LoadRampCard({super.key, required this.runs, required this.now});

  @override
  Widget build(BuildContext context) {
    final load = selfLoad(runs, now.millisecondsSinceEpoch);
    if (!shouldSurfaceSelfLoad(load)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final semantic = AppSemanticColors.of(context);

    // A band is a status role, so each takes the semantic vocabulary rather
    // than a bespoke hue — except `low`, which is deliberately informational:
    // running below your own base is a taper, not a hazard. The insufficient
    // arm is unreachable past the guard above and exists only to keep the
    // switch exhaustive.
    final (Color fill, Color fg, String bandLabel, String meaning) =
        switch (load.band) {
      InjuryRiskBand.optimal => (
          semantic.success,
          semantic.onSuccess,
          l10n.loadRampBandOptimal,
          l10n.loadRampMeaningOptimal,
        ),
      InjuryRiskBand.elevated => (
          semantic.warning,
          semantic.onWarning,
          l10n.loadRampBandElevated,
          l10n.loadRampMeaningElevated,
        ),
      InjuryRiskBand.high => (
          semantic.danger,
          semantic.onDanger,
          l10n.loadRampBandHigh,
          l10n.loadRampMeaningHigh,
        ),
      InjuryRiskBand.low || InjuryRiskBand.insufficient => (
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer,
          l10n.loadRampBandLow,
          l10n.loadRampMeaningLow,
        ),
    };

    final trend = switch (load.trend) {
      LoadTrend.ramping => l10n.loadRampTrendRamping,
      LoadTrend.steady => l10n.loadRampTrendSteady,
      LoadTrend.tapering => l10n.loadRampTrendTapering,
    };

    return Card(
      key: const Key('dashboardLoadRampCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: ChartCardHeader(title: l10n.loadRampTitle)),
                const SizedBox(width: 8),
                StatusPill(
                  key: const Key('dashboardLoadRampBand'),
                  label: bandLabel,
                  foreground: fg,
                  fill: fill,
                  size: StatusPillSize.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              // The decimal separator is locale-dependent (1,60 in de), so the
              // ratio goes through intl rather than toStringAsFixed.
              '${formatFixed(load.ratio, 2, activeLocaleTag)}×',
              key: const Key('dashboardLoadRampRatio'),
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              l10n.loadRampRatioCaption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(meaning, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatTile.small(
                    icon: Icons.calendar_view_week,
                    label: l10n.loadRampAcuteLabel,
                    value: formatDistanceForPref(load.acuteM),
                  ),
                ),
                Expanded(
                  child: StatTile.small(
                    icon: Icons.timeline,
                    label: l10n.loadRampChronicLabel,
                    value: formatDistanceForPref(load.chronicWeeklyM),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              trend,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
