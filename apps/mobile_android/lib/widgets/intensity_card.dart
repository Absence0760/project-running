import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../run_intensity.dart';

/// Dashboard card surfacing how much of the runner's recent training
/// has been spent in each HR zone — easy / moderate / hard at a glance.
/// Mirrors web's intensity-breakdown card on `/dashboard`.
///
/// Self-hides when the user has no HR zones configured (zones == null)
/// OR has no HR-tracked runs in the window. Additive — never load-
/// blocks the page; never throws back at the caller.
class IntensityCard extends StatelessWidget {
  final List<Run> runs;
  /// Resolved HR zones; null when the user hasn't configured them. The
  /// dashboard resolves these once via [parseHrZones] on
  /// `settings_sync.service.effective<Map>(SettingsKeys.hrZones)`.
  final HrZones? hrZones;
  final DateTime now;
  /// Window in days. Default 30 — matches the web card's "weekly /
  /// monthly view → 30 d" cadence.
  final int windowDays;

  const IntensityCard({
    super.key,
    required this.runs,
    required this.hrZones,
    required this.now,
    this.windowDays = 30,
  });

  @override
  Widget build(BuildContext context) {
    final zones = hrZones;
    // No zones configured → card is invisible. The Settings → HR Zones
    // tile is the canonical configuration surface; we don't want a
    // dashboard nag in the meantime.
    if (zones == null) return const SizedBox.shrink();

    final breakdown = computeIntensityBreakdown(
      runs,
      zones,
      windowDays: windowDays,
      now: now,
    );
    // Nothing to show.
    if (breakdown.hrTrackedRuns == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l10n.intensityTitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.06,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.intensityWindow(windowDays),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _SegmentedBar(breakdown: breakdown),
            const SizedBox(height: 12),
            _ZoneLegend(breakdown: breakdown),
            const SizedBox(height: 8),
            Text(
              l10n.intensityBasedOn(breakdown.hrTrackedRuns),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedBar extends StatelessWidget {
  final IntensityBreakdown breakdown;
  const _SegmentedBar({required this.breakdown});

  // Zone palette — green easy, yellow / orange moderate, red hard.
  // Matches the web `--zone-*` CSS vars + the run-detail HR-zone band.
  static const _zoneColors = <Color>[
    Color(0xFF2E7D32), // z1 easy
    Color(0xFF66BB6A), // z2 endurance
    Color(0xFFF59E0B), // z3 tempo
    Color(0xFFFB8C00), // z4 threshold
    Color(0xFFD32F2F), // z5 vo2 / sprint
  ];

  @override
  Widget build(BuildContext context) {
    final total = breakdown.totalSeconds;
    if (total <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 12,
        child: Row(
          children: [
            for (var i = 0; i < 5; i++)
              if (breakdown.zoneSeconds[i] > 0)
                Expanded(
                  flex: breakdown.zoneSeconds[i],
                  child: Container(color: _zoneColors[i]),
                ),
          ],
        ),
      ),
    );
  }
}

class _ZoneLegend extends StatelessWidget {
  final IntensityBreakdown breakdown;
  const _ZoneLegend({required this.breakdown});

  static const _labels = <String>['Z1', 'Z2', 'Z3', 'Z4', 'Z5'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = breakdown.totalSeconds;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (var i = 0; i < 5; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _SegmentedBar._zoneColors[i],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _labels[i],
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _pctLabel(breakdown.zoneSeconds[i], total),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
      ],
    );
  }

  static String _pctLabel(int s, int total) {
    if (s == 0 || total <= 0) return '0%';
    final pct = (s / total) * 100;
    // Don't show "0%" for a non-zero zone — that misreads as "didn't
    // do any of that". The cliff: anything under 1 % renders as the
    // explicit <1% marker so the runner sees it counted.
    if (pct < 1) return '<1%';
    return '${pct.round()}%';
  }
}
