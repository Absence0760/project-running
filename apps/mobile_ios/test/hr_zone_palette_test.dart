import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/hr_zone_palette.dart';

/// Issue #666 round 8. Two different five-colour zone lists shipped — the
/// run-detail band and the dashboard intensity card — and neither separated
/// its bands. Measured before the fix: the intensity card's z2|z3 and z3|z4
/// were 1.10:1 and its z1|z5 was 1.03:1 (identical in greyscale); the
/// run-detail band's z3|z4 was 1.32:1, its whole ramp spanned 2.11:1, and its
/// z1 was 1.75:1 against the light card.
///
/// Five bands cannot be pairwise 3:1 — four steps of 3:1 need 81:1 and sRGB
/// offers 21:1 — so what each band owes is 3:1 against the surface behind the
/// bar. That is what makes the surface-coloured separator visible against
/// every band, which is how each boundary is delineated.

double _luminance(Color c) {
  double chan(double v) {
    v /= 255.0;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  // ignore: deprecated_member_use
  return 0.2126 * chan(c.red.toDouble()) +
      // ignore: deprecated_member_use
      0.7152 * chan(c.green.toDouble()) +
      // ignore: deprecated_member_use
      0.0722 * chan(c.blue.toDouble());
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final cases = <String, (List<Color>, ThemeData, List<Color>)>{
    'light': (
      hrZoneColoursLight,
      AppTheme.light,
      const [AppTheme.parchment, Color(0xFFFFFFFF)],
    ),
    'dark': (
      hrZoneColoursDark,
      AppTheme.dark,
      const [AppTheme.duskDeep, AppTheme.midnight],
    ),
  };

  for (final entry in cases.entries) {
    final (colours, theme, surfaces) = entry.value;

    test('${entry.key} bands clear 3:1 against every surface they sit on', () {
      expect(colours, hasLength(5));
      for (var i = 0; i < colours.length; i++) {
        for (final surface in surfaces) {
          final ratio = _contrast(colours[i], surface);
          expect(ratio, greaterThanOrEqualTo(3.0),
              reason: 'z${i + 1} is $ratio against $surface in ${entry.key} — '
                  'the separator drawn in that colour would vanish');
        }
      }
    });

    test('${entry.key} bands step monotonically in luminance', () {
      final ls = colours.map(_luminance).toList();
      final rising = ls[1] > ls[0];
      for (var i = 0; i + 1 < ls.length; i++) {
        expect(rising ? ls[i + 1] > ls[i] : ls[i + 1] < ls[i], isTrue,
            reason: 'the ${entry.key} ramp folds at z${i + 1}->z${i + 2}');
        final step = rising
            ? (ls[i + 1] + 0.05) / (ls[i] + 0.05)
            : (ls[i] + 0.05) / (ls[i + 1] + 0.05);
        expect(step, greaterThanOrEqualTo(1.35),
            reason: 'z${i + 1}->z${i + 2} steps only $step in ${entry.key}');
      }
    });

    test('${entry.key} resolves from the matching brightness', () {
      expect(hrZoneColours(theme), colours);
    });
  }

  test('the separator is wide enough to read at bar height', () {
    expect(kHrZoneSeparatorWidth, greaterThanOrEqualTo(2));
  });
}
