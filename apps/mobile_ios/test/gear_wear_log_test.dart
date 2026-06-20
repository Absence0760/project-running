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

void main() {
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
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(api.addCalls, 1);
      expect(api.lastAddNote, 'midsole dead');
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
