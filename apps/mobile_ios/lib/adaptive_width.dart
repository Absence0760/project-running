import 'package:flutter/widgets.dart';

/// Material adaptive width classes. Wide-layout re-compositions key off
/// [WidthClass.expanded] (>= 840dp — a 10" tablet or landscape foldable):
/// the flutter_test default surface is 800dp logical, so gating on
/// `expanded` keeps every phone-sized widget test on the compact paths.
enum WidthClass { compact, medium, expanded }

const double kMediumWidthBreakpoint = 600;
const double kExpandedWidthBreakpoint = 840;

/// Max width for single-column reading surfaces (feed, plan detail) on
/// expanded layouts — mirrors the web app's centered content column.
const double kContentMaxWidth = 720;

WidthClass widthClassOf(BuildContext context) =>
    widthClassOfWidth(MediaQuery.sizeOf(context).width);

WidthClass widthClassOfWidth(double width) {
  if (width >= kExpandedWidthBreakpoint) return WidthClass.expanded;
  if (width >= kMediumWidthBreakpoint) return WidthClass.medium;
  return WidthClass.compact;
}

/// Centres [child] behind a [maxWidth] cap on expanded layouts, and returns it
/// untouched on anything narrower.
///
/// A single-column reading surface stretched across a 1280 dp tablet puts a
/// row's label and its value a screen apart. Every clamp in the app was the
/// same four lines written out by hand, which is why so few screens had one
/// (issue #666 C15) — one call is cheap enough to be the default for a list or
/// a prose column. Do NOT wrap a surface whose point is to be full-bleed: a
/// map, a heatmap, a chart that should use the room.
Widget contentColumn(
  BuildContext context,
  Widget child, {
  double maxWidth = kContentMaxWidth,
}) {
  if (widthClassOf(context) != WidthClass.expanded) return child;
  return Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
