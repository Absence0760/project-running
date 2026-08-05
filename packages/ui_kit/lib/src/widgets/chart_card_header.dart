import 'package:flutter/material.dart';

/// The header every data-visualisation card wears — one typography and one
/// colour for the lot, so a runner scanning a dashboard of charts reads one
/// hierarchy instead of a different one per card.
///
/// A `Wrap`, not a `Row`: a single run lays out exactly as a `Row` with
/// `spaceBetween` did, so nothing moves at 1.0x, but the trailing note or
/// action drops to its own line once the title no longer fits beside it rather
/// than truncating either (§500). The title itself sets no `maxLines` — a card
/// title that ellipsises stops naming the card, and a localized title is the
/// common case that needs the second line.
///
/// [title] and [note] are resolved strings; this widget carries no copy of its
/// own. The eyebrow is `labelMedium` on `onSurfaceVariant`, not
/// `colorScheme.outline`: `outline` is a 3:1 boundary token and reads 4.058:1
/// on the light card, which is below WCAG 1.4.3's 4.5:1 for 12 sp text.
class ChartCardHeader extends StatelessWidget {
  const ChartCardHeader({
    super.key,
    required this.title,
    this.note,
    this.action,
  });

  final String title;

  /// A short right-aligned qualifier — a window length, a running total.
  final String? note;

  /// A control belonging to the chart, such as a period toggle.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.06,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
