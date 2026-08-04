import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Chip label legibility guard. RawChip consults only
/// `ChipThemeData.labelStyle`, resolving just its `color` through
/// `WidgetStateProperty.resolveAs` — `secondaryLabelStyle` is never read on
/// the FilterChip path. This pins that the theme's labelStyle color resolves
/// per-state and that both states meet WCAG 2.2 AA (>= 4.5:1) over what the
/// chip actually sits on: `selectedColor` when selected, the scaffold
/// background when not (the chip background is transparent).
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

Color _resolveLabelColor(ThemeData theme, Set<WidgetState> states) {
  final style = theme.chipTheme.labelStyle;
  expect(style, isNotNull, reason: 'chip theme must set labelStyle');
  final color = WidgetStateProperty.resolveAs<Color?>(style!.color, states);
  expect(color, isNotNull, reason: 'chip labelStyle must carry a color');
  return color!;
}

void main() {
  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
    group('$name chip theme', () {
      test('selected label is legible over selectedColor', () {
        final selectedBg = theme.chipTheme.selectedColor;
        expect(selectedBg, isNotNull);
        final label = _resolveLabelColor(theme, {WidgetState.selected});
        expect(
          _contrast(label, selectedBg!),
          greaterThanOrEqualTo(4.5),
          reason: 'selected chip label must meet WCAG AA over selectedColor',
        );
      });

      test('unselected label is legible over the scaffold background', () {
        final label = _resolveLabelColor(theme, const {});
        expect(
          _contrast(label, theme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(4.5),
          reason: 'unselected chip label must meet WCAG AA over the scaffold',
        );
      });

      test('checkmark is legible over selectedColor', () {
        final checkmark = theme.chipTheme.checkmarkColor;
        expect(checkmark, isNotNull);
        expect(
          _contrast(checkmark!, theme.chipTheme.selectedColor!),
          greaterThanOrEqualTo(4.5),
        );
      });
    });
  }
}
