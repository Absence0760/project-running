import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Line-token guard (issue #666 S5). A hairline is only a boundary if it can
/// be seen: WCAG 2.2 SC 1.4.11 puts the floor for non-text visual boundaries
/// at 3:1. Material 3 also routes `Divider` through
/// `colorScheme.outlineVariant` rather than `ThemeData.dividerColor`, so the
/// three names have to resolve to one value or a drawn border and a Divider
/// beside it read as different weights.
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

Color _cardSide(ThemeData theme) =>
    (theme.cardTheme.shape! as RoundedRectangleBorder).side.color;

void main() {
  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
    group('$name line token', () {
      test('dividerColor, dividerTheme and outlineVariant are one value', () {
        expect(theme.dividerTheme.color, theme.dividerColor);
        expect(theme.colorScheme.outlineVariant, theme.dividerColor);
      });

      test('the card hairline is the same token', () {
        expect(_cardSide(theme), theme.dividerColor);
      });

      test('clears 3:1 over the scaffold background', () {
        expect(
          _contrast(theme.dividerColor, theme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(3.0),
        );
      });

      test('clears 3:1 over the card fill', () {
        expect(
          _contrast(theme.dividerColor, theme.cardTheme.color!),
          greaterThanOrEqualTo(3.0),
        );
      });
    });
  }
}
