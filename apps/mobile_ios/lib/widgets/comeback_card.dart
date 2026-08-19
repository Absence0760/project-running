import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppSemanticColors, ChartCardHeader, StatTile, StatusPill, StatusPillSize;

import '../comeback.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_ramp.dart';
import '../preferences.dart';

/// Dashboard "Coming back from a break" card — how this week compares with the
/// weeks the runner was doing before their layoff. Self-hides when there is no
/// break to speak to, no usable pre-break base, or no running this week.
///
/// Mirrors the web `ComebackCard.svelte`, and stands down whenever the load
/// ramp card is speaking: `comebackLoad` fires only where `selfLoad` is silent,
/// so the dashboard mounts both and never has to choose between them.
class ComebackCard extends StatelessWidget {
  final List<RunForVolume> runs;
  final DateTime now;

  const ComebackCard({super.key, required this.runs, required this.now});

  @override
  Widget build(BuildContext context) {
    final load = comebackLoad(runs, now.millisecondsSinceEpoch);
    if (!shouldSurfaceComeback(load)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final semantic = AppSemanticColors.of(context);

    // A steep first week is a caution, not an emergency: the danger role stays
    // with the load-ramp card's `high` band, which describes a runner whose own
    // recent base says they are spiking. The insufficient arm is unreachable
    // past the guard above and exists only to keep the switch exhaustive.
    final (Color fill, Color fg, String verdict, String meaning) =
        switch (load.verdict) {
      ComebackVerdict.steep => (
          semantic.warning,
          semantic.onWarning,
          l10n.comebackVerdictSteep,
          l10n.comebackMeaningSteep,
        ),
      ComebackVerdict.easingIn || ComebackVerdict.insufficient => (
          semantic.success,
          semantic.onSuccess,
          l10n.comebackVerdictEasingIn,
          l10n.comebackMeaningEasingIn,
        ),
    };

    // Percent style rather than a fixed-digit format: the symbol's placement
    // and the decimal separator are both locale-dependent.
    final share = (NumberFormat.percentPattern(activeLocaleTag)
          ..maximumFractionDigits = 0)
        .format(load.share);

    return Card(
      key: const Key('dashboardComebackCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: ChartCardHeader(title: l10n.comebackTitle)),
                const SizedBox(width: 8),
                StatusPill(
                  key: const Key('dashboardComebackVerdict'),
                  label: verdict,
                  foreground: fg,
                  fill: fill,
                  size: StatusPillSize.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.comebackLayoff(load.layoffWeeks),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              share,
              key: const Key('dashboardComebackShare'),
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              l10n.comebackShareCaption,
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
                    label: l10n.comebackThisWeekLabel,
                    value: formatDistanceForPref(load.thisWeekM),
                  ),
                ),
                Expanded(
                  child: StatTile.small(
                    icon: Icons.timeline,
                    label: l10n.comebackBaseLabel,
                    value: formatDistanceForPref(load.preLayoffWeeklyM),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.comebackFootnote,
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
