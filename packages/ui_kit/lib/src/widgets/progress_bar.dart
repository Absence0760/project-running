import 'package:flutter/material.dart';

/// The one linear progress bar in the app: a hairline-outlined stadium track
/// with a coloured fill.
///
/// Two different things have to be visible here and they cannot both be
/// carried by the track's colour. **That the bar exists** is a component
/// boundary and owes WCAG 1.4.11's 3:1 against the page; **how far the fill
/// reaches** is the state and owes 3:1 against the track. Chaining those two
/// steps needs 9:1 of range between the page and the weakest fill, and there
/// is not that much room: `AppSemanticColors.warning` is 5.499:1 from
/// parchment, so a numeric search over every possible track luminance tops out
/// at min(track-vs-page, worst-fill-vs-track) = **2.345:1 in light and 2.563:1
/// in dark**. No colour choice clears both.
///
/// So the track is chosen purely for the state axis — `surfaceContainerHighest`
/// gives the best worst-case fill separation of any token in the scheme,
/// 4.724:1 light (warning) and 4.997:1 dark (danger) — and the component
/// boundary is a drawn hairline in the [ColorScheme.outlineVariant] line token
/// §487 already holds at 3:1 (3.531:1 light card, 3.330:1 dark card, 3.911:1
/// dark scaffold). Nothing has to be both.
///
/// The geometry is derived, not picked: the fill lane is Material's own
/// default linear-indicator height (4), the hairline costs 1 above and 1 below,
/// so the bar is 6 tall; the radius is a full stadium, which a
/// `BorderRadius.circular(999)` clamps to half the height.
///
/// [fill] must clear 3:1 against the track. `colorScheme.error` does **not**
/// (2.991:1 light) — pass `AppSemanticColors.danger` instead, which is what
/// that token exists for.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.fill,
    this.semanticsLabel,
  });

  /// 0..1, or null for an indeterminate "work in progress" animation.
  final double? value;

  /// Defaults to `colorScheme.primary`.
  final Color? fill;

  final String? semanticsLabel;

  /// Height of the fill lane, before the hairline is added around it. This is
  /// `_LinearProgressIndicatorDefaultsM3.linearMinHeight`.
  static const double fillHeight = 4;

  /// Outside height of the whole bar: [fillHeight] plus one hairline above and
  /// one below.
  static const double height = fillHeight + 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(999);
    // A Container, not a DecoratedBox: only Container insets its child by the
    // decoration's border dimensions, which is what makes the bar exactly
    // [height] tall with a [fillHeight] lane inside it.
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: LinearProgressIndicator(
          value: value,
          minHeight: fillHeight,
          backgroundColor: Colors.transparent,
          color: fill ?? scheme.primary,
          semanticsLabel: semanticsLabel,
        ),
      ),
    );
  }
}
