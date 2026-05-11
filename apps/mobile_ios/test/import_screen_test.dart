import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/local_run_store.dart';
import '../lib/screens/import_screen.dart';

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

  group('Platform-aware Health label helpers', () {
    test('healthLabelFor names HealthKit on iOS, Health Connect on Android',
        () {
      expect(healthLabelFor(isIOS: true), 'Apple Health');
      expect(healthLabelFor(isIOS: false), 'Health Connect');
    });

    test(
        'healthCardSubtitleFor names iOS source apps on iOS, Android on Android',
        () {
      expect(
        healthCardSubtitleFor(isIOS: true),
        contains('Apple Watch'),
        reason: 'iOS subtitle should mention Apple Watch',
      );
      expect(
        healthCardSubtitleFor(isIOS: true),
        contains('Apple Health'),
      );
      expect(
        healthCardSubtitleFor(isIOS: false),
        contains('Google Fit'),
      );
      expect(
        healthCardSubtitleFor(isIOS: false),
        contains('Health Connect'),
      );
    });

    test('healthCardDescriptionFor names the platform store in the caveat',
        () {
      expect(
        healthCardDescriptionFor(isIOS: true),
        contains('Apple Health'),
      );
      expect(
        healthCardDescriptionFor(isIOS: false),
        contains('Health Connect'),
      );
      // Both variants must call out the no-GPS-track caveat — without
      // it the user is surprised by trackless runs in their history.
      expect(
        healthCardDescriptionFor(isIOS: true),
        contains("won't have a map trace"),
      );
      expect(
        healthCardDescriptionFor(isIOS: false),
        contains("won't have a map trace"),
      );
    });
  });
}
