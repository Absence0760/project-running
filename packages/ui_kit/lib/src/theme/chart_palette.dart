import 'package:flutter/material.dart';

/// The colours a chart draws its marks in — one per-brightness palette shared
/// by every data-visualisation surface, so a runner reading two charts on one
/// screen reads one colour system.
///
/// Four scales, because charts need four shapes of answer:
///
///  * [series] is CATEGORICAL — unordered things drawn together (fitness /
///    fatigue / form). Entries separate by LUMINANCE rather than hue, which is
///    what survives greyscale and red-green colour-vision deficiency. Pairwise
///    3:1 between three series is unreachable once each also owes 3:1 to the
///    card it is drawn on: it forces the extreme pair past 9:1, and light's
///    whole usable range is 5.98:1. So the floor between entries is the
///    achievable one and the ORDER is what holds — a monotone ladder.
///  * [zones] is ORDINAL — the five heart-rate bands, an ordered scale whose
///    steps are named. Same luminance-ladder reasoning as [series], and five
///    bands genuinely cannot be pairwise 3:1: four steps of 3:1 need 81:1 and
///    sRGB offers 21:1. What each band owes is 3:1 against the surface behind
///    the bar, which is what makes a separator drawn in that surface colour
///    visible against both its neighbours. Draw the bar with
///    [zoneSeparatorWidth] of the ambient background between segments. The ramp
///    direction inverts with the background (§489): the cool recovery end
///    always sits furthest from the page and the hot end nearest it, because a
///    saturated red cannot occupy the far end of either ramp without turning
///    brown-black on light or pink-white on dark.
///  * [ramp] is SEQUENTIAL — one quantity at increasing intensity (a heatmap
///    cell, a bar's fill). Single-hue, monotone, each step clearing WCAG
///    1.4.11's 3:1 non-text floor against its card, adjacent steps ~1.85:1
///    apart. Built as a tint ladder from the card toward [series]`.first`, so
///    the ramp's top step and the categorical scale's most legible entry are
///    the same colour and there is one intensity ladder in the app.
///  * [kinds] is CATEGORICAL too, and separate from [series] rather than an
///    extension of it: [series] means the three training-load curves and is
///    pinned at three entries by the web lockstep, while these are the six
///    planned-workout groups a plan calendar marks its days with. Six groups
///    cannot be pairwise 3:1 either — five steps of 3:1 need 243:1 — so the
///    same bargain holds: 3:1 against every surface the mark is drawn on, and
///    a monotone luminance ladder between the entries. Index order is the
///    ladder, coolest and furthest from the page first:
///    0 easy/recovery, 1 long/race, 2 tempo, 3 marathon pace,
///    4 interval/walk-run, 5 rest. That order is hue temperature, NOT session
///    prominence: §489's constraint fixes which hues can occupy which end (a
///    saturated red cannot be the far end without going brown-black on light),
///    and prominence is not what tells one kind from another — the localized
///    kind WORD beside the mark is, which is why these paint marks only.
///
/// `colorScheme.primary` is deliberately NOT a chart colour. It is a brand and
/// interaction token whose hue is not stable across brightnesses — dusk in
/// light, coral in dark — so a mark painted in it means "data" in one theme and
/// collides with an interaction affordance (or another chart's warm series) in
/// the other. Charts take their marks from here.
///
/// Web's `--chart-fitness` / `--chart-fatigue` / `--chart-form`,
/// `--zone-1`..`--zone-5` and `--kind-1`..`--kind-6` in `apps/web/src/app.css`
/// are [series], [zones] and [kinds] by value, per brightness; all three
/// locksteps are asserted from the web side, by scale name, in
/// `apps/web/src/lib/contrast_guard.test.ts` — renaming a scale here breaks a
/// guard in the other language's suite. [ramp] has no web twin and is not owed
/// one: web retired its only sequential surface, the dashboard calendar
/// heatmap, in favour of the Training intensity card (§ 515).
@immutable
class ChartPalette {
  const ChartPalette({
    required this.series,
    required this.zones,
    required this.ramp,
    required this.kinds,
  });

  final List<Color> series;
  final List<Color> zones;
  final List<Color> ramp;
  final List<Color> kinds;

  /// Gap between zone-bar segments, filled with the surface behind the bar.
  static const double zoneSeparatorWidth = 2;

  /// A single-series chart is a one-level ramp, so its bars draw the ramp's
  /// top step — the same colour the heatmap's busiest day gets.
  Color get bar => ramp.last;

  /// Contrast against the parchment card — series: 13.386 / 3.139 / 6.665;
  /// zones z1->z5: 15.178 / 10.168 / 6.978 / 4.737 / 3.248;
  /// ramp: 3.897 / 7.228 / 13.386;
  /// kinds 0->5: 15.282 / 11.377 / 8.621 / 6.550 / 4.929 / 3.737, and on the
  /// tightest surface a kind mark is drawn on — `tertiaryContainer`, the
  /// completed-day fill — 13.109 / 9.759 / 7.395 / 5.618 / 4.228 / 3.206.
  static const light = ChartPalette(
    series: [
      Color(0xFF1F1A6B),
      Color(0xFFB4801F),
      Color(0xFFA62020),
    ],
    zones: [
      Color(0xFF0C1E34),
      Color(0xFF174326),
      Color(0xFF6B4E0D),
      Color(0xFFAF5111),
      Color(0xFFE9544F),
    ],
    ramp: [
      Color(0xFF7975A1),
      Color(0xFF4E4987),
      Color(0xFF1F1A6B),
    ],
    kinds: [
      Color(0xFF082024),
      Color(0xFF0E3558),
      Color(0xFF6D2A6D),
      Color(0xFF72510E),
      Color(0xFFCC2429),
      Color(0xFF807A8C),
    ],
  );

  /// Contrast against the duskDeep card — series: 13.149 / 6.453 / 3.321;
  /// zones z1->z5: 13.775 / 9.698 / 6.900 / 4.899 / 3.457;
  /// ramp: 3.859 / 7.126 / 13.149;
  /// kinds 0->5: 14.483 / 11.996 / 9.808 / 8.035 / 6.637 / 5.459, and on the
  /// tightest surface a kind mark is drawn on — `tertiaryContainer`, the
  /// completed-day fill — 8.354 / 6.919 / 5.657 / 4.634 / 3.828 / 3.149. That
  /// midtone fill is what caps the dark ladder: white itself is only 9.324:1
  /// against it, so six rungs above 3:1 cannot step further apart than 1.255.
  static const dark = ChartPalette(
    series: [
      Color(0xFFE8E5FF),
      Color(0xFFE59105),
      Color(0xFFDE1F17),
    ],
    zones: [
      Color(0xFFE4EEF9),
      Color(0xFF91D8A9),
      Color(0xFFD8A01B),
      Color(0xFFE56917),
      Color(0xFFE2231C),
    ],
    ramp: [
      Color(0xFF7E7896),
      Color(0xFFADA9C5),
      Color(0xFFE8E5FF),
    ],
    kinds: [
      Color(0xFFE3F6F9),
      Color(0xFFC9E1F6),
      Color(0xFFE5BDE5),
      Color(0xFFE7AD3B),
      Color(0xFFEB8B8F),
      Color(0xFF9894A2),
    ],
  );

  static ChartPalette of(BuildContext context) => ofTheme(Theme.of(context));

  static ChartPalette ofTheme(ThemeData theme) =>
      theme.brightness == Brightness.dark ? dark : light;
}
