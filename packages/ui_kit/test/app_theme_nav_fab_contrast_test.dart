import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// `AppTheme`'s own component themes, measured where they paint (issue #666,
/// the round-12 open item).
///
/// The navigation bar's selected icon is drawn INSIDE the indicator pill, so
/// the pill is the background it owes WCAG 1.4.11's 3:1 against — not the bar.
/// Measuring on the bar is §503's recorded trap and it flatters the light
/// theme: `coralDeep` reads 2.767:1 on parchment and 2.337:1 on the pill it
/// actually lands on. The FAB is the other half of the same token problem, and
/// there the answer is the opposite way round — the glyph moved, not the fill,
/// because a FAB carries its own elevation and shadow, so under §503's
/// foreground-XOR-fill rule the boundary is not the fill's to earn.
///
/// Every figure is computed from the real tokens. Each repair is pinned in both
/// directions, so reverting one fails here rather than passing quietly.
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

Color _over(Color c, Color bg) => Color.alphaBlend(c, bg);

const _aaText = 4.5;
const _aaMark = 3.0;

T _resolve<T>(WidgetStateProperty<T?>? prop, Set<WidgetState> states) {
  expect(prop, isNotNull);
  final value = prop!.resolve(states);
  expect(value, isNotNull);
  return value!;
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    final s = theme.colorScheme;
    final bar = theme.navigationBarTheme;
    final barBg = bar.backgroundColor!;
    final pill = _over(bar.indicatorColor!, barBg);

    group('$name navigation bar', () {
      test('the selected icon clears 3:1 on the indicator it sits inside', () {
        final icon =
            _resolve(bar.iconTheme, const {WidgetState.selected}).color!;
        expect(_contrast(icon, pill), greaterThanOrEqualTo(_aaMark),
            reason: 'the selected icon is drawn on the indicator, not the bar');
        expect(_contrast(icon, barBg), greaterThanOrEqualTo(_aaMark),
            reason: 'and on the bar, for the frame in which the indicator is '
                'still growing into place');
      });

      test('the unselected icon clears 3:1 on the bar', () {
        final icon = _resolve(bar.iconTheme, const <WidgetState>{}).color!;
        expect(_contrast(_over(icon, barBg), barBg),
            greaterThanOrEqualTo(_aaMark));
      });

      test('both labels clear AA on the bar', () {
        for (final states in [
          const {WidgetState.selected},
          const <WidgetState>{},
        ]) {
          final label = _resolve(bar.labelTextStyle, states).color!;
          expect(_contrast(_over(label, barBg), barBg),
              greaterThanOrEqualTo(_aaText),
              reason: 'the label sits below the indicator, on the bar itself');
        }
      });
    });

    group('$name floating action button', () {
      test('the glyph clears 3:1 on the fill', () {
        final fab = theme.floatingActionButtonTheme;
        expect(_contrast(fab.foregroundColor!, fab.backgroundColor!),
            greaterThanOrEqualTo(_aaMark));
      });
    });

    group('$name secondary is a foreground token', () {
      test('it clears 3:1 as a mark on every surface it can land on', () {
        for (final (label, bg) in [
          ('surface', s.surface),
          ('scaffold', theme.scaffoldBackgroundColor),
          ('surfaceContainerLowest', s.surfaceContainerLowest),
          ('surfaceContainerLow', s.surfaceContainerLow),
          ('surfaceContainer', s.surfaceContainer),
          ('surfaceContainerHigh', s.surfaceContainerHigh),
          ('surfaceContainerHighest', s.surfaceContainerHighest),
          ('primaryContainer', s.primaryContainer),
          ('secondaryContainer', s.secondaryContainer),
          ('tertiaryContainer', s.tertiaryContainer),
        ]) {
          expect(_contrast(s.secondary, bg), greaterThanOrEqualTo(_aaMark),
              reason: '$name secondary on $label — the mobile tree paints it '
                  'only as an icon, so 1.4.11 applies at every one of them');
        }
      });

      test('the onSecondary pairing clears AA', () {
        expect(_contrast(s.onSecondary, s.secondary),
            greaterThanOrEqualTo(_aaText));
      });
    });
  }

  group('the coral the light theme could not use', () {
    test('coralDeep fails 3:1 on parchment and on its own indicator tint', () {
      final pill = _over(
        AppTheme.coralDeep.withOpacity(0.18),
        AppTheme.parchment,
      );
      expect(_contrast(AppTheme.coralDeep, AppTheme.parchment), lessThan(3),
          reason: 'if this ever clears 3:1 the second coral has stopped '
              'earning its place — collapse the two');
      expect(_contrast(AppTheme.coralDeep, pill), lessThan(3));
      expect(_contrast(AppTheme.parchment, AppTheme.coralDeep), lessThan(3),
          reason: 'the FAB pairing that was shipping');
    });

    test('coralMark clears AA as text on every light surface, so a tint or a '
        'weight cannot push it under', () {
      final s = AppTheme.light.colorScheme;
      for (final bg in [
        s.surface,
        s.surfaceContainerLowest,
        s.surfaceContainerLow,
        s.surfaceContainer,
        s.surfaceContainerHigh,
        s.surfaceContainerHighest,
        s.primaryContainer,
        s.secondaryContainer,
        s.tertiaryContainer,
        AppTheme.parchmentDim,
      ]) {
        expect(_contrast(AppTheme.coralMark, bg),
            greaterThanOrEqualTo(_aaText));
      }
    });

    test('coralMark is the light secondary and coralDeep only ever a fill', () {
      expect(AppTheme.light.colorScheme.secondary, AppTheme.coralMark);
      expect(
        AppTheme.light.floatingActionButtonTheme.backgroundColor,
        AppTheme.coralDeep,
      );
      expect(
        AppTheme.light.navigationBarTheme.indicatorColor,
        AppTheme.coralDeep.withOpacity(0.18),
      );
    });
  });
}
