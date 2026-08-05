import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Chart-card-header guard (issue #666 S7). Five dashboard chart cards carried
/// three header typographies between them and a sixth carried none. The
/// eyebrow is the one shape now, and its colour has to clear WCAG 1.4.3's
/// 4.5:1 as text — `colorScheme.outline`, which two of those cards used, is a
/// 3:1 boundary token and reads 4.058:1 on the light card.
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

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme, {
  String title = 'Mileage',
  String? note,
  Widget? action,
  double textScale = 1.0,
  double width = 360,
}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ChartCardHeader(
                      title: title,
                      note: note,
                      action: action,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    group('$name chart card header', () {
      testWidgets('the eyebrow clears 4.5:1 on the card as text',
          (tester) async {
        await _pump(tester, theme, note: '30 d');
        final card = theme.cardTheme.color!;
        for (final label in ['Mileage', '30 d']) {
          final ratio = _contrast(_styleOf(tester, label).color!, card);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: '"$label" is $ratio against the $name card');
        }
      });

      // outline is the boundary token §487 pins at 3:1. Reusing it as text
      // borrows a non-text floor for a text job.
      testWidgets('the eyebrow does not paint in the boundary token',
          (tester) async {
        await _pump(tester, theme, note: '30 d');
        expect(_styleOf(tester, 'Mileage').color,
            isNot(theme.colorScheme.outline));
        expect(_styleOf(tester, '30 d').color, isNot(theme.colorScheme.outline));
      });

      testWidgets('title and note share one colour', (tester) async {
        await _pump(tester, theme, note: '30 d');
        expect(_styleOf(tester, '30 d').color, _styleOf(tester, 'Mileage').color);
      });
    });
  }

  testWidgets('the note sits on the title line when both fit', (tester) async {
    await _pump(tester, AppTheme.light, note: '30 d');
    expect(
      tester.getTopLeft(find.text('30 d')).dy,
      tester.getTopLeft(find.text('Mileage')).dy,
    );
  });

  // The reflow is the whole reason this is a Wrap: at 2x text scale a title
  // plus its running total no longer share a phone's width, and truncating
  // either loses real information.
  testWidgets('the note reflows below the title when it cannot fit',
      (tester) async {
    await _pump(
      tester,
      AppTheme.light,
      title: 'This Week',
      note: '10.00 km · 2 activities',
      textScale: 2.0,
      width: 320,
    );
    expect(
      tester.getTopLeft(find.text('10.00 km · 2 activities')).dy,
      greaterThan(tester.getTopLeft(find.text('This Week')).dy),
    );
  });

  testWidgets('a long title wraps rather than ellipsising', (tester) async {
    await _pump(
      tester,
      AppTheme.light,
      title: 'Charge dentraînement sur les quatre-vingt-dix derniers jours',
      width: 320,
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNull);
  });

  testWidgets('an action renders and a missing one adds no slot',
      (tester) async {
    await _pump(tester, AppTheme.light,
        action: const Chip(label: Text('Week')));
    expect(find.text('Week'), findsOneWidget);

    await _pump(tester, AppTheme.light);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('renders nothing but the title when note and action are null',
      (tester) async {
    await _pump(tester, AppTheme.light);
    expect(find.text('Mileage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
