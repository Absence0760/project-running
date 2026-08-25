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
import '../lib/widgets/undo_bar.dart';
import 'pump_until.dart';

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

/// The sheet's store, temp dir and preferences, plus a `persisted` probe.
///
/// `OfflineSyncStore.persist` populates the in-memory rows BEFORE its atomic
/// write and notifies only once the row file and the index are both down, so
/// the notification — not the row count — is what says the write has cleared
/// the temp dir's teardown.
Future<
    ({
      LocalGearStore store,
      Directory dir,
      Preferences prefs,
      bool Function() persisted
    })> _setup(String tag) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  final dir = Directory.systemTemp.createTempSync('gear_form_$tag');
  final store = LocalGearStore();
  await store.init(overrideDirectory: dir);
  var persisted = false;
  store.addListener(() => persisted = true);
  return (store: store, dir: dir, prefs: prefs, persisted: () => persisted);
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
  tearDown(debugResetUndo);

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
      await pumpUntil(tester, f.persisted,
          describe: "the gear row's files to land on disk");

      expect(f.store.rows, hasLength(1));
      expect(f.store.rows.first['name'], 'Vaporfly');
      expect(f.store.rows.first['kind'], 'shoe');
      expect(f.store.rows.first['target_distance_m'], isNull);
      expect(f.store.rows.first['brand'], isNull);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  // Issue #666 U8, mobile half: the wear-log delete dropped its confirm dialog
  // for a deferred, undoable delete (decisions § 514). These two replace the
  // Cancel-keeps-it / confirm-deletes-it pair that pinned the dialog.
  testWidgets(
      'wear-log delete: Undo keeps the note and calls no api delete',
      (tester) async {
    final f = await _setup('wearlog_undo');
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
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('resoled outsole'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pump();

      expect(find.text('resoled outsole'), findsOneWidget);
      expect(api.deleteCalls, 0);
      await tester.pump(const Duration(seconds: 9));
      expect(api.deleteCalls, 0);
      // Drain the Restored banner's auto-dismiss timer.
      await tester.pump(const Duration(seconds: 4));
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'wear-log delete: the window closing deletes the note via the api',
      (tester) async {
    final f = await _setup('wearlog_commit');
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
      expect(api.deleteCalls, 0,
          reason: 'nothing is destroyed while undo is on offer');

      await tester.pump(const Duration(seconds: 9));
      expect(find.text('resoled outsole'), findsNothing);
      expect(api.deleteCalls, 1);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
