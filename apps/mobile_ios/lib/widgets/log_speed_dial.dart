import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import 'log_sheet.dart';

// The docked centre Log FAB sits with its centre on the top edge of the 64 dp
// BottomAppBar (`centerDocked`), so its centre is this far above the screen
// bottom. The fan items radiate out from that anchor.
const double _kBarHeight = 64;
// Radius of the arc the three icons sit on, measured from the FAB centre.
const double _kArcRadius = 96;
const double _kItemSize = 52;

// Unit offsets (x from centre, y upward) for the three slots: one directly
// above, one down-left, one down-right — a shallow arc over the button, not a
// vertical stack. Scaled by [_kArcRadius].
const List<Offset> _kSlotUnits = [
  Offset(0, 1), // top-centre (highest) — the recent action
  Offset(-0.74, 0.67), // left, a bit lower
  Offset(0.74, 0.67), // right, a bit lower
];

/// Fan the three capture actions (Run / Lift / Food) out as icon-only buttons
/// in a shallow arc around the centre Log FAB, over a dismiss scrim. Resolves
/// to the picked [LogAction], or null on scrim tap / back — same contract as
/// [showLogSheet] so the caller (HomeScreen) still owns the navigation.
/// Distinct from the History Log FAB, which keeps the bottom sheet.
Future<LogAction?> showLogSpeedDial({
  required BuildContext context,
  LogAction? recent,
}) {
  final overlay = Overlay.of(context);
  final completer = Completer<LogAction?>();
  final fabCentreFromBottom = MediaQuery.paddingOf(context).bottom + _kBarHeight;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _LogSpeedDial(
      recent: recent,
      fabCentreFromBottom: fabCentreFromBottom,
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
  final double fabCentreFromBottom;
  final void Function(LogAction? action) onClose;

  const _LogSpeedDial({
    required this.recent,
    required this.fabCentreFromBottom,
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
  // old bottom sheet; the overlay is torn down at once (the fan-out is the
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
    final centreX = MediaQuery.sizeOf(context).width / 2;
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
        // One focus group so a screen reader presents the fan as a single menu.
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: l10n.logSheetTitle,
          child: Stack(
            children: [
              for (var i = 0; i < actions.length; i++)
                _item(context, l10n, actions[i], i, actions.length, centreX),
            ],
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
    double centreX,
  ) {
    final theme = Theme.of(context);
    final (icon, label) = switch (action) {
      LogAction.run => (Icons.directions_run, l10n.logRun),
      LogAction.lift => (Icons.fitness_center, l10n.logLift),
      LogAction.food => (Icons.restaurant, l10n.logFood),
    };
    final unit = _kSlotUnits[index];
    // Stagger the entrance so the icons pop out of the button in turn.
    final start = (index / count) * 0.4;
    final anim = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: Curves.easeOutBack),
    );
    final button = Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: theme.colorScheme.secondaryContainer,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _close(action),
            child: SizedBox(
              width: _kItemSize,
              height: _kItemSize,
              child: Icon(icon, color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) {
        // Ride the icon out along its slot vector as the animation runs, so it
        // emerges from behind the FAB rather than popping in place.
        final v = anim.value;
        final dx = unit.dx * _kArcRadius * v;
        final up = unit.dy * _kArcRadius * v;
        return Positioned(
          left: centreX + dx - _kItemSize / 2,
          bottom: widget.fabCentreFromBottom + up - _kItemSize / 2,
          child: Opacity(
            opacity: _controller.value.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.6 + 0.4 * _controller.value, child: child),
          ),
        );
      },
      child: button,
    );
  }
}
