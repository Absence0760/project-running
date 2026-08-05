import 'package:flutter/material.dart';

/// The eyebrow that names a group of rows in a list — a settings section, a
/// bucket of routes in a picker.
///
/// One typography for every such group: `labelSmall`, the §482 micro-label
/// floor, uppercased, weight 700, on `onSurfaceVariant` rather than
/// `colorScheme.outline` for the same reason [ChartCardHeader] gives — at
/// 11 sp, `outline`'s 4.058:1 on the light card is under WCAG 1.4.3's 4.5:1.
///
/// Distinct from [ChartCardHeader], which titles a data-visualisation card and
/// carries a right-aligned note slot, and from a *section title* — the
/// `titleMedium` heading of a block within a scrolling body — which is a
/// heading rather than an eyebrow and keeps its own type.
///
/// Padding is the caller's: a list group's inset belongs to the list, and the
/// two existing callers place it differently above the first row.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.trailing,
  });

  final String label;

  /// A leading glyph identifying the group. [iconColor] carries the group's
  /// own semantic colour when it has one.
  final IconData? icon;
  final Color? iconColor;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon,
              size: 16,
              color: iconColor ?? theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
