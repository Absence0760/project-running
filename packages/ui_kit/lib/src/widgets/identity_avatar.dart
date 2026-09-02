import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const double _saturation = 0.5;
const double _baseLightness = 0.55;
const double _minContrast = 4.5;

/// Hash a stable id to a hue 0-360 so avatars colour-diff consistently.
/// Must stay byte-for-byte compatible with the historical per-screen hash:
/// changing it would recolour every existing user's avatar.
int identityHue(String seed) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h % 360;
}

/// Initial letter for an avatar bubble.
///
/// Taken as a GRAPHEME CLUSTER, not as a UTF-16 code unit. `substring(0, 1)`
/// cuts a display name starting with an emoji — or any astral character — in
/// half at the surrogate pair, and the avatar every social surface draws then
/// renders a lone unpaired surrogate as the replacement glyph.
String identityInitial(String? name) {
  final c = (name ?? '?').trim();
  return c.isEmpty ? '?' : c.characters.first.toUpperCase();
}

double _relativeLuminance(Color c) {
  double chan(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
}

double _contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Background for [hue] at the house saturation/lightness, with lightness
/// nudged away from the mid-luminance band where neither white nor ink
/// reaches 4.5:1 (yellow/lime hues sit near 2:1 against white unclamped).
/// Hues already legible keep the historical colour exactly.
Color identityBackground(int hue) {
  var lightness = _baseLightness;
  var color =
      HSLColor.fromAHSL(1, hue.toDouble(), _saturation, lightness).toColor();
  var white = _contrast(Colors.white, color);
  var ink = _contrast(AppTheme.ink, color);
  final darken = white >= ink;
  while (white < _minContrast && ink < _minContrast) {
    lightness = (lightness + (darken ? -0.01 : 0.01)).clamp(0.0, 1.0);
    color =
        HSLColor.fromAHSL(1, hue.toDouble(), _saturation, lightness).toColor();
    white = _contrast(Colors.white, color);
    ink = _contrast(AppTheme.ink, color);
  }
  return color;
}

/// Foreground over [background], picked by computed contrast.
Color identityForeground(Color background) =>
    _contrast(Colors.white, background) >= _contrast(AppTheme.ink, background)
        ? Colors.white
        : AppTheme.ink;

/// Deterministic initial-letter avatar for users, clubs, and events. Hashes
/// [seed] to a hue and guarantees the initial meets WCAG AA (4.5:1) over the
/// resolved background in both themes.
///
/// When [imageUrl] is set the uploaded picture is layered over that circle
/// rather than replacing it, so the initial is what shows while the bytes
/// are in flight and what remains if they never arrive. `DecorationImage`
/// carries no error hook at all, which is why every hand-rolled avatar that
/// used one rendered a failed load as an empty coloured disc.
class IdentityAvatar extends StatelessWidget {
  final String seed;
  final String? name;
  final double size;
  final double? fontSize;
  final String? imageUrl;

  const IdentityAvatar({
    super.key,
    required this.seed,
    this.name,
    this.size = 36,
    this.fontSize,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final background = identityBackground(identityHue(seed));
    final url = imageUrl;
    // The circle's diameter is chosen by the caller for layout, so the
    // initial is bounded by the graphic rather than the other way round: at
    // 2x OS text scale an 18 px avatar's 10 px initial needs 29 px and spilled
    // outside the circle. Scaling down keeps it centred and whole.
    final letter = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        identityInitial(name),
        style: TextStyle(
          color: identityForeground(background),
          fontWeight: FontWeight.w700,
          fontSize: fontSize ?? size * 0.42,
        ),
      ),
    );
    // Decode at ~3x the rendered circle instead of full source resolution —
    // a feed or leaderboard holds dozens of these at once.
    final decodeSide = (size * 3).round();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
      ),
      child: url == null || url.isEmpty
          ? letter
          : Stack(
              alignment: Alignment.center,
              children: [
                letter,
                ClipOval(
                  child: Image(
                    image: ResizeImage(
                      NetworkImage(url),
                      width: decodeSide,
                      height: decodeSide,
                    ),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
                        wasSynchronouslyLoaded || frame != null
                            ? child
                            : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
    );
  }
}
