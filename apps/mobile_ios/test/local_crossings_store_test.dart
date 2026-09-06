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
      'instance_start': instanceStart,
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

    test('matches an occurrence however the stored row SPELLS it', () async {
      // decisions § 1343. One occurrence has several spellings on the wire:
      // PostgREST answers `+00:00`, `CheckpointCrossingRow.toJson` re-writes
      // that as `.000Z`, and a row this store wrote before § 1343 carries the
      // writer's bare local wall clock. The old string equality matched only
      // the last of the three, so a server-fetched crossing never appeared in
      // "who has already been stamped here".
      final spellings = <String, String>{
        'postgrest': '2026-06-14T07:00:00+00:00',
        'row-dto': '2026-06-14T07:00:00.000Z',
        'offset': '2026-06-14T09:00:00+02:00',
        'legacy-local':
            DateTime.utc(2026, 6, 14, 7).toLocal().toIso8601String(),
      };
      await store.replaceFromServer([
        for (final e in spellings.entries)
          <String, dynamic>{
            'id': 'aaaaaaaa-aaaa-aaaa-aaaa-0000000000${spellings.keys.toList().indexOf(e.key)}0',
            'event_id': eventId,
            'checkpoint_id': checkpointId,
            'instance_start': e.value,
            'bib': e.key,
            'recorded_at': DateTime.utc(2026, 6, 14, 7, 5).toIso8601String(),
          },
      ]);
      final here =
          store.rowsForCheckpoint(eventId, checkpointId, instanceStart);
      expect(here.map((r) => r['bib']).toSet(), spellings.keys.toSet());
    });

    test('a DIFFERENT occurrence of the same series is still excluded',
        () async {
      // The instant comparison must not have widened the filter into a
      // same-event-and-checkpoint match: a weekly series files each week
      // under its own key and the screen shows one of them.
      await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart,
        bib: 'this-week',
      );
      await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: instanceStart.add(const Duration(days: 7)),
        bib: 'next-week',
      );
      final here =
          store.rowsForCheckpoint(eventId, checkpointId, instanceStart);
      expect(here.map((r) => r['bib']), ['this-week']);
    });

    test('an unreadable stored instance matches nothing', () async {
      await store.replaceFromServer([
        <String, dynamic>{
          'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa99',
          'event_id': eventId,
          'checkpoint_id': checkpointId,
          'instance_start': 'not a date',
          'bib': 'corrupt',
          'recorded_at': DateTime.utc(2026, 6, 14, 7, 5).toIso8601String(),
        },
      ]);
      expect(store.rowsForCheckpoint(eventId, checkpointId, instanceStart),
          isEmpty);
    });
  });

  group('instance_start is pushed as an INSTANT', () {
    test('a stamp taken in a non-UTC zone pushes the UTC instant', () async {
      // The row is stored through `instanceStartKey`, so the on-disk key and
      // the key `pushCreate` sends are the value web writes for the same
      // occurrence — not the reader's wall clock, which Postgres would
      // re-anchor in its own TimeZone.
      final local = DateTime.utc(2026, 6, 14, 7).toLocal();
      final stored = await store.createLocal(
        eventId: eventId,
        checkpointId: checkpointId,
        instanceStart: local,
        bib: '7',
      );
      expect(stored.row['instance_start'], endsWith('Z'));
      expect(
          DateTime.parse(stored.row['instance_start'] as String)
              .isAtSameMomentAs(local),
          isTrue);

      final api = _FakeCrossingsApi();
      await store.syncWithServer(api);
      expect(api.upserts, hasLength(1));
      expect(
          (api.upserts.single['instance_start'] as DateTime)
              .isAtSameMomentAs(local),
          isTrue);
    });

    test('a legacy zone-less stored row still pushes the instant it names',
        () async {
      // A row written before § 1343 carries the writer's bare wall clock.
      // Reading it back recovers the instant that produced it, so the drain
      // files it under the same occurrence a fresh stamp would.
      final local = DateTime.utc(2026, 6, 14, 7).toLocal();
      final stored = StoredCrossing(
        row: <String, dynamic>{
          'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa11',
          'event_id': eventId,
          'checkpoint_id': checkpointId,
          'instance_start': local.toIso8601String(),
          'bib': 'legacy',
          'recorded_at': DateTime.utc(2026, 6, 14, 7, 5).toIso8601String(),
        },
        syncState: CrossingSyncState.pendingCreate,
      );
      File('${dir.path}/${stored.id}.json')
          .writeAsStringSync(jsonEncode(stored.toJson()));
      final reloaded = LocalCrossingsStore();
      await reloaded.init(overrideDirectory: dir);

      final api = _FakeCrossingsApi();
      await reloaded.syncWithServer(api);
      expect(api.upserts, hasLength(1));
      expect(
          (api.upserts.single['instance_start'] as DateTime)
              .isAtSameMomentAs(local),
          isTrue);
    });

    test('a crossing whose stored instance is unreadable is refused, not '
        'filed under a guess', () async {
      final stored = StoredCrossing(
        row: <String, dynamic>{
          'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa22',
          'event_id': eventId,
          'checkpoint_id': checkpointId,
          'instance_start': 'not a date',
          'bib': 'corrupt',
          'recorded_at': DateTime.utc(2026, 6, 14, 7, 5).toIso8601String(),
        },
        syncState: CrossingSyncState.pendingCreate,
      );
      File('${dir.path}/${stored.id}.json')
          .writeAsStringSync(jsonEncode(stored.toJson()));
      final reloaded = LocalCrossingsStore();
      await reloaded.init(overrideDirectory: dir);

      final api = _FakeCrossingsApi();
      expect(await reloaded.syncWithServer(api), 0);
      expect(api.upserts, isEmpty);
      expect(reloaded.rowsById[stored.id]!.syncState,
          CrossingSyncState.pendingCreate);
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

    test('a scoped fetch keeps synced rows for other events, on disk too',
        () async {
      // M3: the only caller fetches ONE (event, instance) pair, but the prune
      // was unscoped — so opening the check-in screen for E2 deleted every
      // stamped row for E1 from memory AND from disk, and offline the
      // volunteer never got them back.
      await store.replaceFromServer([
        {
          'id': 'e1-row',
          'event_id': eventId,
          'checkpoint_id': checkpointId,
          'instance_start': instanceStart.toIso8601String(),
          'bib': '1',
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        },
      ]);
      expect(store.rows.any((r) => r['id'] == 'e1-row'), isTrue);

      await store.replaceFromServer(
        [
          {
            'id': 'e2-row',
            'event_id': 'event-2',
            'checkpoint_id': checkpointId,
            'instance_start': instanceStart.toIso8601String(),
            'bib': '2',
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
        eventId: 'event-2',
        instanceStart: instanceStart,
      );

      expect(store.rows.any((r) => r['id'] == 'e1-row'), isTrue);
      expect(File('${dir.path}/e1-row.json').existsSync(), isTrue);
      expect(store.rows.any((r) => r['id'] == 'e2-row'), isTrue);
    });

    test('an out-of-scope synced row still ages out of retention', () async {
      await store.replaceFromServer([
        {
          'id': 'e1-stale',
          'event_id': eventId,
          'checkpoint_id': checkpointId,
          'instance_start': instanceStart.toIso8601String(),
          'bib': '1',
          'recorded_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 5))
              .toIso8601String(),
        },
      ]);
      // Backdate it past the window without going through the server path.
      final stored = store.debugStored('e1-stale')!;
      await store.persist(StoredCrossing(
        row: {
          ...stored.row,
          'recorded_at': DateTime.now()
              .toUtc()
              .subtract(LocalCrossingsStore.kSyncedRetention +
                  const Duration(days: 1))
              .toIso8601String(),
        },
        syncState: CrossingSyncState.synced,
      ));

      await store.replaceFromServer(
        const [],
        eventId: 'event-2',
        instanceStart: instanceStart,
      );

      expect(store.rows.any((r) => r['id'] == 'e1-stale'), isFalse,
          reason: 'the Art 9 mirror must keep expiring other events');
    });
  });

  group('retention', () {
    Map<String, dynamic> crossing(String id, DateTime recordedAt) => {
          'id': id,
          'event_id': eventId,
          'checkpoint_id': checkpointId,
          'instance_start': instanceStart.toIso8601String(),
          'bib': id,
          'recorded_at': recordedAt.toIso8601String(),
        };

    DateTime ago(Duration d) => DateTime.now().toUtc().subtract(d);

    test('an unsynced crossing is never pruned, however old', () async {
      // A stamp taken offline long ago and never drained: unsent data, the
      // only copy that exists.
      final row = crossing('pending-1', ago(const Duration(days: 400)));
      await store.persist(
        StoredCrossing(row: row, syncState: CrossingSyncState.pendingCreate),
      );

      await store.replaceFromServer([]);

      expect(store.rows.any((r) => r['id'] == 'pending-1'), isTrue);
      expect(store.hasPending, isTrue);
    });

    test('a recent synced crossing survives', () async {
      await store
          .replaceFromServer([crossing('recent', ago(const Duration(days: 7)))]);
      expect(store.rows.any((r) => r['id'] == 'recent'), isTrue);
    });

    test('a synced crossing past the retention window is dropped', () async {
      await store.replaceFromServer([
        crossing('old', ago(LocalCrossingsStore.kSyncedRetention +
            const Duration(days: 1))),
        crossing('fresh', ago(const Duration(days: 1))),
      ]);

      expect(store.rows.any((r) => r['id'] == 'old'), isFalse);
      expect(store.rows.any((r) => r['id'] == 'fresh'), isTrue);
      expect(File('${dir.path}/old.json').existsSync(), isFalse,
          reason: 'the pruned record leaves no file behind');
    });

    test('a synced crossing with an unparseable recorded_at is kept', () async {
      await store.replaceFromServer([
        {
          'id': 'undated',
          'event_id': eventId,
          'checkpoint_id': checkpointId,
          'instance_start': instanceStart.toIso8601String(),
          'bib': 'undated',
          'recorded_at': null,
        },
      ]);
      expect(store.rows.any((r) => r['id'] == 'undated'), isTrue,
          reason: 'an undatable audit record is never assumed old');
    });
  });
}
