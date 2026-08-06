import 'package:flutter/material.dart';

/// The per-modality IDENTITY hues, split the way §529 split web's: a **fill**
/// that tints a disc, chip or rail, and an **ink** beside it that every glyph,
/// border or label on that fill takes.
///
/// One frozen hue cannot be both, in two themes. `#4E7C5E` is a legible green
/// glyph on white and **2.875:1** on its own 16 % disc over the dark card;
/// `#9A6B2F` is **2.962:1** on the same ground. Both shipped as
/// theme-independent `const Color`s doing both jobs, which is the tightest
/// version of the ground there is — a mark measured against a tint of itself.
/// Split, they read 5.297 / 5.183 light and 5.712 / 6.633 dark.
///
/// Identity survives the split because it moves LIGHTNESS only — each ink is
/// the same hue as its fill — so the colour a runner learns for "gym" is the
/// colour that stays. In dark the ink IS the fill: a pastel on near-black
/// already clears, and re-spelling it would be two values for one rung.
///
/// Values are web's `--section-gym` / `--section-gym-ink` /
/// `--section-nutrition` / `--section-nutrition-ink` in
/// `apps/web/src/app.css`, taken rather than re-derived so the two platforms
/// carry one measured pair. Only the two modalities mobile actually paints are
/// here; web's other five sections belong to its sidebar, which mobile has no
/// twin of.
@immutable
class SectionAccents {
  const SectionAccents({
    required this.gym,
    required this.gymInk,
    required this.nutrition,
    required this.nutritionInk,
  });

  final Color gym;
  final Color gymInk;
  final Color nutrition;
  final Color nutritionInk;

  static const light = SectionAccents(
    gym: Color(0xFF8FBF9F),
    gymInk: Color(0xFF3B684A),
    nutrition: Color(0xFFE8C07D),
    nutritionInk: Color(0xFF825A17),
  );

  static const dark = SectionAccents(
    gym: Color(0xFF8FBF9F),
    gymInk: Color(0xFF8FBF9F),
    nutrition: Color(0xFFE8C07D),
    nutritionInk: Color(0xFFE8C07D),
  );

  static SectionAccents of(BuildContext context) => ofTheme(Theme.of(context));

  static SectionAccents ofTheme(ThemeData theme) =>
      theme.brightness == Brightness.dark ? dark : light;
}
