import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gear_store.dart';
import '../lib/preferences.dart';
import '../lib/widgets/gear_form_sheet.dart';

Future<({LocalGearStore store, Directory dir, Preferences prefs})> _setup(
    String tag) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  final dir = Directory.systemTemp.createTempSync('gear_form_$tag');
  final store = LocalGearStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir, prefs: prefs);
}

Widget _opener(
  LocalGearStore store,
  Preferences prefs, {
  void Function(GearFormResult?)? onResult,
}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await showGearFormSheet(
                  context: ctx,
                  store: store,
                  preferences: prefs,
                  kind: 'shoe',
                );
                onResult?.call(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, Widget app) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
  await tester.tap(find.text('open'));
  // fullscreenDialog route: avoid pumpAndSettle (slide-in + cursor never
  // settle under the fake clock).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
      'opens as a full-screen dialog with the Add shoes heading + Name field',
      (tester) async {
    final f = await _setup('title');
    try {
      await _open(tester, _opener(f.store, f.prefs));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Add shoes'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
      // fullscreenDialog injects a Close affordance, not a Back arrow.
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('Cancel returns null and writes nothing', (tester) async {
    final f = await _setup('cancel');
    GearFormResult? result;
    var called = false;
    try {
      await _open(
        tester,
        _opener(f.store, f.prefs, onResult: (r) {
          result = r;
          called = true;
        }),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(called, isTrue);
      expect(result, isNull);
      expect(f.store.rows, isEmpty);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('entering a name + Add writes a pendingCreate row to the store',
      (tester) async {
    // The popped GearFormResult value-delivery + dialog dismissal are
    // covered by full_screen_form_test (synchronous pop). Here we pin the
    // gear-specific store write. _save's pop continuation can't resume under
    // the fake clock once createLocal's real file write is in flight (the
    // documented testWidgets + store-IO gotcha), so we assert only the
    // in-memory write createLocal performs before that await.
    final f = await _setup('create');
    try {
      await _open(tester, _opener(f.store, f.prefs));
      await tester.enterText(
          find.widgetWithText(TextField, 'Name'), 'Vaporfly');
      await tester.ensureVisible(find.text('Add'));
      await tester.tap(find.text('Add'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      expect(f.store.rows, hasLength(1));
      expect(f.store.rows.first['name'], 'Vaporfly');
      expect(f.store.rows.first['kind'], 'shoe');
      expect(f.store.rows.first['target_distance_m'], isNull);
      expect(f.store.rows.first['brand'], isNull);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
