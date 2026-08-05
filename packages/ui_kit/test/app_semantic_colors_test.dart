import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Guard for the AppSemanticColors theme extension (issue #666 V3): every
/// on*/base pair must compute to >= 4.5:1 WCAG AA contrast in its brightness,
/// and every base must clear 3:1 against that brightness's scaffold
/// background so a status banner reads as a banner. Ratios are computed from
/// relative luminance here, never hardcoded, so retuning a token re-derives
/// the check.

double _luminance(Color c) {
  double chan(double v) {
    v /= 255.0;
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
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
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

Map<String, ({Color base, Color on})> _pairs(AppSemanticColors s) => {
      'success': (base: s.success, on: s.onSuccess),
      'warning': (base: s.warning, on: s.onWarning),
      'danger': (base: s.danger, on: s.onDanger),
      'crown': (base: s.crown, on: s.onCrown),
    };

void main() {
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    group('AppSemanticColors in ${entry.key}', () {
      final theme = entry.value;
      final semantic = theme.extension<AppSemanticColors>();

      test('is registered on the theme', () {
        expect(semantic, isNotNull,
            reason: 'AppTheme.${entry.key} must carry AppSemanticColors '
                'in ThemeData.extensions');
      });

      test('every on*/base pair meets WCAG AA (>= 4.5:1)', () {
        for (final p in _pairs(semantic!).entries) {
          final ratio = _contrast(p.value.on, p.value.base);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: 'on${p.key} on ${p.key} contrast '
                  '${ratio.toStringAsFixed(2)} in ${entry.key} fails AA');
        }
      });

      test('every base clears 3:1 against the scaffold background', () {
        for (final p in _pairs(semantic!).entries) {
          final ratio =
              _contrast(p.value.base, theme.scaffoldBackgroundColor);
          expect(ratio, greaterThanOrEqualTo(3.0),
              reason: '${p.key} contrast ${ratio.toStringAsFixed(2)} '
                  'against the ${entry.key} scaffold is too low to read '
                  'as a banner');
        }
      });

      // A base is also used as a bare foreground — the signed readiness
      // delta, status icons — so 3:1 is not enough on its own. The raw
      // literals that use replaced were 3.15:1 and 3.25:1 as text on the
      // dark card (issue #666 round 8).
      test('every base clears 4.5:1 as text on card and scaffold', () {
        for (final p in _pairs(semantic!).entries) {
          for (final bg in {
            theme.colorScheme.surface,
            theme.scaffoldBackgroundColor,
          }) {
            final ratio = _contrast(p.value.base, bg);
            expect(ratio, greaterThanOrEqualTo(4.5),
                reason: '${p.key} as text on $bg is '
                    '${ratio.toStringAsFixed(2)} in ${entry.key}');
          }
        }
      });
    });
  }

  group('ThemeExtension contract', () {
    test('lerp endpoints and midpoint', () {
      const l = AppSemanticColors.light;
      const d = AppSemanticColors.dark;
      expect(l.lerp(d, 0).danger, l.danger);
      expect(l.lerp(d, 1).danger, d.danger);
      final mid = l.lerp(d, 0.5);
      expect(mid.warning, Color.lerp(l.warning, d.warning, 0.5));
      expect(mid.onCrown, Color.lerp(l.onCrown, d.onCrown, 0.5));
      expect(l.lerp(null, 0.5), same(l));
    });

    test('copyWith overrides only the given fields', () {
      const override = Color(0xFF123456);
      final copied = AppSemanticColors.light.copyWith(success: override);
      expect(copied.success, override);
      expect(copied.onSuccess, AppSemanticColors.light.onSuccess);
      expect(copied.danger, AppSemanticColors.light.danger);
      expect(copied.crown, AppSemanticColors.light.crown);
    });

    test('ofTheme reads the registered extension', () {
      expect(AppSemanticColors.ofTheme(AppTheme.light),
          same(AppTheme.light.extension<AppSemanticColors>()));
      expect(AppSemanticColors.ofTheme(AppTheme.dark),
          same(AppTheme.dark.extension<AppSemanticColors>()));
    });

    test('ofTheme falls back by brightness when the extension is absent', () {
      expect(AppSemanticColors.ofTheme(ThemeData(brightness: Brightness.light)),
          same(AppSemanticColors.light));
      expect(AppSemanticColors.ofTheme(ThemeData(brightness: Brightness.dark)),
          same(AppSemanticColors.dark));
    });
  });
}
