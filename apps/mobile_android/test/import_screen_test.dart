import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/local_run_store.dart';
import 'package:mobile_android/screens/import_screen.dart';

late Directory _runsDir;

Future<LocalRunStore> _makeStore() async {
  _runsDir = Directory.systemTemp.createTempSync('import_screen_test_');
  final store = LocalRunStore();
  await store.init(overrideDirectory: _runsDir);
  return store;
}

Future<void> _pump(WidgetTester tester, LocalRunStore runStore) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ImportScreen(
        apiClient: null,
        runStore: runStore,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('ImportScreen', () {
    testWidgets('renders Import runs app-bar title', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      expect(find.text('Import runs'), findsOneWidget);
    });

    testWidgets('shows Strava import card with heading and description',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      expect(find.text('Strava'), findsOneWidget);
      expect(find.textContaining('Strava data export ZIP'), findsOneWidget);
    });

    testWidgets('shows Health Connect import card with heading', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      expect(find.text('Health Connect'), findsOneWidget);
    });

    testWidgets('Import Strava ZIP button is present and enabled', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      final btn = find.widgetWithText(FilledButton, 'Import Strava ZIP');
      expect(btn, findsOneWidget);
      // onPressed must be non-null when _busy == false (i.e., the button is enabled).
      final widget = tester.widget<FilledButton>(btn);
      expect(widget.onPressed, isNotNull);
    });

    testWidgets('Import from Health Connect button is present and enabled',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      final btn = find.widgetWithText(FilledButton, 'Import from Health Connect');
      expect(btn, findsOneWidget);
      final widget = tester.widget<FilledButton>(btn);
      expect(widget.onPressed, isNotNull);
    });

    testWidgets('status card is absent before any import is triggered',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      // The status card only renders when _busy == true or _status is
      // non-empty — neither holds on initial paint.
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}
