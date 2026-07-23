import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/live_share_indicator.dart';

Future<void> _pumpIndicator(WidgetTester tester,
    {required VoidCallback onTap}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: LiveShareIndicator(onTap: onTap)),
    ),
  );
}

/// Pumps a button that opens the sheet and records the resolved action.
Future<void> _pumpSheetHost(
  WidgetTester tester, {
  required void Function(LiveShareAction?) onResolved,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async =>
                  onResolved(await showLiveShareSheet(context)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('indicator renders the Live label and fires onTap',
      (tester) async {
    var taps = 0;
    await _pumpIndicator(tester, onTap: () => taps++);
    expect(find.text('Live'), findsOneWidget);
    expect(find.byIcon(Icons.podcasts), findsOneWidget);
    await tester.tap(find.byType(LiveShareIndicator));
    expect(taps, 1);
  });

  testWidgets('sheet renders the title and both actions', (tester) async {
    await _pumpSheetHost(tester, onResolved: (_) {});
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Live sharing on'), findsOneWidget);
    expect(find.text('Share link again'), findsOneWidget);
    expect(find.text('Stop sharing'), findsOneWidget);
  });

  testWidgets('picking "Share link again" resolves reshare', (tester) async {
    LiveShareAction? resolved;
    var called = false;
    await _pumpSheetHost(tester, onResolved: (a) {
      resolved = a;
      called = true;
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share link again'));
    await tester.pumpAndSettle();
    expect(called, true);
    expect(resolved, LiveShareAction.reshare);
  });

  testWidgets('picking "Stop sharing" resolves stop', (tester) async {
    LiveShareAction? resolved;
    await _pumpSheetHost(tester, onResolved: (a) => resolved = a);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop sharing'));
    await tester.pumpAndSettle();
    expect(resolved, LiveShareAction.stop);
  });

  testWidgets('dismissing the sheet resolves null', (tester) async {
    LiveShareAction? resolved;
    var called = false;
    await _pumpSheetHost(tester, onResolved: (a) {
      resolved = a;
      called = true;
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Tap the scrim above the sheet to dismiss.
    await tester.tapAt(const Offset(200, 100));
    await tester.pumpAndSettle();
    expect(called, true);
    expect(resolved, isNull);
  });
}
