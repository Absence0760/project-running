import 'dart:ui';

import 'package:flutter/material.dart';

/// A bottom-pinned panel with a drag handle that can be toggled between a
/// collapsed (minimal) state and an expanded (full) state.
///
/// Tap the handle to toggle. Flick the handle up to expand, down to collapse.
/// The panel provides its own glass-blur container and safe-area padding so
/// callers only supply the content for each state.
class CollapsiblePanel extends StatefulWidget {
  final Widget expandedChild;
  final Widget collapsedChild;
  final bool initiallyExpanded;

  const CollapsiblePanel({
    super.key,
    required this.expandedChild,
    required this.collapsedChild,
    this.initiallyExpanded = true,
  });

  @override
  State<CollapsiblePanel> createState() => _CollapsiblePanelState();
}

class _CollapsiblePanelState extends State<CollapsiblePanel> {
  late bool _expanded = widget.initiallyExpanded;

  static const _flickVelocity = 200.0;
  static const _animationDuration = Duration(milliseconds: 260);

  void _toggle() => setState(() => _expanded = !_expanded);

  void _onVerticalDragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v > _flickVelocity && _expanded) {
      setState(() => _expanded = false);
    } else if (v < -_flickVelocity && !_expanded) {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                onVerticalDragEnd: _onVerticalDragEnd,
                child: SizedBox(
                  height: 28,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedCrossFade(
                duration: _animationDuration,
                sizeCurve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: SizedBox(
                  width: double.infinity,
                  child: widget.collapsedChild,
                ),
                secondChild: SizedBox(
                  width: double.infinity,
                  child: widget.expandedChild,
                ),
              ),
              SizedBox(height: bottomSafe + 12),
            ],
          ),
        ),
      ),
    );
  }
}
