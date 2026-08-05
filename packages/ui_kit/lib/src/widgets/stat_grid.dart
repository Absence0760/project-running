import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Narrowest a stat cell may be at 1.0x text scale before its value stops
/// being readable. The widest secondary value a run produces is a paced one —
/// "10:24 /km", "1234 kcal" — needing roughly 64 dp at the 14 sp body size a
/// [StatTile.small] draws its value in, so 72 leaves the value whole and lets
/// only the label truncate. Scaled by the OS text scale, it is what [StatGrid]
/// divides the available width by to decide a column count.
const double kStatCellMinWidth = 72;

/// Lays stat cells on a column grid whose column *count* is derived from the
/// width a cell needs at the current text scale, rather than from how many
/// cells there happen to be.
///
/// A `Row` of `Expanded` stat cells divides its width by the cell count, so a
/// run carrying eight secondary stats gave each 40.0 dp on a 360 dp phone —
/// under every value it draws — and because a stat label ellipsises rather
/// than overflows, nothing threw and no test could see it (§502). Here eight
/// cells become two rows of four at 1.0x and four rows of two at 2.0x.
///
/// With four or fewer cells that all fit, the layout is exactly what a `Row`
/// of `Expanded` produced, so adopting it on an existing row changes nothing
/// at 1.0x. What it adds beyond the reflow is that every cell is *bounded*,
/// which is what a `StatTile`'s `BoxFit.scaleDown` needs in order to shrink a
/// long value instead of bursting its row.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.cells});

  static const int _maxColumns = 4;

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();
    final minWidth = MediaQuery.textScalerOf(context).scale(kStatCellMinWidth);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final columns = (available / minWidth)
            .floor()
            .clamp(1, math.min(_maxColumns, cells.length));
        // Floored so `columns` cells can never total more than `available`
        // through floating-point drift and push the last one onto its own run.
        final width = (available / columns).floorToDouble();
        return Wrap(
          runSpacing: 12,
          children: [
            for (final cell in cells) SizedBox(width: width, child: cell),
          ],
        );
      },
    );
  }
}
