import 'package:flutter/material.dart';

/// The colours a chart draws its marks in — one per-brightness palette shared
/// by every data-visualisation surface, so a runner reading two charts on one
/// screen reads one colour system.
///
/// Two scales, because charts need two shapes of answer:
///
///  * [series] is CATEGORICAL — unordered things drawn together (fitness /
///    fatigue / form). Entries separate by LUMINANCE rather than hue, which is
///    what survives greyscale and red-green colour-vision deficiency. Pairwise
///    3:1 between three series is unreachable once each also owes 3:1 to the
///    card it is drawn on: it forces the extreme pair past 9:1, and light's
///    whole usable range is 5.98:1. So the floor between entries is the
///    achievable one and the ORDER is what holds — a monotone ladder.
///  * [ramp] is SEQUENTIAL — one quantity at increasing intensity (a heatmap
///    cell, a bar's fill). Single-hue, monotone, each step clearing WCAG
///    1.4.11's 3:1 non-text floor against its card, adjacent steps ~1.85:1
///    apart. Built as a tint ladder from the card toward [series]`.first`, so
///    the ramp's top step and the categorical scale's most legible entry are
///    the same colour and there is one intensity ladder in the app.
///
/// `colorScheme.primary` is deliberately NOT a chart colour. It is a brand and
/// interaction token whose hue is not stable across brightnesses — dusk in
/// light, coral in dark — so a mark painted in it means "data" in one theme and
/// collides with an interaction affordance (or another chart's warm series) in
/// the other. Charts take their marks from here.
///
/// Web's `--chart-fitness` / `--chart-fatigue` / `--chart-form` in
/// `apps/web/src/app.css` are [series] by value, per brightness. Web has no
/// sequential-ramp token yet.
@immutable
class ChartPalette {
  const ChartPalette({required this.series, required this.ramp});

  final List<Color> series;
  final List<Color> ramp;

  /// A single-series chart is a one-level ramp, so its bars draw the ramp's
  /// top step — the same colour the heatmap's busiest day gets.
  Color get bar => ramp.last;

  /// Contrast against the parchment card — series: 13.386 / 3.139 / 6.665;
  /// ramp: 3.897 / 7.228 / 13.386.
  static const light = ChartPalette(
    series: [
      Color(0xFF1F1A6B),
      Color(0xFFB4801F),
      Color(0xFFA62020),
    ],
    ramp: [
      Color(0xFF7975A1),
      Color(0xFF4E4987),
      Color(0xFF1F1A6B),
    ],
  );

  /// Contrast against the duskDeep card — series: 13.149 / 6.453 / 3.321;
  /// ramp: 3.859 / 7.126 / 13.149.
  static const dark = ChartPalette(
    series: [
      Color(0xFFE8E5FF),
      Color(0xFFE59105),
      Color(0xFFDE1F17),
    ],
    ramp: [
      Color(0xFF7E7896),
      Color(0xFFADA9C5),
      Color(0xFFE8E5FF),
    ],
  );

  static ChartPalette of(BuildContext context) => ofTheme(Theme.of(context));

  static ChartPalette ofTheme(ThemeData theme) =>
      theme.brightness == Brightness.dark ? dark : light;
}
