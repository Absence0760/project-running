import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors;

import '../l10n/gen/app_localizations.dart';

/// One toolbar action, renderable either as a visible [IconButton] or as a
/// row in the overflow menu — the same action, two presentations, so the
/// budget can move it without the caller restating it.
class AppBarAction {
  const AppBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor,
    this.destructive = false,
  });

  /// Drawn in both presentations. A [Widget] rather than an `IconData` so a
  /// busy action can swap in its spinner without a second code path.
  final Widget icon;

  /// Tooltip while visible, menu row title once it overflows. There is no
  /// separate short form: an action whose name only works as a tooltip has
  /// no name a user can act on.
  final String label;

  /// Null disables the action in both presentations.
  final VoidCallback? onPressed;

  final Color? iconColor;

  /// Destroys data or a relationship the user cannot restore (decisions
  /// § 498). Sits last, behind a divider, in the error colour — and is never
  /// promoted into a visible slot, where a mis-tap has no confirmation step
  /// before the dialog.
  final bool destructive;
}

/// An `AppBar.actions` list that keeps the title readable.
///
/// A Material toolbar spends 72dp before the title (a 56dp leading slot plus
/// the 16dp title gap), 48 on each action and 16 after the last, so the title
/// gets `width - 88 - 48n`. Six concurrent actions on a 360dp phone measure
/// **0dp of title** — not a crushed name, no name at all; three measure 128.
/// `run_detail_screen` had already worked this out by hand for its four
/// actions; this is that answer as one widget, so a screen does not have to
/// rediscover it.
///
/// [pinned] widgets always render (a share `PopupMenuButton` cannot fold into
/// another menu without nesting one) and count against [maxVisible]; the
/// first of [actions] fill whatever budget is left, in the order given, and
/// the rest go to a single overflow menu. Order [actions] by how often the
/// screen's user reaches for them — the head of the list is what earns a
/// toolbar slot.
class AppBarActions extends StatelessWidget {
  const AppBarActions({
    super.key,
    required this.actions,
    this.pinned = const [],
    this.maxVisible = 3,
  });

  final List<AppBarAction> actions;
  final List<Widget> pinned;

  /// Total toolbar slots, including [pinned] and the overflow button itself.
  /// Three is what fits beside a title on a 360dp phone.
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = AppSemanticColors.of(context);
    // The overflow button costs a slot of its own, unless every action fits
    // without one.
    final free = maxVisible - pinned.length;
    final slots = actions.length <= free ? actions.length : math.max(0, free - 1);
    final visible = <AppBarAction>[];
    final overflow = <AppBarAction>[];
    for (final action in actions) {
      if (!action.destructive && visible.length < slots) {
        visible.add(action);
      } else {
        overflow.add(action);
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...pinned,
        for (final action in visible)
          IconButton(
            icon: IconTheme.merge(
              data: IconThemeData(color: action.iconColor),
              child: action.icon,
            ),
            tooltip: action.label,
            onPressed: action.onPressed,
          ),
        if (overflow.isNotEmpty)
          PopupMenuButton<int>(
            tooltip: l10n.commonMore,
            onSelected: (i) => overflow[i].onPressed?.call(),
            itemBuilder: (_) => [
              for (var i = 0; i < overflow.length; i++) ...[
                if (overflow[i].destructive && i > 0) const PopupMenuDivider(),
                PopupMenuItem<int>(
                  value: i,
                  enabled: overflow[i].onPressed != null,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: IconTheme.merge(
                      data: IconThemeData(
                        color: overflow[i].destructive
                            ? semantic.danger
                            : overflow[i].iconColor,
                      ),
                      child: overflow[i].icon,
                    ),
                    title: Text(
                      overflow[i].label,
                      style: overflow[i].destructive
                          ? TextStyle(color: semantic.danger)
                          : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}
