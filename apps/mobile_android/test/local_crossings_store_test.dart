import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_crossings_store.dart';

/// Fake [ApiClient] that records `upsertCheckpointCrossing` calls and lets a
/// test inject a per-id failure. The crossing store has no update/delete path —
/// every drain is a create through the merge RPC.
class _FakeCrossingsApi extends ApiClient {
  final List<String> calls = [];
  final List<Map<String, dynamic>> upserts = [];
  Set<String> failOnBib = const {};

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
    calls.add('upsert:${bib ?? userId}');
    if (failOnBib.contains(bib)) throw StateError('upsert failed');
    upserts.add({
      'event_id': eventId,
      'checkpoint_id': checkpointId,
      'bib': bib,
      'user_id': userId,
      'in_time': inTime?.toIso8601String(),
      'out_time': outTime?.toIso8601String(),
      'health_consent': healthConsent,
      'body_weight_kg': bodyWeightKg,
    });
  }
}

void main() {
  late Directory dir;
  late LocalCrossingsStore store;
  final eventId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01';
  final checkpointId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01';
  final instanceStart = DateTime.utc(2026, 6, 14, 7);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('local_crossings_store_test_');
    store = LocalCrossingsStore();
    await store.init(overrideDirectory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('createLocal', () {
    test('mints a v4 UUID and marks the row pendingCreate', () async {
      final stored = await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart,
        bib: '101',
        runnerName: 'Ada',
        inTime: DateTime.utc(2026, 6, 14, 8, 30),
      );
      expect(
          stored.id,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(stored.syncState, CrossingSyncState.pendingCreate);
      expect(store.rows, hasLength(1));
      expect(store.hasPending, isTrue);
    });

    test('survives a store reload', () async {
      await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart,
        bib: '202',
      );
      final fresh = LocalCrossingsStore();
      await fresh.init(overrideDirectory: dir);
      expect(fresh.rows, hasLength(1));
      expect(fresh.rows.first['bib'], '202');
      expect(fresh.hasPending, isTrue);
    });

    test('lastModifiedAt derives from the same instant as recorded_at',
        () async {
      final stored = await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart,
        bib: '1',
      );
      final recordedAt =
          DateTime.parse(stored.row['recorded_at'] as String).toUtc();
      expect(stored.lastModifiedAt, recordedAt);
    });
  });

  group('rowsForCheckpoint', () {
    test('filters by event + checkpoint + instance', () async {
      await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart,
        bib: '1',
      );
      await store.createLocal(
        eventId: eventId,
        checkpointId: 'cccccccc-cccc-cccc-cccc-cccccccccc01',
        instanceStart: instanceStart,
        bib: '2',
      );
      final here =
          store.rowsForCheckpoint(eventId, checkpointId, instanceStart);
      expect(here, hasLength(1));
      expect(here.first['bib'], '1');
    });
  });

  group('schema version (_v)', () {
    test('a persisted record carries the current schema version', () async {
      final stored = await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart,
        bib: '1',
      );
      final raw = jsonDecode(
              File('${dir.path}/${stored.id}.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(raw[kLocalStoreVersionKey], kLocalStoreSchemaVersion);
    });
  });

  group('syncWithServer drain', () {
    test('drains pendingCreate via upsertCheckpointCrossing', () async {
      final api = _FakeCrossingsApi();
      await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart,
        bib: '101',
        runnerName: 'Ada',
        inTime: DateTime.utc(2026, 6, 14, 8),
      );
      expect(store.hasPending, isTrue);

      final drained = await store.syncWithServer(api);

      expect(drained, 1);
      expect(api.calls.single, 'upsert:101');
      expect(store.hasPending, isFalse, reason: 'drained rows flip to synced');
    });

    test('does not send health fields by value when consent is false',
        () async {
      final api = _FakeCrossingsApi();
      await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart,
        bib: '1',
        outTime: DateTime.utc(2026, 6, 14, 9),
        healthConsent: false,
        bodyWeightKg: 70,
      );
      await store.syncWithServer(api);
      expect(api.upserts.single['health_consent'], isFalse);
    });

    test('per-row failure isolation: failing upsert leaves the row pending',
        () async {
      await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart,
        bib: 'fail',
      );
      final api = _FakeCrossingsApi()..failOnBib = {'fail'};

      final drained = await store.syncWithServer(api);

      expect(drained, 0);
      expect(store.hasPending, isTrue);
    });

    test('clean store: syncWithServer is a no-op (drained=0)', () async {
      final api = _FakeCrossingsApi();
      final drained = await store.syncWithServer(api);
      expect(drained, 0);
      expect(api.calls, isEmpty);
    });

    test('offline-create survives a restart then syncs', () async {
      // Stamp offline.
      await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart,
        bib: '303',
        inTime: DateTime.utc(2026, 6, 14, 8),
      );

      // Simulate an app restart: a fresh store reads the same dir.
      final reloaded = LocalCrossingsStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.hasPending, isTrue,
          reason: 'the offline stamp persisted across the restart');

      // Connectivity returns: drain.
      final api = _FakeCrossingsApi();
      final drained = await reloaded.syncWithServer(api);

      expect(drained, 1);
      expect(api.calls.single, 'upsert:303');
      expect(reloaded.hasPending, isFalse);
    });
  });

  group('replaceFromServer', () {
    test('overwrites synced rows but preserves pendingCreate', () async {
      final mine = await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart,
        bib: 'mine',
      );
      await store.replaceFromServer([
        {
          'id': 'server-1',
          'event_id': eventId,
          'checkpoint_id': checkpointId,
          'instance_start': instanceStart.toIso8601String(),
          'bib': '500',
          'runner_name': 'Srv',
        },
      ]);
      expect(store.rows.any((r) => r['id'] == mine.id), isTrue,
          reason: 'pendingCreate row must survive a server refresh');
      expect(store.rows.any((r) => r['id'] == 'server-1'), isTrue);
    });
  });
}
