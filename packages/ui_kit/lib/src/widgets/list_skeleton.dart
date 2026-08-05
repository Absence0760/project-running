import 'package:flutter/material.dart';

/// Placeholder rows for a list surface that is still loading.
///
/// A centred spinner tells the user only that something is happening; it
/// occupies none of the space the list will, so arriving content lands as a
/// full-height jump. These blocks stand where the rows will stand, so the
/// swap is a fill rather than a re-layout.
///
/// [label] is the screen-reader announcement — ui_kit has no localisations of
/// its own, so the caller passes the translated string.
class ListSkeleton extends StatefulWidget {
  final int rows;
  final double rowHeight;
  final bool hasLeading;
  final EdgeInsetsGeometry padding;
  final String label;

  /// Lay the rows out at their intrinsic height rather than inside a
  /// viewport. See [ListSkeleton.section].
  final bool _intrinsic;

  const ListSkeleton({
    super.key,
    required this.label,
    this.rows = 5,
    this.rowHeight = 64,
    this.hasLeading = true,
    this.padding = const EdgeInsets.all(16),
  }) : _intrinsic = false;

  /// Placeholder rows for one *section* of an already-laid-out screen — a
  /// comment list inside a card, a picker inside a scrollable sheet.
  ///
  /// The default constructor's viewport requires a bounded height, so it
  /// cannot be used inside an outer scrollable; this variant occupies exactly
  /// the height its rows need and leaves scrolling to the host.
  const ListSkeleton.section({
    super.key,
    required this.label,
    this.rows = 3,
    this.rowHeight = 64,
    this.hasLeading = true,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  }) : _intrinsic = true;

  @override
  State<ListSkeleton> createState() => _ListSkeletonState();
}

class _ListSkeletonState extends State<ListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: widget.label,
      liveRegion: true,
      container: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final block = onSurface.withValues(
            alpha: 0.05 + 0.06 * _controller.value,
          );
          Widget row(int i) => _SkeletonRow(
                color: block,
                height: widget.rowHeight,
                hasLeading: widget.hasLeading,
                // Stagger the bar widths so the stack reads as content in
                // waiting rather than as a rendered table.
                titleFactor: 0.44 + (i % 3) * 0.12,
              );
          if (widget._intrinsic) {
            return Padding(
              padding: widget.padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.rows; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    row(i),
                  ],
                ],
              ),
            );
          }
          return ListView.separated(
            padding: widget.padding,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.rows,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => row(i),
          );
        },
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  final Color color;
  final double height;
  final bool hasLeading;
  final double titleFactor;

  const _SkeletonRow({
    required this.color,
    required this.height,
    required this.hasLeading,
    required this.titleFactor,
  });

  Widget _bar(double widthFactor, double barHeight) => FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: Container(
          height: barHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final leadingSide = (height * 0.55).clamp(24.0, 48.0);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          if (hasLeading) ...[
            Container(
              width: leadingSide,
              height: leadingSide,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(titleFactor, 12),
                const SizedBox(height: 8),
                _bar(0.82, 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
