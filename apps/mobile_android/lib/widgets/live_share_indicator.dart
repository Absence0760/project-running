import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors;

import '../l10n/gen/app_localizations.dart';

/// The persistent "you are live sharing this run" indicator on the
/// recording screen (issue #613). A compact pill — a live dot + label +
/// broadcast glyph — that stands in the recording chrome while a live-share
/// broadcast is active, so a runner who shared a link (or was nudged into
/// it for safety) has a standing, glanceable confirmation the feed is on
/// plus a tap target to re-share or stop it. Before this, a broadcasting
/// run looked identical to a private one.
///
/// Store/api-free: it takes only an [onTap] so it stays unit-testable; the
/// run screen owns the side effects (re-open the OS share sheet / conclude
/// the broadcast).
class LiveShareIndicator extends StatelessWidget {
  final VoidCallback onTap;
  const LiveShareIndicator({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liveColor = AppSemanticColors.of(context).success;
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Semantics(
          button: true,
          label: l10n.runLiveShareActiveSemantics,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: liveColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.runLiveShareActive,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: liveColor,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.podcasts, size: 14, color: liveColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The action the runner picked from [showLiveShareSheet].
enum LiveShareAction { reshare, stop }

/// The action sheet the [LiveShareIndicator] opens: re-share the link or
/// stop the live share. Resolves the chosen [LiveShareAction] (null on
/// dismiss) so the caller owns the actual side effects — this keeps the
/// sheet store/api-free and unit-testable.
Future<LiveShareAction?> showLiveShareSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<LiveShareAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppSemanticColors.of(ctx).success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.runLiveShareSheetTitle,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(l10n.runLiveShareReshare),
              onTap: () => Navigator.of(ctx).pop(LiveShareAction.reshare),
            ),
            ListTile(
              leading: Icon(Icons.stop_circle_outlined,
                  color: theme.colorScheme.error),
              title: Text(
                l10n.runLiveShareStop,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => Navigator.of(ctx).pop(LiveShareAction.stop),
            ),
          ],
        ),
      );
    },
  );
}
