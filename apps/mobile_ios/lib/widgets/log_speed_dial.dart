import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import 'log_sheet.dart';

// Geometry of the docked centre Log FAB, so the fan anchors directly above it:
// `centerDocked` centres the FAB on the top edge of the 64 dp BottomAppBar, so
// the FAB top sits one radius above that edge. The items start a small gap above
// the FAB top.
const double _kBarHeight = 64;
const double _kFabRadius = 28;
const double _kAnchorGap = 12;

/// Fan the three capture actions (Run / Lift / Food) up above the centre Log
/// FAB, over a dismiss scrim. Resolves to the picked [LogAction], or null on
/// scrim tap / back — same contract as [showLogSheet] so the caller
/// (HomeScreen) still owns the navigation. Distinct from the History Log FAB,
/// which keeps the bottom sheet.
Future<LogAction?> showLogSpeedDial({
  required BuildContext context,
  LogAction? recent,
}) {
  final overlay = Overlay.of(context);
  final completer = Completer<LogAction?>();
  final bottomOffset =
      MediaQuery.paddingOf(context).bottom + _kBarHeight + _kFabRadius * 2 + _kAnchorGap;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _LogSpeedDial(
      recent: recent,
      bottomOffset: bottomOffset,
      onClose: (action) {
        entry.remove();
        if (!completer.isCompleted) completer.complete(action);
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _LogSpeedDial extends StatefulWidget {
  final LogAction? recent;
  final double bottomOffset;
  final void Function(LogAction? action) onClose;

  const _LogSpeedDial({
    required this.recent,
    required this.bottomOffset,
    required this.onClose,
  });

  @override
  State<_LogSpeedDial> createState() => _LogSpeedDialState();
}

class _LogSpeedDialState extends State<_LogSpeedDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..forward();
  bool _closing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Hand the result straight to the caller so navigation is as snappy as the
  // old bottom sheet; the overlay is torn down at once (the fan-up is the
  // entrance flourish, there's no exit dance to wait on).
  void _close(LogAction? action) {
    if (_closing) return;
    _closing = true;
    widget.onClose(action);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = orderedLogActions(widget.recent);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _close(null),
            child: Semantics(
              button: true,
              label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, _) => ColoredBox(
                  color: Colors.black.withValues(alpha: 0.32 * _controller.value),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: widget.bottomOffset,
          child: Center(
            // One focus group so a screen reader presents the fan as a single
            // menu, mirroring the Log bottom sheet.
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: l10n.logSheetTitle,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                // Lay the actions out bottom-up so the recent one sits nearest
                // the FAB.
                verticalDirection: VerticalDirection.up,
                children: [
                  for (var i = 0; i < actions.length; i++)
                    _item(context, l10n, actions[i], i, actions.length),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _item(
    BuildContext context,
    AppLocalizations l10n,
    LogAction action,
    int index,
    int count,
  ) {
    final theme = Theme.of(context);
    final (icon, label) = switch (action) {
      LogAction.run => (Icons.directions_run, l10n.logRun),
      LogAction.lift => (Icons.fitness_center, l10n.logLift),
      LogAction.food => (Icons.restaurant, l10n.logFood),
    };
    // Stagger the entrance so the items cascade up from the button.
    final start = (index / count) * 0.5;
    final anim = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: Curves.easeOutBack),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedBuilder(
        animation: anim,
        builder: (_, child) => Opacity(
          opacity: _controller.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - anim.value) * 16),
            child: Transform.scale(
              scale: 0.8 + 0.2 * anim.value,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        ),
        child: Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: () => _close(action),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: theme.colorScheme.surface,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(label, style: theme.textTheme.labelLarge),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Icon(icon, color: theme.colorScheme.onSecondaryContainer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
