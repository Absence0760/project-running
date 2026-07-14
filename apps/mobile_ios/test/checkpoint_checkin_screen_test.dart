import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_crossings_store.dart';
import '../lib/screens/checkpoint_checkin_screen.dart';

/// Fake [ApiClient] returning one checkpoint + no server crossings, recording
/// any upsert the screen pushes through the store's drain.
class _FakeApi extends ApiClient {
  final List<Map<String, dynamic>> upserts = [];

  @override
  Future<List<EventCheckpointRow>> fetchEventCheckpoints(
      String eventId) async {
    return [
      EventCheckpointRow(
        id: 'cp-1',
        eventId: eventId,
        name: 'Mile 25 Aid',
        ordinal: 0,
        requiresWeighIn: false,
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

  setUp(() async {
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
  Future<void> _settleUntil(WidgetTester tester, bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'condition not reached within 5s');
  }

  Future<void> _pumpLoaded(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_app());
    });
    await tester.pump();
    await _settleUntil(tester, () => tester.any(find.byType(TextField)));
  }

  testWidgets('stamping IN writes a pending crossing through the store',
      (tester) async {
    await _pumpLoaded(tester);
    final l10n = AppLocalizations.of(
        tester.element(find.byType(CheckpointCheckinScreen)));

    await tester.enterText(find.byType(TextField), '101');
    await tester.tap(find.text(l10n.checkpointStampIn));
    await _settleUntil(tester, () => api.upserts.isNotEmpty);

    expect(store.rows, hasLength(1));
    expect(store.rows.first['bib'], '101');
    expect(store.rows.first['in_time'], isNotNull);
    // The best-effort immediate sync drained it through the RPC.
    expect(api.upserts.single['bib'], '101');
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
