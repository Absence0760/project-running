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
  // Stretch the surface vertically so every Card in the ListView is
  // built + laid out — the default 800x600 viewport puts the lower
  // cards (CSV / Backup-ZIP) just past the offstage cliff so
  // `skipOffstage: false` alone isn't enough for ancestor finders.
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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

    testWidgets('shows CSV import card with the no-GPS caveat',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      // CSV + backup-ZIP cards sit below the fold in the default
      // 800x600 test viewport — `skipOffstage: false` reaches into
      // the ListView's off-screen children which are built eagerly
      // (the `children:` constructor, not `.builder`).
      expect(find.text('CSV', skipOffstage: false), findsOneWidget);
      // The body copy must explicitly tell the user CSV is trackless —
      // a CSV that silently produces empty maps would surprise the
      // user the moment they tap a row.
      expect(
        find.textContaining("won't have a route line", skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('Import CSV button is present and enabled', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      final btn = find.widgetWithText(FilledButton, 'Import CSV',
          skipOffstage: false);
      expect(btn, findsOneWidget);
      expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);
    });

    testWidgets('shows Full backup ZIP card with offline-first language',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      expect(find.text('Full backup ZIP', skipOffstage: false),
          findsOneWidget);
      // The card must call out that the path works signed-out — the
      // whole reason to surface it on the import screen rather than
      // leave it buried in Settings.
      expect(
        find.textContaining('without signing in', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('Restore backup ZIP button is present and enabled',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store);
      final btn = find.widgetWithText(FilledButton, 'Restore backup ZIP',
          skipOffstage: false);
      expect(btn, findsOneWidget);
      expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);
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

  group('buildImportStatus (#37)', () {
    test('Health Connect import appends the no-route note', () {
      final s = buildImportStatus(
        savedCount: 5,
        errorCount: 0,
        label: 'Health Connect',
        noGpsNote: true,
      );
      expect(s, contains('Imported 5 runs from Health Connect'));
      expect(s, contains('no map'));
    });

    test('non-HC import omits the note; zero-saved omits it too', () {
      expect(
        buildImportStatus(savedCount: 3, errorCount: 0, label: 'Strava'),
        'Imported 3 runs from Strava',
      );
      expect(
        buildImportStatus(
          savedCount: 0,
          errorCount: 0,
          label: 'Health Connect',
          noGpsNote: true,
        ),
        isNot(contains('no map')),
      );
    });
  });
}
