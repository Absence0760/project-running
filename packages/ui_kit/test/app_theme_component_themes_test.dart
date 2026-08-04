import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Guards for the issue #666 round-3 component themes (V5/V6/V16/V11): every
/// button family shares the radius-12 shape and 14px vertical padding so a
/// primary and its paired secondary match in shape and height; cards get a
/// real surface (fill + hairline outline, elevation 0); labelSmall pins the
/// 11px micro-label floor.

T? _resolve<T>(WidgetStateProperty<T?>? prop) => prop?.resolve(const {});

double _radius(OutlinedBorder? shape) =>
    (shape! as RoundedRectangleBorder).borderRadius
        .resolve(TextDirection.ltr)
        .topLeft
        .x;

void main() {
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    final theme = entry.value;

    group('button themes in ${entry.key}', () {
      final styles = <String, ButtonStyle?>{
        'FilledButton': theme.filledButtonTheme.style,
        'ElevatedButton': theme.elevatedButtonTheme.style,
        'OutlinedButton': theme.outlinedButtonTheme.style,
        'TextButton': theme.textButtonTheme.style,
      };

      test('every family overrides shape to radius 12', () {
        for (final e in styles.entries) {
          final shape = _resolve(e.value?.shape);
          expect(shape, isA<RoundedRectangleBorder>(),
              reason: '${e.key} in ${entry.key} keeps the stock M3 '
                  'StadiumBorder and reads as a pill beside a rounded-rect '
                  'primary');
          expect(_radius(shape), 12,
              reason: '${e.key} radius in ${entry.key}');
        }
      });

      test('every family shares the 14px vertical padding', () {
        for (final e in styles.entries) {
          final padding =
              _resolve(e.value?.padding)?.resolve(TextDirection.ltr);
          expect(padding, isNotNull, reason: '${e.key} in ${entry.key}');
          expect(padding!.top, 14, reason: '${e.key} in ${entry.key}');
          expect(padding.bottom, 14, reason: '${e.key} in ${entry.key}');
        }
      });

      test('filled, elevated, and outlined share horizontal padding too', () {
        for (final name in ['FilledButton', 'ElevatedButton', 'OutlinedButton']) {
          final padding =
              _resolve(styles[name]?.padding)?.resolve(TextDirection.ltr);
          expect(padding!.left, 20, reason: '$name in ${entry.key}');
          expect(padding.right, 20, reason: '$name in ${entry.key}');
        }
      });
    });

    group('cardTheme in ${entry.key}', () {
      final card = theme.cardTheme;

      test('separates by fill + hairline outline, not shadow', () {
        expect(card.elevation, 0);
        expect(card.color, theme.colorScheme.surface);
        final shape = card.shape! as RoundedRectangleBorder;
        expect(
            shape.borderRadius.resolve(TextDirection.ltr).topLeft.x, 12);
        expect(shape.side.color, theme.dividerColor,
            reason: 'the hairline must come from the brightness\'s divider '
                'token so cards and dividers stay one family');
        expect(shape.side.width, 1.0);
        expect(shape.side.style, BorderStyle.solid);
      });
    });

    group('textTheme in ${entry.key}', () {
      test('labelSmall pins the 11px micro-label floor', () {
        final label = theme.textTheme.labelSmall;
        expect(label, isNotNull);
        expect(label!.fontSize, 11);
        expect(label.fontWeight, FontWeight.w500);
        expect(label.letterSpacing, 0.5);
      });
    });
  }

  test('dark cardTheme fill is a real tonal step off the scaffold', () {
    final dark = AppTheme.dark;
    expect(dark.cardTheme.color, isNot(dark.scaffoldBackgroundColor));
  });
}
