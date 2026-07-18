import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/safety_nudge_banner.dart';

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback onShare,
  required VoidCallback onDismiss,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SafetyNudgeBanner(onShare: onShare, onDismiss: onDismiss),
      ),
    ),
  );
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
}
