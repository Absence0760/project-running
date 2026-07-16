import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gear_store.dart';
import '../lib/preferences.dart';
import '../lib/widgets/gear_form_sheet.dart';

/// Fakes the gear wear-log endpoints only; every other ApiClient method
/// is unused by this sheet when [existing] carries an id + [api] is
/// wired, since the rest of the form writes through [LocalGearStore].
class _WearLogApi extends ApiClient {
  _WearLogApi(this._logs);
  final List<GearWearLogRow> _logs;
  int deleteCalls = 0;

  @override
  Future<List<GearWearLogRow>> fetchGearWearLogs(String gearId) async =>
      _logs;

  @override
  Future<void> deleteGearWearLog(String id) async {
    deleteCalls++;
  }
}

GearWearLogRow _wearLog() => GearWearLogRow(
      id: 'log-1',
      gearId: 'gear-1',
      ownerId: 'owner-1',
      loggedOn: DateTime(2026, 1, 1),
      area: 'outsole',
      note: 'resoled outsole',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

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
  Map<String, dynamic>? existing,
  ApiClient? api,
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
                  existing: existing,
                  api: api,
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

  testWidgets(
      'wear-log delete: Cancel in the confirm dialog keeps the note and '
      'calls no api delete', (tester) async {
    final f = await _setup('wearlog_cancel');
    final api = _WearLogApi([_wearLog()]);
    try {
      await _open(
        tester,
        _opener(f.store, f.prefs,
            existing: {'id': 'gear-1', 'name': 'Vaporfly'}, api: api),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('resoled outsole'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete observation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('resoled outsole'), findsOneWidget);
      expect(api.deleteCalls, 0);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'wear-log delete: confirming the dialog deletes the note via the api',
      (tester) async {
    final f = await _setup('wearlog_confirm');
    final api = _WearLogApi([_wearLog()]);
    try {
      await _open(
        tester,
        _opener(f.store, f.prefs,
            existing: {'id': 'gear-1', 'name': 'Vaporfly'}, api: api),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('resoled outsole'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete observation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Delete'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('resoled outsole'), findsNothing);
      expect(api.deleteCalls, 1);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
