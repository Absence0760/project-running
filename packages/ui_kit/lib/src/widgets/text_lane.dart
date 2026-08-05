import 'package:flutter/material.dart';

/// An aligned column of text inside a row — a set number, a date, a rank, a
/// weekday — whose width is a *text* dimension rather than a graphic one.
///
/// A literal `SizedBox(width:)` around such a lane fails on two axes the
/// author never sees: the OS text scale (up to 2x on both platforms) and the
/// active locale. Neither raises an exception. A multi-word label reflows
/// inside the box and makes the row taller than its neighbours; a single
/// unbreakable token ("Desaquecimento", "120:00", "#999") paints straight over
/// the lane beside it.
///
/// [width] is therefore a floor, scaled by the OS text scale: 1.0x geometry is
/// preserved exactly, the lane grows in step with the glyphs, and a label that
/// still outruns it widens the lane rather than losing characters. Use it for
/// text; a graphic whose size is load-bearing keeps its fixed box and fits the
/// text inside with `BoxFit.scaleDown` instead.
class TextLane extends StatelessWidget {
  const TextLane({super.key, required this.width, required this.child});

  /// Lane width at 1.0x text scale, before the content has its say.
  final double width;

  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.textScalerOf(context).scale(width),
        ),
        child: child,
      );
}
