import 'package:flutter/material.dart';

enum _StatEmphasis { small, medium, large }

/// One metric read as a pair: the value over the name of the thing it
/// measures. Every stat row in the app is built from these at one of three
/// emphases, so a runner scanning a screen reads one type ramp rather than a
/// different one per card.
///
/// The three tiers are the ones the app already used, not a scale invented
/// here. [StatTile.large] is a hero row (run detail, a public share page, a
/// period summary); [StatTile.medium] a live-updating column, which is why it
/// alone takes tabular figures — a proportional digit changes the value's
/// width every second and the column jitters; [StatTile.small] a dense
/// secondary grid cell, where an icon carries the identification and the
/// label only confirms it.
///
/// **A value must never be the thing that truncates.** `large` and `medium`
/// scale the value+unit pair with `BoxFit.scaleDown`, which needs a *bounded*
/// parent to scale against: an intrinsically-sized cell in a
/// `Row(mainAxisAlignment: spaceAround)` has no bound, so the row overflows
/// instead of the number shrinking. Lay these out with `StatGrid`, which
/// bounds every cell by construction, or with `Expanded`. The label may
/// ellipsise — a stat whose name is clipped is still identifiable beside its
/// neighbours and its icon, a clipped number is not.
///
/// Muted text is `onSurfaceVariant`, not `colorScheme.outline`: `outline` is
/// a 3:1 boundary token and reads 4.058:1 on the light card, under WCAG
/// 1.4.3's 4.5:1 for the 11–12 sp type these labels carry (§505).
class StatTile extends StatelessWidget {
  /// A dense cell in a secondary grid: an icon, a compact value, a label.
  const StatTile.small({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  })  : unit = null,
        labelTrailing = null,
        _emphasis = _StatEmphasis.small;

  /// A live-updating column — the recording overlay, the finished-run summary.
  const StatTile.medium({
    super.key,
    required this.label,
    required this.value,
    this.unit,
  })  : icon = null,
        labelTrailing = null,
        _emphasis = _StatEmphasis.medium;

  /// A hero stat: the headline row of a detail or summary surface.
  const StatTile.large({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.labelTrailing,
  })  : icon = null,
        _emphasis = _StatEmphasis.large;

  final IconData? icon;
  final String label;
  final String value;

  /// A short qualifier drawn on the value's baseline — "km", "/mi", "bpm".
  final String? unit;

  /// A glyph beside the label: an info affordance, a trend arrow. The gesture
  /// belongs to the caller; this slot only reserves the space beside the name.
  final Widget? labelTrailing;

  final _StatEmphasis _emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final large = _emphasis == _StatEmphasis.large;

    final labelText = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (large ? theme.textTheme.bodySmall : theme.textTheme.labelSmall)
          ?.copyWith(color: muted),
    );

    return Column(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: muted),
          const SizedBox(height: 2),
        ],
        _value(theme, muted),
        SizedBox(
            height: switch (_emphasis) {
          _StatEmphasis.small => 0,
          _StatEmphasis.medium => 2,
          _StatEmphasis.large => 4,
        }),
        if (labelTrailing == null)
          labelText
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: labelText),
              const SizedBox(width: 3),
              labelTrailing!,
            ],
          ),
      ],
    );
  }

  Widget _value(ThemeData theme, Color muted) {
    if (_emphasis == _StatEmphasis.small) {
      return Text(
        value,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      );
    }
    final large = _emphasis == _StatEmphasis.large;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: large
                ? theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700)
                : theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
          ),
          if (unit != null) ...[
            SizedBox(width: large ? 4 : 2),
            Text(
              unit!,
              style: (large
                      ? theme.textTheme.bodySmall
                      : theme.textTheme.labelSmall)
                  ?.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
