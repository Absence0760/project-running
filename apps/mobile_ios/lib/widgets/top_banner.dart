import 'dart:async';

import 'package:flutter/material.dart';

/// Top-anchored notification pill — the canonical replacement for
/// `ScaffoldMessenger.of(context).showSnackBar(...)` across the mobile
/// app. Material's floating SnackBar docks at the bottom and on the
/// recording screen overlapped the Pause / Stop / Lap controls; the
/// runner couldn't reach Stop without dismissing a snack first.
/// Anchoring at the top eliminates that overlap on every screen and
/// gives notifications a consistent shape app-wide.
///
/// Renders via [Overlay] so callers don't need to plumb a banner into
/// every screen's [Scaffold] body. The pill auto-positions just below
/// the AppBar when the calling context lives under one (read via
/// [Scaffold.maybeOf]); on AppBar-less screens it sits at the safe-
/// area top.
///
/// Single-banner semantics, mirroring SnackBar: a new call coalesces
/// the existing entry — there is never more than one banner on screen.

_TopBannerEntry? _current;

/// Hard ceiling on how long ANY banner can stay on screen, even when
/// a caller passes a custom [duration]. Acts as a defence against
/// a degenerate code path (e.g. a screen scheduling a banner with
/// `Duration.zero` or a forgotten-to-dismiss action handler) so the
/// user is never stuck looking at a stale notification.
const Duration kTopBannerMaxDuration = Duration(seconds: 6);

/// Show a transient top-anchored banner. Returns immediately.
///
/// [actionLabel] + [onAction] add a tappable button (e.g. the
/// "Settings" shortcut on the GPS-unavailable banner). Tapping the
/// action runs the callback AND dismisses the banner.
///
/// Auto-dismisses after [duration] (clamped to [kTopBannerMaxDuration]).
/// Also swipe-dismissible — drag horizontally to dismiss; matches
/// the canonical Material SnackBar gesture so users don't need to
/// learn a new affordance.
///
/// Caller must pass a [context] that's under the [Navigator] /
/// [Overlay] (any screen-level context works). When no Overlay is
/// reachable (e.g. very early app boot) the call is a no-op.
void showTopBanner(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  // Clamp to the hard ceiling so a caller can never wedge a banner
  // on screen indefinitely.
  final effective = duration > kTopBannerMaxDuration
      ? kTopBannerMaxDuration
      : duration;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  // Read the AppBar height from the nearest Scaffold (if any) so the
  // pill sits below it. Captured at show-time — the Overlay context
  // is above the screen's Scaffold so the entry's own builder
  // wouldn't see it.
  final mq = MediaQuery.of(context);
  final scaffold = Scaffold.maybeOf(context);
  final appBarHeight = scaffold?.appBarMaxHeight ?? 0;
  final topInset = mq.padding.top + appBarHeight + 12;

  _current?.dismiss();
  _current = null;

  late _TopBannerEntry tracker;
  late OverlayEntry entry;
  void dismiss() {
    if (_current == tracker) _current = null;
    tracker.timer?.cancel();
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => _TopBannerWidget(
      message: message,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              dismiss();
              onAction.call();
            },
      onSwipeDismiss: dismiss,
      topInset: topInset,
    ),
  );
  overlay.insert(entry);

  final timer = Timer(effective, dismiss);
  tracker = _TopBannerEntry(dismiss: dismiss, timer: timer);
  _current = tracker;
}

/// Dismiss the currently visible banner, if any. Safe to call from
/// anywhere; no-op when nothing is shown.
void hideTopBanner() {
  _current?.dismiss();
  _current = null;
}

class _TopBannerEntry {
  final void Function() dismiss;
  final Timer? timer;
  _TopBannerEntry({required this.dismiss, required this.timer});
}

class _TopBannerWidget extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onSwipeDismiss;
  final double topInset;

  const _TopBannerWidget({
    required this.message,
    required this.topInset,
    required this.onSwipeDismiss,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: topInset,
      left: 16,
      right: 16,
      // Dismissible — swipe in any direction to dismiss.
      // `DismissDirection.up` is the primary affordance the user
      // explicitly asked for (top-anchored banner reads as
      // "push me away upwards"). Horizontal also dismisses for
      // Material SnackBar gesture parity. The two are combined via
      // a wrapping Dismissible-on-Dismissible pattern because
      // DismissDirection is an enum that doesn't bitwise-OR.
      child: Dismissible(
        key: ValueKey('top_banner:up:$message'),
        direction: DismissDirection.up,
        onDismissed: (_) => onSwipeDismiss(),
        child: Dismissible(
          key: ValueKey('top_banner:horiz:$message'),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => onSwipeDismiss(),
        child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              16,
              6,
              actionLabel == null ? 16 : 6,
              6,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surface
                  .withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 8),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The text portion is IgnorePointer'd so a tap on the
                // banner pill doesn't compete with whatever's
                // underneath; only the explicit action button is
                // interactive.
                Flexible(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        message,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }
}
