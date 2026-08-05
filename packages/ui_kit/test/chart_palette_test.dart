import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Chart-palette guard (issue #666 S7). Every mark a chart paints is a
/// graphical object carrying meaning on its own, so it owes WCAG 2.2 SC
/// 1.4.11's 3:1 against the surface it is drawn on. What it does NOT owe is
/// pairwise 3:1 against its neighbours: four steps of 3:1 need 81:1 and sRGB
/// offers 21:1, so between marks the guard pins a monotone luminance ladder,
/// which is what survives greyscale and red-green colour-vision deficiency.
double _luminance(Color c) {
  double chan(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Ladder step between two marks, expressed the way a contrast ratio is so the
/// two floors in this file read on one scale.
double _step(Color a, Color b) {
  final la = _luminance(a) + 0.05;
  final lb = _luminance(b) + 0.05;
  return math.max(la, lb) / math.min(la, lb);
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    final palette = ChartPalette.ofTheme(theme);
    final card = theme.cardTheme.color!;
    final scaffold = theme.scaffoldBackgroundColor;

    group('$name chart palette', () {
      test('resolves per brightness', () {
        expect(
          palette,
          same(theme.brightness == Brightness.dark
              ? ChartPalette.dark
              : ChartPalette.light),
        );
      });

      test('every series entry clears 3:1 on the card', () {
        for (var i = 0; i < palette.series.length; i++) {
          expect(_contrast(palette.series[i], card), greaterThanOrEqualTo(3.0),
              reason: 'series[$i] is ${_contrast(palette.series[i], card)} '
                  'against the $name card');
        }
      });

      test('every series entry clears 3:1 on the scaffold', () {
        for (var i = 0; i < palette.series.length; i++) {
          expect(
            _contrast(palette.series[i], scaffold),
            greaterThanOrEqualTo(3.0),
            reason: 'series[$i] is '
                '${_contrast(palette.series[i], scaffold)} against the $name '
                'scaffold',
          );
        }
      });

      test('series entries are mutually distinct', () {
        expect(palette.series.toSet().length, palette.series.length);
      });

      test('series separates by a monotone luminance ladder', () {
        final ordered = palette.series.map(_luminance).toList()..sort();
        for (var i = 0; i + 1 < ordered.length; i++) {
          final step = (ordered[i + 1] + 0.05) / (ordered[i] + 0.05);
          expect(step, greaterThanOrEqualTo(1.7),
              reason: 'adjacent $name series separate by only $step');
        }
      });

      // Two five-colour zone lists used to ship — the run-detail band and the
      // dashboard intensity card. Measured before §495: the card's z2|z3 and
      // z3|z4 were 1.10:1 and its z1|z5 1.03:1 (identical in greyscale); the
      // band's z3|z4 was 1.32:1, its whole ramp spanned 2.11:1, and its z1 was
      // 1.75:1 against the light card. Both surfaces read this list now, and
      // the bands appear over the card AND the page, so both are checked — a
      // separator drawn in either surface colour has to stay visible.
      test('every zone band clears 3:1 on every surface it sits on', () {
        expect(palette.zones, hasLength(5));
        for (var i = 0; i < palette.zones.length; i++) {
          for (final (where, surface) in [
            ('card', card),
            ('scaffold', scaffold),
            // Web's --color-surface is plain white in light and midnight in
            // dark, and the twin band renders there too.
            (
              'plain surface',
              theme.brightness == Brightness.dark
                  ? AppTheme.midnight
                  : const Color(0xFFFFFFFF),
            ),
          ]) {
            final ratio = _contrast(palette.zones[i], surface);
            expect(ratio, greaterThanOrEqualTo(3.0),
                reason: 'z${i + 1} is $ratio against the $name $where — a '
                    'separator drawn in that colour would vanish');
          }
        }
      });

      test('zone bands step monotonically in luminance', () {
        final ls = palette.zones.map(_luminance).toList();
        final rising = ls[1] > ls[0];
        for (var i = 0; i + 1 < ls.length; i++) {
          expect(rising ? ls[i + 1] > ls[i] : ls[i + 1] < ls[i], isTrue,
              reason: 'the $name zone ramp folds at z${i + 1}->z${i + 2}');
          final step = _step(palette.zones[i], palette.zones[i + 1]);
          expect(step, greaterThanOrEqualTo(1.35),
              reason: 'z${i + 1}->z${i + 2} steps only $step in $name');
        }
      });

      test('every ramp step clears 3:1 on the card', () {
        for (var i = 0; i < palette.ramp.length; i++) {
          expect(_contrast(palette.ramp[i], card), greaterThanOrEqualTo(3.0),
              reason: 'ramp[$i] is ${_contrast(palette.ramp[i], card)} '
                  'against the $name card');
        }
      });

      test('the ramp rises monotonically in contrast against the card', () {
        final ratios = [
          for (final c in palette.ramp) _contrast(c, card),
        ];
        for (var i = 0; i + 1 < ratios.length; i++) {
          expect(ratios[i + 1], greaterThan(ratios[i]),
              reason: '$name ramp is not monotone: $ratios');
        }
      });

      test('adjacent ramp steps separate by at least 1.7', () {
        for (var i = 0; i + 1 < palette.ramp.length; i++) {
          final step = _step(palette.ramp[i], palette.ramp[i + 1]);
          expect(step, greaterThanOrEqualTo(1.7),
              reason: '$name ramp steps $i/${i + 1} separate by only $step');
        }
      });

      // The ramp is a tint ladder from the card toward the categorical scale's
      // most legible entry, so a single-series bar and the heatmap's busiest
      // day are one colour rather than two that drift apart.
      test('the ramp tops out at the first series entry', () {
        expect(palette.ramp.last, palette.series.first);
        expect(palette.bar, palette.ramp.last);
      });

      // A mark painted in the brand accent means "data" in one theme and
      // "interaction" in the other, because primary is dusk in light and coral
      // in dark. Nothing in the palette may alias it.
      test('no entry aliases the brand accent', () {
        for (final c in [...palette.series, ...palette.zones, ...palette.ramp]) {
          expect(c, isNot(theme.colorScheme.primary));
          expect(c, isNot(theme.colorScheme.secondary));
        }
      });
    });
  }

  // The two brightnesses are separate palettes precisely because one fixed
  // list cannot clear 3:1 on both cards; asserting they differ keeps a future
  // "simplification" from collapsing them.
  test('the two brightnesses carry different palettes', () {
    expect(ChartPalette.light.series, isNot(ChartPalette.dark.series));
    expect(ChartPalette.light.zones, isNot(ChartPalette.dark.zones));
    expect(ChartPalette.light.ramp, isNot(ChartPalette.dark.ramp));
  });

  // A 1 px gap disappears into the antialiasing of the two bands either side.
  test('the zone separator is wide enough to read at bar height', () {
    expect(ChartPalette.zoneSeparatorWidth, greaterThanOrEqualTo(2));
  });
}
