import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// App-bar scrolled-under guard (issue #666 C3). Both brightnesses used to
/// pair `elevation: 0` with `scrolledUnderElevation: 0` over a background
/// equal to the scaffold, so a pinned bar was indistinguishable from the list
/// travelling under it. The bar now resolves a distinct background in the
/// `scrolledUnder` state — the same state `AppBar` itself resolves the theme
/// colour through — and the seed's surface tint is disabled, because its
/// hue does not belong on this palette.
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

Color _bg(ThemeData theme, Set<WidgetState> states) =>
    WidgetStateProperty.resolveAs<Color>(theme.appBarTheme.backgroundColor!, states);

void main() {
  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
    group('$name app bar', () {
      test('at rest it matches the scaffold', () {
        expect(_bg(theme, const {}), theme.scaffoldBackgroundColor);
      });

      test('scrolled under it becomes a distinguishable surface', () {
        final resting = _bg(theme, const {});
        final scrolled = _bg(theme, const {WidgetState.scrolledUnder});
        expect(scrolled, isNot(resting));
        expect(
          _contrast(scrolled, resting),
          greaterThan(1.1),
          reason: 'the scrolled-under fill must be a real tonal step, not '
              'the 1.05:1 M3 default',
        );
      });

      test('the title stays legible on the scrolled-under fill', () {
        expect(
          _contrast(
            theme.appBarTheme.foregroundColor!,
            _bg(theme, const {WidgetState.scrolledUnder}),
          ),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('it raises on scroll and never paints the seed tint', () {
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, greaterThan(0));
        expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
      });
    });
  }

  testWidgets('AppBar picks up the scrolled-under fill from the theme',
      (tester) async {
    final theme = AppTheme.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          appBar: AppBar(title: const Text('t')),
          body: ListView(
            children: List.generate(40, (i) => SizedBox(height: 60, child: Text('$i'))),
          ),
        ),
      ),
    );

    Color barColor() => tester
        .widget<Material>(find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(Material),
        ).first)
        .color!;

    expect(barColor(), theme.scaffoldBackgroundColor);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(barColor(),
        _bg(theme, const {WidgetState.scrolledUnder}));
  });
}
