import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, StatusPill;

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
///
/// Suppressing the *verdict* must not suppress what the card still knows.
/// [LiveCutoffEta.requiredPaceSecPerKm] does not depend on recent pace, so the
/// go/no-go number survives the stale branch — labelled from the last fix, so
/// it can't be read as measured from where the runner is now. And an expired
/// limit ([LiveCutoffEta.limitPassed]) is stated outright rather than left
/// behind "Signal lost": the deadline is gone whether or not the fix is
/// current, and it is the fact the crew at the checkpoint is deciding on.
/// The two never co-render — a passed limit is exactly when required pace is
/// null, and the flag exists so this surface never fires off the *other* null
/// (a checkpoint under 50 m away).
class CutoffCard extends StatelessWidget {
  final LiveCutoffEta eta;
  final bool stale;
  const CutoffCard({super.key, required this.eta, required this.stale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final l10n = AppLocalizations.of(context);
    final unknown = eta.status == LiveCutoffStatus.unknown;
    final label = eta.checkpoint!.label.trim();
    final title = label.isEmpty ? l10n.liveCutoffTitle : label;

    final (chipColor, chipLabel) = switch (eta.status) {
      LiveCutoffStatus.behind => (
          semantic.danger,
          l10n.liveCutoffBehind(_marginLabel(eta.marginS!.abs())),
        ),
      LiveCutoffStatus.tight => (
          semantic.warning,
          l10n.liveCutoffAhead(_marginLabel(eta.marginS!)),
        ),
      LiveCutoffStatus.on => (
          semantic.success,
          l10n.liveCutoffAhead(_marginLabel(eta.marginS!)),
        ),
      LiveCutoffStatus.unknown => (theme.colorScheme.onSurfaceVariant, ''),
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
          if (eta.limitPassed)
            StatusPill(
              label: l10n.liveCutoffExpired,
              foreground: semantic.danger,
              fill: semantic.danger.withValues(alpha: 0.15),
            )
          else if (eta.requiredPaceSecPerKm != null &&
              eta.status != LiveCutoffStatus.on)
            Text(
              stale
                  ? l10n.liveCutoffRequiredPaceStale(
                      formatPaceForPref(eta.requiredPaceSecPerKm!))
                  : l10n.liveCutoffRequiredPace(
                      formatPaceForPref(eta.requiredPaceSecPerKm!)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (eta.limitPassed ||
              (eta.requiredPaceSecPerKm != null &&
                  eta.status != LiveCutoffStatus.on))
            const SizedBox(height: 8),
          if (unknown)
            Text(
              stale ? l10n.liveCutoffSignalLost : l10n.liveCutoffWaitingSignal,
              style: theme.textTheme.bodySmall?.copyWith(
                color: stale
                    ? semantic.warning
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: stale ? FontWeight.w700 : null,
                fontStyle: stale ? null : FontStyle.italic,
              ),
            )
          else
            Row(
              children: [
                Flexible(
                  child: StatusPill(
                    label: chipLabel,
                    foreground: chipColor,
                    fill: chipColor.withValues(alpha: 0.15),
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
