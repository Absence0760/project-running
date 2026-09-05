import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_crossings_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/checkpoint_checkin_screen.dart';
import 'pump_until.dart';
import 'store_write_watch.dart';

/// Fake [ApiClient] returning one checkpoint + no server crossings, recording
/// any upsert the screen pushes through the store's drain.
class _FakeApi extends ApiClient {
  final List<Map<String, dynamic>> upserts = [];
  bool requiresWeighIn = false;

  @override
  Future<List<EventCheckpointRow>> fetchEventCheckpoints(
      String eventId) async {
    return [
      EventCheckpointRow(
        id: 'cp-1',
        eventId: eventId,
        name: 'Mile 25 Aid',
        ordinal: 0,
        requiresWeighIn: requiresWeighIn,
        createdBy: 'organiser',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ];
  }

  @override
  Future<List<CheckpointCrossingRow>> fetchCheckpointCrossings(
      String eventId, DateTime instanceStart) async {
    return const [];
  }

  @override
  Future<void> upsertCheckpointCrossing({
    required String eventId,
    required String checkpointId,
    required DateTime instanceStart,
    String? userId,
    String? bib,
    String? runnerName,
    DateTime? inTime,
    DateTime? outTime,
    bool healthConsent = false,
    double? bodyWeightKg,
    double? bodyWeightPct,
    bool? medicalHold,
    String? medicalNote,
  }) async {
    upserts.add({'bib': bib, 'in_time': inTime, 'out_time': outTime});
  }
}

void main() {
  late Directory dir;
  late LocalCrossingsStore store;
  late _FakeApi api;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.loadFromString(isOptional: true);
  });

  setUp(() async {
    dotenv.env.remove('WEIGH_IN_GATE');
    dir = Directory.systemTemp.createTempSync('checkin_screen_test_');
    store = LocalCrossingsStore();
    await store.init(overrideDirectory: dir);
    api = _FakeApi();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget _app() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CheckpointCheckinScreen(
          eventId: 'evt-1',
          instanceStart: DateTime.utc(2026, 6, 14, 7),
          api: api,
          store: store,
        ),
      );

  // The load (store.init + api fetches) and the stamp's sync drain are real
  // async work (file I/O), so their completion time is load-dependent — a
  // fixed sleep flaked on a busy CI runner. Poll the observable condition
  // under runAsync with a bounded deadline instead. pumpAndSettle is avoided
  // — the loading spinner + the autofocused TextField cursor are perpetual
  // animations that hang it.
  ///
  /// [describe] is required for the reason decisions 723 gives: one generic
  /// sentence shared by every call site means an expired deadline no longer
  /// names the condition that never held.
  Future<void> _settleUntil(WidgetTester tester, bool Function() done,
          {required String describe}) =>
      pumpUntil(tester, done,
          describe: describe, timeout: const Duration(seconds: 5));

  Future<void> _pumpLoaded(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_app());
    });
    await tester.pump();
    await _settleUntil(tester, () => tester.any(find.byType(TextField)),
        describe: 'the bib field to replace the loading state');
  }

  testWidgets('stamping IN writes a pending crossing through the store',
      (tester) async {
    await _pumpLoaded(tester);
    final l10n = AppLocalizations.of(
        tester.element(find.byType(CheckpointCheckinScreen)));

    await tester.enterText(find.byType(TextField), '101');
    await tester.tap(find.text(l10n.checkpointStampIn));
    await _settleUntil(tester, () => api.upserts.isNotEmpty,
        describe: 'the stamp to drain through the sync RPC');

    expect(store.rows, hasLength(1));
    expect(store.rows.first['bib'], '101');
    expect(store.rows.first['in_time'], isNotNull);
    // The best-effort immediate sync drained it through the RPC.
    expect(api.upserts.single['bib'], '101');
    await pumpUntilStoreWritesSettle(tester);
    // The drain lets `_stamp` finish, which arms `showTopBanner`'s dismissal
    // timer; the widget tree may not be disposed under it.
    await tester.pump(const Duration(seconds: 4));
  });

  // The gate parses through the canonical isTruthyFlagValue, so it honours
  // every affirmative the rest of the product does. It used to accept `1` and
  // `true` alone, and `yes` — which turns every other gate on, on both
  // platforms — silently left these Art 9 fields off (decisions § 709).
  testWidgets('WEIGH_IN_GATE=yes gates the stamp behind the weigh-in sheet',
      (tester) async {
    dotenv.env['WEIGH_IN_GATE'] = 'yes';
    api.requiresWeighIn = true;
    await _pumpLoaded(tester);
    final l10n = AppLocalizations.of(
        tester.element(find.byType(CheckpointCheckinScreen)));

    await tester.enterText(find.byType(TextField), '101');
    await tester.tap(find.text(l10n.checkpointStampIn));
    await _settleUntil(
        tester, () => tester.any(find.text(l10n.checkpointWeighInTitle)),
        describe: 'the Art 9 weigh-in sheet the gate opens');

    // The sheet is open and nothing has been written: the stamp waits on it.
    expect(store.rows, isEmpty);
    expect(api.upserts, isEmpty);
  });

  testWidgets('an unrecognised WEIGH_IN_GATE value leaves the fields off',
      (tester) async {
    dotenv.env['WEIGH_IN_GATE'] = 'maybe';
    api.requiresWeighIn = true;
    await _pumpLoaded(tester);
    final l10n = AppLocalizations.of(
        tester.element(find.byType(CheckpointCheckinScreen)));

    await tester.enterText(find.byType(TextField), '101');
    await tester.tap(find.text(l10n.checkpointStampIn));
    await _settleUntil(tester, () => api.upserts.isNotEmpty,
        describe: 'the ungated stamp to drain through the sync RPC');

    expect(find.text(l10n.checkpointWeighInTitle), findsNothing);
    expect(store.rows.single['bib'], '101');
    await pumpUntilStoreWritesSettle(tester);
    // The drain lets `_stamp` finish, which arms `showTopBanner`'s dismissal
    // timer; the widget tree may not be disposed under it.
    await tester.pump(const Duration(seconds: 4));
  });

  /// Open the weigh-in sheet and reveal the weight field behind its Art 9
  /// consent toggle, returning the field's decoration.
  Future<InputDecoration> _weighInDecoration(WidgetTester tester) async {
    dotenv.env['WEIGH_IN_GATE'] = 'yes';
    api.requiresWeighIn = true;
    // The sheet is a tall unscrolled Column; on the default 800x600 surface
    // the consent switch sits below the fold and the tap misses it.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpLoaded(tester);
    final l10n = AppLocalizations.of(
        tester.element(find.byType(CheckpointCheckinScreen)));
    await tester.enterText(find.byType(TextField), '101');
    await tester.tap(find.text(l10n.checkpointStampIn));
    await _settleUntil(
        tester, () => tester.any(find.text(l10n.checkpointWeighInTitle)),
        describe: 'the Art 9 weigh-in sheet the gate opens');
    // The sheet is findable while it is still sliding up from below the fold,
    // so a tap now lands off the bottom of the render tree. Advance the
    // slide-in explicitly — pumpAndSettle hangs on the bib field's cursor.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(SwitchListTile));
    await _settleUntil(
        tester, () => tester.any(find.text(l10n.checkpointWeighInBodyWeight)),
        describe: 'the weight field the consent toggle reveals');
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((f) => f.decoration?.suffixText != null)
        .toList();
    expect(fields, hasLength(1),
        reason: 'exactly one field on the sheet carries a unit suffix');
    return fields.single.decoration!;
  }

  // The label used to be `checkpointWeighInWeightKg` — "Body weight (kg)" in
  // every locale — beside a suffix carrying the runner's OWN unit, so a runner
  // on lbs read "Body weight (kg)" with an "lbs" suffix: two units in one
  // field, one of them wrong (decisions § 820). The suffix is the authority,
  // so the label names no unit at all.
  testWidgets('the weight label names no unit; the suffix carries the real one',
      (tester) async {
    SharedPreferences.setMockInitialValues({'weight_unit': 'lbs'});
    final prefs = Preferences();
    await prefs.init();
    registerActivePreferences(prefs);
    addTearDown(resetActivePreferencesForTest);
    expect(activeWeightUnit, WeightUnit.lbs);

    final decoration = await _weighInDecoration(tester);
    expect(decoration.suffixText, 'lbs');
    expect(decoration.labelText, isNotNull);
    expect(decoration.labelText, isNot(contains('kg')));
    expect(decoration.labelText, isNot(contains('lbs')));
  });

  // The widget test above can only read the locale it renders. This reads the
  // string every locale ships, because a translator restoring "(kg)" in one
  // catalogue puts the contradiction back for that language alone.
  test('no locale names a unit in the weigh-in weight label', () {
    const key = 'checkpointWeighInBodyWeight';
    final arbs = Directory('${Directory.current.path}/lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .toList();
    expect(arbs, hasLength(7), reason: 'expected the seven shipped catalogues');
    for (final f in arbs) {
      final bag = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final value = bag[key] as String?;
      expect(value, isNotNull, reason: '$key missing from ${f.path}');
      for (final unit in const ['kg', 'lb', 'キロ', '(', 'kilo']) {
        expect(value!.toLowerCase().contains(unit.toLowerCase()), isFalse,
            reason: '${f.path} names "$unit" in $key — the field suffix is '
                "the runner's own unit and would contradict it");
      }
    }
  });

  testWidgets('an empty bib is rejected without writing', (tester) async {
    await _pumpLoaded(tester);
    final l10n = AppLocalizations.of(
        tester.element(find.byType(CheckpointCheckinScreen)));

    // Absence assertion — no condition to poll for; give any (wrong) write a
    // generous window to land before asserting nothing did. The tap stays
    // inside runAsync so the rejection banner's auto-dismiss timer is created
    // in the real zone, not the fake-timer zone the binding asserts empty.
    await tester.runAsync(() async {
      await tester.tap(find.text(l10n.checkpointStampIn));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(store.rows, isEmpty);
    expect(api.upserts, isEmpty);
  });
}
