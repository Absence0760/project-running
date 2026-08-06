import 'package:flutter/material.dart';

/// The sub-surface tab strip every hosting screen wears, whose `isScrollable`
/// is *derived* from whether the labels fit rather than chosen per screen.
///
/// Two sibling hubs had opposite strips because each author picked by hand: the
/// fitness hub's four text tabs left `isScrollable` unset (Material 3 defaults
/// to `TabAlignment.fill`, flush at x=0, 46 dp tall), while the social hub's
/// five icon-and-text tabs set it true (defaulting to `TabAlignment.startOffset`
/// — a 52 dp left indent — and 72 dp tall). Switching destinations, the strip
/// jumped 26 dp taller and the first tab slid 52 dp right (issue #666 C6).
///
/// Deriving the flag removes the choice: labels that fit share the width, and
/// labels that don't scroll and start **flush**, never at `startOffset`. The
/// offset exists so a scrollable strip hints that content precedes the first
/// tab, but no strip in this app is ever scrolled to a middle tab on arrival,
/// so it only ever cost the leading tab its alignment with the fill case.
///
/// Icons are not a parameter. They are the only thing that makes a strip 72 dp
/// instead of 46, and the six-tab club-detail strip demonstrates that a longer
/// strip does not need them: tab count is not what earns the extra height.
class AppTabBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTabBar({super.key, required this.controller, required this.labels});

  final TabController controller;

  /// Resolved, already-localized labels — one per tab. This widget carries no
  /// copy of its own.
  final List<String> labels;

  /// Height of a text-only Material tab plus the indicator, which is what
  /// [TabBar] reports for the tabs this widget builds.
  static const double height = 46 + 2;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.tabBarTheme.labelStyle ?? theme.textTheme.titleSmall;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // What the strip needs to lay every label out whole, at the size the OS is
    // currently rendering type: the text plus Material's own per-tab padding.
    var needed = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      needed += painter.width + kTabLabelPadding.horizontal;
      painter.dispose();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scrollable = needed > constraints.maxWidth;
        return TabBar(
          controller: controller,
          isScrollable: scrollable,
          tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
          tabs: [for (final label in labels) Tab(text: label)],
        );
      },
    );
  }
}
