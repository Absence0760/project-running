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

GearWearLogRow _log({
  String id = 'l1',
  String note = 'outsole worn',
  String? area = 'outsole',
}) =>
    GearWearLogRow(
      id: id,
      gearId: 'g1',
      ownerId: 'viewer-1',
      loggedOn: DateTime(2026, 6, 18),
      area: area,
      note: note,
      createdAt: DateTime(2026, 6, 18),
      updatedAt: DateTime(2026, 6, 18),
    );

class _WearApi extends ApiClient {
  _WearApi({List<GearWearLogRow>? seed}) : _rows = List.of(seed ?? const []);

  final List<GearWearLogRow> _rows;
  int addCalls = 0;
  int deleteCalls = 0;
  String? lastAddNote;
  String? lastAddArea;

  @override
  String? get userId => 'viewer-1';

  @override
  Future<List<GearWearLogRow>> fetchGearWearLogs(String gearId) async =>
      List.of(_rows);

  @override
  Future<GearWearLogRow> addGearWearLog({
    required String gearId,
    required String note,
    String? area,
    DateTime? loggedOn,
  }) async {
    addCalls++;
    lastAddNote = note;
    lastAddArea = area;
    return _log(id: 'new', note: note, area: area);
  }

  @override
  Future<void> deleteGearWearLog(String id) async {
    deleteCalls++;
  }
}

Future<({LocalGearStore store, Directory dir, Preferences prefs})>
    _setup(String tag) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  final dir = Directory.systemTemp.createTempSync('gear_wear_$tag');
  final store = LocalGearStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir, prefs: prefs);
}

Widget _opener(
  LocalGearStore store,
  Preferences prefs,
  ApiClient api,
  Map<String, dynamic> existing,
) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showGearFormSheet(
                context: ctx,
                store: store,
                preferences: prefs,
                kind: 'shoe',
                existing: existing,
                api: api,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Map<String, dynamic> _existing() => {
      'id': 'g1',
      'kind': 'shoe',
      'name': 'Pegasus',
      'brand': null,
      'model': null,
      'notes': null,
      'purchased_at': null,
      'target_distance_m': null,
    };

Future<void> _open(WidgetTester tester, Widget app) async {
  await tester.binding.setSurfaceSize(const Size(420, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The armed undo window owns a real Timer; a test that ends with it pending
/// fails on `!timersPending`.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 9));

void main() {
  tearDown(debugResetUndo);

  // Issue #666 U8, mobile half. This delete is the in-modal case § 521 had to
  // widen web's Tab trap for: the affordance lives inside a full-screen form
  // route. Mobile's pill is a root overlay entry, so it lands ABOVE the modal
  // barrier and stays reachable — see undo_bar_test.dart for the semantics
  // measurement, and the pill's reachability here for the wiring.
  group('deleting an observation offers undo instead of a confirm', () {
    testWidgets('the delete is deferred, and the pill is reachable over the '
        'form route', (tester) async {
      final f = await _setup('undo_defer');
      final api = _WearApi(seed: [_log(note: 'lugs gone')]);
      try {
        await _open(tester, _opener(f.store, f.prefs, api, _existing()));
        await tester.ensureVisible(find.byTooltip('Delete observation'));
        await tester.tap(find.byTooltip('Delete observation'));
        await tester.pump();

        expect(find.byType(AlertDialog), findsNothing,
            reason: 'confirm and undo are alternatives, not partners');
        expect(find.text('lugs gone'), findsNothing);
        expect(find.text('Observation removed'), findsOneWidget);
        expect(find.text('Undo'), findsOneWidget);
        expect(api.deleteCalls, 0);

        await _drain(tester);
        expect(api.deleteCalls, 1);
      } finally {
        f.dir.deleteSync(recursive: true);
      }
    });

    testWidgets('Undo puts the observation back untouched', (tester) async {
      final f = await _setup('undo_restore');
      final api = _WearApi(seed: [_log(note: 'lugs gone')]);
      try {
        await _open(tester, _opener(f.store, f.prefs, api, _existing()));
        await tester.ensureVisible(find.byTooltip('Delete observation'));
        await tester.tap(find.byTooltip('Delete observation'));
        await tester.pump();
        await tester.tap(find.text('Undo'));
        await tester.pump();

        expect(find.text('lugs gone'), findsOneWidget);
        await _drain(tester);
        expect(api.deleteCalls, 0);
      } finally {
        f.dir.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('wear log renders seeded observations on the edit form',
      (tester) async {
    final f = await _setup('render');
    try {
      await _open(
        tester,
        _opener(f.store, f.prefs, _WearApi(seed: [_log(note: 'lugs gone')]),
            _existing()),
      );
      expect(find.text('Wear log'), findsOneWidget);
      expect(find.text('lugs gone'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('empty wear log shows the empty state', (tester) async {
    final f = await _setup('empty');
    try {
      await _open(tester, _opener(f.store, f.prefs, _WearApi(), _existing()));
      expect(find.text('No wear observations yet.'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('adding an observation calls the api with the note',
      (tester) async {
    final f = await _setup('add');
    final api = _WearApi();
    try {
      await _open(tester, _opener(f.store, f.prefs, api, _existing()));
      await tester.enterText(
          find.widgetWithText(TextField, 'Observation'), 'midsole dead');
      await tester.ensureVisible(find.text('Add observation'));
      await tester.tap(find.text('Add observation'));
      await pumpUntil(tester, () => api.addCalls > 0,
          describe: 'the observation to reach the api');
      expect(api.addCalls, 1);
      expect(api.lastAddNote, 'midsole dead');
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
