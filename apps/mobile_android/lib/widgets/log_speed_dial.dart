import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppMotion, motionDuration;

import '../l10n/gen/app_localizations.dart';
import 'log_sheet.dart';

// The docked centre Log FAB sits with its centre on the top edge of the 64 dp
// BottomAppBar (`centerDocked`), so its centre is this far above the screen
// bottom. The fan items radiate out from that anchor.
const double _kBarHeight = 64;
// Radius of the arc the three icons sit on, measured from the FAB centre.
// The radius has to keep `_kItemWidth <= 0.74 * _kArcRadius` (0.74 is the
// side slots' horizontal unit): below that the top-centre item's label runs
// into the two lower icons, which sit at the label's own height.
const double _kArcRadius = 128;
const double _kItemSize = 52;
// Width of the whole item (icon above its label), and the gap between them.
// Wider than the icon so the label has room to wrap instead of ellipsising in
// the longer locales.
const double _kItemWidth = 84;
const double _kLabelGap = 6;

// Unit offsets (x from centre, y upward) for the three slots: one directly
// above, one down-left, one down-right — a shallow arc over the button, not a
// vertical stack. Scaled by [_kArcRadius].
const List<Offset> _kSlotUnits = [
  Offset(0, 1), // top-centre (highest) — the recent action
  Offset(-0.74, 0.67), // left, a bit lower
  Offset(0.74, 0.67), // right, a bit lower
];

// Slot units when fanning from an [anchor] (the NavigationRail Log button on
// expanded layouts): a shallow arc opening to the right of the anchor.
const List<Offset> _kAnchoredSlotUnits = [
  Offset(1, 0), // directly right — the recent action
  Offset(0.67, 0.74), // right, above
  Offset(0.67, -0.74), // right, below
];

/// Fan the three capture actions (Run / Lift / Food) out as labelled buttons
/// in a shallow arc around the centre Log FAB, over a dismiss scrim. Resolves
/// to the picked [LogAction], or null on scrim tap / back — same contract as
/// [showLogSheet] so the caller (HomeScreen) still owns the navigation.
/// Distinct from the History Log FAB, which keeps the bottom sheet.
Future<LogAction?> showLogSpeedDial({
  required BuildContext context,
  LogAction? recent,
  Offset? anchor,
}) {
  final overlay = Overlay.of(context);
  final completer = Completer<LogAction?>();
  final fabCentreFromBottom = MediaQuery.paddingOf(context).bottom + _kBarHeight;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _LogSpeedDial(
      recent: recent,
      fabCentreFromBottom: fabCentreFromBottom,
      anchor: anchor,
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

  /// Global centre of the launching button. Null means the default
  /// bottom-docked centre FAB; non-null fans the arc to the right of the
  /// anchor instead (the NavigationRail Log button on expanded layouts).
  final Offset? anchor;
  final void Function(LogAction? action) onClose;

  const _LogSpeedDial({
    required this.recent,
    required this.fabCentreFromBottom,
    required this.anchor,
    required this.onClose,
  });

  @override
  State<_LogSpeedDial> createState() => _LogSpeedDialState();
}

class _LogSpeedDialState extends State<_LogSpeedDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.brief);
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Zero duration completes `forward()` synchronously, so under
    // reduce-motion the fan is simply present rather than flying out.
    _controller.duration = motionDuration(context, AppMotion.brief);
    if (_controller.value == 0 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

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
    final screen = MediaQuery.sizeOf(context);
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
                _item(context, l10n, actions[i], i, actions.length, screen),
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
    Size screen,
  ) {
    final theme = Theme.of(context);
    final (icon, label) = switch (action) {
      LogAction.run => (Icons.directions_run, l10n.logRun),
      LogAction.lift => (Icons.fitness_center, l10n.logLift),
      LogAction.food => (Icons.restaurant, l10n.logFood),
    };
    final unit =
        widget.anchor == null ? _kSlotUnits[index] : _kAnchoredSlotUnits[index];
    // Stagger the entrance so the icons pop out of the button in turn.
    final start = (index / count) * 0.4;
    final anim = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: AppMotion.curveOvershoot),
    );
    final button = Semantics(
      button: true,
      label: label,
      child: Tooltip(
        // The visible label wraps to two lines and then ellipsises; the
        // tooltip still carries the full string for the longest locales.
        message: label,
        child: SizedBox(
          width: _kItemWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: theme.colorScheme.secondaryContainer,
                shape: const CircleBorder(),
                elevation: 3,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _close(action),
                  child: SizedBox(
                    width: _kItemSize,
                    height: _kItemSize,
                    child:
                        Icon(icon, color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              ),
              const SizedBox(height: _kLabelGap),
              Material(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
                elevation: 2,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  // The enclosing Semantics already announces the label; the
                  // Text would otherwise make a screen reader say it twice.
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
        final anchor = widget.anchor;
        // Anchored on the icon's top edge, never the item's bottom: the label
        // wraps to a second line in the longer locales, so a bottom-anchored
        // item would shove its own icon off the arc by its label's height.
        final iconTop = anchor == null
            ? screen.height - widget.fabCentreFromBottom - up - _kItemSize / 2
            : anchor.dy - up - _kItemSize / 2;
        return Positioned(
          left: (anchor?.dx ?? screen.width / 2) + dx - _kItemWidth / 2,
          top: iconTop,
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
