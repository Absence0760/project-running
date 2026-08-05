import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// SectionHeader guard (issue #666 V8). Three private `_SectionHeader` classes
/// carried two kinds between them; the list-group eyebrow is this one shape,
/// and at 11 sp it has to clear WCAG 1.4.3's 4.5:1 as text — which
/// `colorScheme.outline` does not on the light card.
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
  WidgetTester tester, {
  required ThemeData theme,
  String label = 'Recording',
  IconData? icon,
  Color? iconColor,
  Widget? trailing,
  double width = 360,
}) => tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SectionHeader(
                label: label,
                icon: icon,
                iconColor: iconColor,
                trailing: trailing,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('the label is uppercased by the header, not by the caller', (tester) async {
    await _pump(tester, theme: AppTheme.light, label: 'Recording');
    expect(find.text('RECORDING'), findsOneWidget);
    expect(find.text('Recording'), findsNothing);
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('the $name eyebrow clears 4.5:1 on the page', (tester) async {
      await _pump(tester, theme: theme);
      final style = tester.widget<Text>(find.text('RECORDING')).style!;
      expect(style.color, theme.colorScheme.onSurfaceVariant);
      expect(style.fontSize, theme.textTheme.labelSmall!.fontSize);
      expect(
        _contrast(style.color!, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  testWidgets('a long localized label ellipsises instead of overflowing', (tester) async {
    await _pump(
      tester,
      theme: AppTheme.light,
      label: 'Zusammenfassung der Trainingswoche',
      width: 80,
    );
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(
      find.text('ZUSAMMENFASSUNG DER TRAININGSWOCHE'),
    );
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('an icon takes the group colour and a trailing widget the end', (tester) async {
    await _pump(
      tester,
      theme: AppTheme.light,
      icon: Icons.star,
      iconColor: const Color(0xFF00FF00),
      trailing: const Text('more'),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.star)).color,
      const Color(0xFF00FF00),
    );
    expect(
      tester.getRect(find.text('more')).left,
      greaterThan(tester.getRect(find.text('RECORDING')).left),
    );
  });
}
