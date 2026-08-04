import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// Persistent solo-run safety prompt on the recording screen — the
/// non-missable replacement for the old 6-second auto-dismissing banner
/// (docs/features/safety.md). It stays on screen until the runner acts:
/// [onShare] shares a live link, [onDismiss] is the explicit "Not now".
/// Both dismiss it AND stamp the throttle, so a nudge that was never seen
/// is never suppressed. Rendered in the run screen's recording chrome
/// (sibling of the off-route / GPS banners), gated on a screen-held
/// visibility flag.
class SafetyNudgeBanner extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback onDismiss;

  const SafetyNudgeBanner({
    super.key,
    required this.onShare,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.inverseSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.nightlight_round,
                    color: scheme.onInverseSurface, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.runSafetyNudgeSolo,
                    style: TextStyle(
                        color: scheme.onInverseSurface,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  child: Text(
                    l10n.runNotNow,
                    style: TextStyle(
                        color:
                            scheme.onInverseSurface.withValues(alpha: 0.75)),
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: onShare,
                  child: Text(l10n.runSafetyNudgeShareAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
