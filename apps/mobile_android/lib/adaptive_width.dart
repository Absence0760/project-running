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
