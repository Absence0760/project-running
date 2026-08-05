import 'package:flutter/material.dart';

/// The five heart-rate zone band colours, per brightness — the one palette the
/// run-detail HR-zone band and the dashboard intensity card both read.
///
/// Those two surfaces used to carry different five-colour lists, and the
/// intensity card's comment claimed it matched "web's `--zone-*` CSS vars",
/// which did not exist. Both are now the same ramp as web's `--zone-1`..
/// `--zone-5`, by value.
///
/// The bands separate by LUMINANCE, not hue: a green-to-red ramp collapses
/// under red-green colour-vision deficiency, and the two old palettes proved
/// it — the intensity card's Z1 and Z5 were 1.03:1 apart (identical in
/// greyscale) and the run-detail band spanned only 2.11:1 end to end.
///
/// Five bands cannot be 3:1 apart pairwise: four steps of 3:1 need 81:1 and
/// sRGB offers at most 21:1. What each band DOES owe is 3:1 against the
/// surface behind the bar, which is what makes a surface-coloured separator
/// visible against every band — so each boundary is delineated even though
/// adjacent bands are ~1.42-1.49:1 apart. Draw the bar with
/// [kHrZoneSeparatorWidth] of the ambient background between segments.
///
/// Contrast, z1 -> z5:
///   light on parchment  15.18 / 10.17 / 6.98 / 4.74 / 3.25
///   dark  on duskDeep   13.78 /  9.70 / 6.90 / 4.90 / 3.46
/// The ramp direction inverts with the background (§489): the cool recovery
/// end always sits furthest from the page and the hot end nearest it, because
/// a saturated red cannot occupy the far end of either ramp without turning
/// brown-black on light or pink-white on dark.
const hrZoneColoursLight = <Color>[
  Color(0xFF0C1E34),
  Color(0xFF174326),
  Color(0xFF6B4E0D),
  Color(0xFFAF5111),
  Color(0xFFE9544F),
];

const hrZoneColoursDark = <Color>[
  Color(0xFFE4EEF9),
  Color(0xFF91D8A9),
  Color(0xFFD8A01B),
  Color(0xFFE56917),
  Color(0xFFE2231C),
];

/// Gap between bar segments, filled with the surface behind the bar.
const double kHrZoneSeparatorWidth = 2;

List<Color> hrZoneColours(ThemeData theme) =>
    theme.brightness == Brightness.dark ? hrZoneColoursDark : hrZoneColoursLight;
