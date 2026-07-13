import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../live_cutoff_eta.dart';
import '../preferences.dart';

/// "Next cut-off" card — the predictive-tracking answer the ultra personas
/// actually want ("will I / will my person make it?"). Shared by the live
/// spectator screen (`/live/[id]` mirror) and the runner's own recording
/// screen so the two surfaces can't diverge: checkpoint label + distance to
/// go, and either a coloured on/tight/behind margin chip (with projected
/// arrival) when the position is fresh, or a suppressed-verdict line when the
/// status is `unknown` — never an over-claimed ETA. The suppressed state
/// splits by cause (mirroring web): a **stale** fix reads the amber "Signal
/// lost" line (a runner who went dark mid-race must not be mislabelled as
/// still starting up), while a fresh fix with no pace yet keeps the neutral
/// "waiting for a fresh signal" line.
class CutoffCard extends StatelessWidget {
  final LiveCutoffEta eta;
  final bool stale;
  const CutoffCard({super.key, required this.eta, required this.stale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unknown = eta.status == LiveCutoffStatus.unknown;
    final label = eta.checkpoint!.label.trim();
    final title = label.isEmpty ? l10n.liveCutoffTitle : label;

    final (chipColor, chipLabel) = switch (eta.status) {
      LiveCutoffStatus.behind => (
          const Color(0xFFEF4444),
          l10n.liveCutoffBehind(_marginLabel(eta.marginS!.abs())),
        ),
      LiveCutoffStatus.tight => (
          const Color(0xFFF59E0B),
          l10n.liveCutoffAhead(_marginLabel(eta.marginS!)),
        ),
      LiveCutoffStatus.on => (
          const Color(0xFF10B981),
          l10n.liveCutoffAhead(_marginLabel(eta.marginS!)),
        ),
      LiveCutoffStatus.unknown => (theme.colorScheme.outline, ''),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.liveCutoffTitle.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.liveCutoffToGo(formatDistanceForPref(eta.distanceToM)),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          if (unknown)
            Text(
              stale ? l10n.liveCutoffSignalLost : l10n.liveCutoffWaitingSignal,
              style: theme.textTheme.bodySmall?.copyWith(
                color: stale
                    ? const Color(0xFFF59E0B)
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: stale ? FontWeight.w700 : null,
                fontStyle: stale ? null : FontStyle.italic,
              ),
            )
          else
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    chipLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: chipColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (eta.projectedArrivalElapsedS != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.liveCutoffEta(
                        _formatCutoffDuration(
                          Duration(
                            seconds: eta.projectedArrivalElapsedS!.round(),
                          ),
                        ),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// H:MM:SS past an hour, M:SS under — the projected-arrival elapsed clock.
String _formatCutoffDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// A cutoff margin (seconds) rendered as `Hh Mm` / `Mm`. Always a positive
/// magnitude — the on/behind framing comes from the surrounding "ahead" /
/// "behind" copy, not a sign here.
String _marginLabel(double seconds) {
  final total = seconds.abs().round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
