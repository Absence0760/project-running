import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/safety_nudge_banner.dart';

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback onShare,
  required VoidCallback onDismiss,
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SafetyNudgeBanner(onShare: onShare, onDismiss: onDismiss),
      ),
    ),
  );
}

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

void main() {
  testWidgets('renders the prompt with Share + Not now actions',
      (tester) async {
    await _pump(tester, onShare: () {}, onDismiss: () {});
    expect(
      find.text(
          'Running solo after dark? Share a live link so someone can follow along.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Share'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Not now'), findsOneWidget);
  });

  testWidgets('Share fires onShare, not onDismiss', (tester) async {
    var shared = 0;
    var dismissed = 0;
    await _pump(tester,
        onShare: () => shared++, onDismiss: () => dismissed++);
    await tester.tap(find.widgetWithText(FilledButton, 'Share'));
    expect(shared, 1);
    expect(dismissed, 0);
  });

  testWidgets('Not now fires onDismiss, not onShare', (tester) async {
    var shared = 0;
    var dismissed = 0;
    await _pump(tester,
        onShare: () => shared++, onDismiss: () => dismissed++);
    await tester.tap(find.widgetWithText(TextButton, 'Not now'));
    expect(dismissed, 1);
    expect(shared, 0);
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('renders as an inverse-surface slab meeting WCAG AA ($name)',
        (tester) async {
      await _pump(tester, onShare: () {}, onDismiss: () {}, theme: theme);
      final scheme = theme.colorScheme;
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, scheme.inverseSurface);

      final prompt = tester.widget<Text>(find.text(
          'Running solo after dark? Share a live link so someone can follow along.'));
      expect(prompt.style?.color, scheme.onInverseSurface);
      expect(
        _contrast(scheme.onInverseSurface, scheme.inverseSurface),
        greaterThanOrEqualTo(4.5),
      );

      final notNow = tester.widget<Text>(find.text('Not now'));
      final blended = Color.alphaBlend(
        scheme.onInverseSurface.withValues(alpha: 0.75),
        scheme.inverseSurface,
      );
      expect(notNow.style?.color,
          scheme.onInverseSurface.withValues(alpha: 0.75));
      expect(
        _contrast(blended, scheme.inverseSurface),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}
