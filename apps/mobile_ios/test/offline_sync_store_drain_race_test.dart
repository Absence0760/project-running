// Two things `OfflineSyncStore` does between a network push and the disk it
// writes back to, neither of which any suite could see.
//
// The drain snapshots a row, awaits a network push, then marks it synced —
// and `markSynced` guards that with an identity test, because an edit made
// during the push must be left pending rather than recorded as sent. But the
// test ran OUTSIDE the write chain, and `persist` only QUEUES: a write already
// queued and not yet run still let the check pass, and the pre-edit copy then
// landed on top of it marked `synced`. That is the exact loss the guard exists
// to prevent, moved one step later — and permanent, because a `synced` row is
// never pushed again and `replaceFromServer`'s newer-wins keeps the local
// copy. `LocalRunStore.markManySynced` had the check inside the chain; the
// base class did not, and the asymmetry was the tell.
//
// A queued-but-not-yet-run write is not exotic: the drain's own `markSynced`
// for the previous row occupies the chain for a real disk write, so any store
// draining more than one row reaches it. These tests hold the chain open
// explicitly, which is the same state with a deterministic clock.
//
// The second is `rewriteAll`'s prune: it deletes a row's file without evicting
// the row's cached encoding, so when the server hands the same row back
// byte-identically the diff-skip believes it is already on disk and writes
// nothing. The row renders normally and is gone at the next cold load.
//
// The two stores here stand in for every subclass — all of this lives in the
// base. Food is the vehicle for the prune case because it builds a synced
// row's clock from the SERVER's `last_modified_at`, so two identical fetches
// really do encode identically and the diff-skip really does fire.

import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_food_store.dart';
import '../lib/local_gear_store.dart';
import '../lib/offline_sync_store.dart';

/// Holds each push open until the test releases it, so a mutation can be
/// queued at the one instant the drain is mid-flight.
class _GatedGearApi extends ApiClient {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  Future<void> _gate() async {
    if (!started.isCompleted) started.complete();
    await release.future;
  }

  @override
  Future<GearRow> createGear({
    required String kind,
    required String name,
    String? id,
    String? brand,
    String? model,
    DateTime? purchasedAt,
    int? targetDistanceM,
    String? notes,
  }) async {
    await _gate();
    return GearRow(
      id: id ?? 'server',
      ownerId: 'test-user',
      kind: kind,
      name: name,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDefault: false,
    );
  }

  @override
  Future<void> updateGear(
    String id, {
    String? name,
    String? brand,
    String? model,
    DateTime? purchasedAt,
    DateTime? retiredAt,
    bool clearRetiredAt = false,
    int? targetDistanceM,
    String? notes,
  }) async {
    await _gate();
  }

  @override
  Future<void> deleteGear(String id) async {
    await _gate();
  }
}

Map<String, dynamic> _gearRow(String id, String name) => <String, dynamic>{
      'id': id,
      'owner_id': 'test-user',
      'kind': 'shoes',
      'name': name,
      'brand': null,
      'model': null,
      'purchased_at': null,
      'retired_at': null,
      'target_distance_m': null,
      'notes': null,
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
      'total_distance_m': 0,
      'is_default': false,
    };

Map<String, dynamic> _foodRow(String id, String itemName) => <String, dynamic>{
      'id': id,
      'started_at': DateTime.utc(2026, 6, 1, 12).toIso8601String(),
      'item_name': itemName,
      'meal_slot': null,
      'calories': null,
      'protein_g': null,
      'carbs_g': null,
      'fat_g': null,
      'is_public': false,
      'external_id': null,
      'last_modified_at': DateTime.utc(2026, 6, 1).toIso8601String(),
      'created_at': DateTime.utc(2026, 6, 1).toIso8601String(),
    };

void main() {
  group('an edit queued while the drain is pushing', () {
    late Directory dir;
    late LocalGearStore store;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('drain_race');
      store = LocalGearStore();
      await store.init(overrideDirectory: dir);
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    /// Run [action] against a store whose write chain is already occupied, so
    /// its body is still QUEUED when the drain's push resolves — the state
    /// the drain itself leaves the chain in between rows, because the previous
    /// row's own mark is a real disk write. Then release the push, let the
    /// mark run its identity check against that queued edit, and only then let
    /// the chain drain.
    Future<void> editDuringPush(
      _GatedGearApi api,
      Future<int> drain,
      void Function() action,
    ) async {
      final gate = Completer<void>();
      final held = serialiseStoreWrite(dir.path, () => gate.future);
      action();
      api.release.complete();
      // Hand the real event loop enough turns for the push to resolve and the
      // mark to make its decision. The mark's own write is queued behind the
      // gate, so the drain cannot finish here however many turns it gets.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      gate.complete();
      await held;
      await drain;
      await store.debugWritesSettled();
    }

    test('is not overwritten by the mark that follows the push', () async {
      await store.replaceFromServer([_gearRow('g1', 'Pegasus')]);
      await store.updateLocal('g1', {'name': 'Pegasus 40'});

      final api = _GatedGearApi();
      final drain = store.syncWithServer(api);
      await api.started.future;

      // The screen's own edit, queued while the chain is busy — which is
      // where `markSynced`'s check used to look straight past it.
      await editDuringPush(
          api, drain, () => store.updateLocal('g1', {'name': 'Pegasus 41'}));

      expect(store.debugStored('g1')!.row['name'], 'Pegasus 41',
          reason: "the runner's edit was overwritten by the pre-push copy");
      expect(store.debugStored('g1')!.syncState, isNot(SyncState.synced),
          reason: 'an edit the server has never seen must stay pending, or it '
              'is never pushed and the divergence is permanent');
    });

    test('survives a reload, so disk agrees with what the screen shows',
        () async {
      await store.replaceFromServer([_gearRow('g1', 'Pegasus')]);
      await store.updateLocal('g1', {'name': 'Pegasus 40'});

      final api = _GatedGearApi();
      final drain = store.syncWithServer(api);
      await api.started.future;

      await editDuringPush(
          api, drain, () => store.updateLocal('g1', {'name': 'Pegasus 41'}));

      final reloaded = LocalGearStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.debugStored('g1')!.row['name'], 'Pegasus 41');
    });

    test('a re-create during a delete push is not dropped with the tombstone',
        () async {
      // The same shape one branch over: the drain identity-tests the
      // tombstone and then calls `dropRow`, which also only queues.
      await store.replaceFromServer([_gearRow('g1', 'Pegasus')]);
      await store.deleteLocal('g1');
      expect(store.debugStored('g1')!.syncState, SyncState.pendingDelete);

      final api = _GatedGearApi();
      final drain = store.syncWithServer(api);
      await api.started.future;

      await editDuringPush(api, drain,
          () => store.updateLocal('g1', {'name': 'Pegasus revived'}));

      expect(store.debugStored('g1'), isNotNull,
          reason: 'a row re-created during its own delete push has never been '
              'sent — dropping it loses a row the runner is looking at');
      expect(store.debugStored('g1')!.row['name'], 'Pegasus revived');
    });

    test('and a row nobody touched is still marked synced', () async {
      // The negative shape. Without it the fix could be "never mark", which
      // leaves every drained row pending and re-pushes it forever.
      await store.replaceFromServer([_gearRow('g1', 'Pegasus')]);
      await store.updateLocal('g1', {'name': 'Pegasus 40'});

      final api = _GatedGearApi();
      final drain = store.syncWithServer(api);
      await api.started.future;
      api.release.complete();
      expect(await drain, 1);
      await store.debugWritesSettled();

      expect(store.debugStored('g1')!.syncState, SyncState.synced);
      expect(store.hasPending, isFalse);
    });
  });

  group('rewriteAll', () {
    late Directory dir;
    late LocalFoodStore store;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('rewrite_prune');
      store = LocalFoodStore();
      await store.init(overrideDirectory: dir);
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('re-writes a row whose file its own prune removed', () async {
      // The server omits B for one refresh — a filtered fetch, a transient
      // partial page — then hands it back unchanged. Its encoding never
      // changed, so the diff-skip believed the file was still there.
      await store.replaceFromServer([
        _foodRow('a', 'Porridge'),
        _foodRow('b', 'Banana'),
      ]);
      expect(File('${dir.path}/b.json').existsSync(), isTrue);

      await store.replaceFromServer([_foodRow('a', 'Porridge')]);
      expect(File('${dir.path}/b.json').existsSync(), isFalse);

      await store.replaceFromServer([
        _foodRow('a', 'Porridge'),
        _foodRow('b', 'Banana'),
      ]);

      expect(File('${dir.path}/b.json').existsSync(), isTrue,
          reason: 'the row is resident and rendered, but nothing wrote it — '
              'it disappears at the next cold load');

      final reloaded = LocalFoodStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rowsById.keys.toSet(), {'a', 'b'});
    });

    test('still skips the write when the row really is on disk unchanged',
        () async {
      // The other half: without it the fix could be "always write", which
      // turns every pull-to-refresh back into N forced fsyncs (§ the
      // write-amplification skip this counter exists for).
      await store.replaceFromServer([_foodRow('a', 'Porridge')]);
      final before = store.rewriteAtomicWrites;
      await store.replaceFromServer([_foodRow('a', 'Porridge')]);

      expect(store.rewriteAtomicWrites, before,
          reason: 'an unchanged refresh must not rewrite anything');
    });
  });

  // `_loadAll` deliberately writes no index for a store that is both empty and
  // has none on disk. The two production reasons are its own — nothing to
  // cache, no write on every cold-load of a store the user never opens — and
  // BOTH claims are asserted here, because neither had a test.
  //
  // The third reason its comment gives is the one measured in § 1196:
  // `_readIndex` short-circuits on a missing file, so the index write would be
  // the only real-async await a fresh empty store's `init()` carries, and a
  // widget test that inits one outside `tester.runAsync` would never see it
  // complete. That is why the first case here is a `testWidgets` pumping the
  // fake clock rather than a plain `test` — a plain one would await the real
  // event loop and pass either way, proving nothing.
  group('a fresh empty store loads without writing an index', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('empty_load'));
    tearDown(() => dir.deleteSync(recursive: true));

    testWidgets('init() completes under fake-async pumping alone',
        (tester) async {
      var loaded = false;
      unawaited(LocalFoodStore()
          .init(overrideDirectory: dir)
          .then((_) => loaded = true));
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 20 && !loaded; i++) {
        await tester.pump();
      }

      expect(loaded, isTrue,
          reason: 'a fresh empty store\'s init() must carry no real-async '
              'await, or every widget test that inits one outside '
              'tester.runAsync hangs to the runner timeout');
    });

    test('writes no index file, and writes one as soon as a row exists',
        () async {
      final store = LocalFoodStore();
      await store.init(overrideDirectory: dir);
      final index = File('${dir.path}/index.json');

      expect(index.existsSync(), isFalse,
          reason: 'there is nothing to cache and no index to correct');

      await store.createLocal(itemName: 'Porridge', startedAt: DateTime.now());
      expect(index.existsSync(), isTrue,
          reason: 'the skip is for an empty store, not a standing refusal');
    });

    test('a drifted index on disk is still corrected when the store is empty',
        () async {
      final index = File('${dir.path}/index.json');
      index.writeAsStringSync('{"summaries": [{"id": "ghost"}]}');

      await LocalFoodStore().init(overrideDirectory: dir);

      expect(index.readAsStringSync(), isNot(contains('ghost')),
          reason: 'the skip is conditioned on there being no index to '
              'correct, so one naming a row the store does not hold must '
              'still be rewritten');
    });
  });
}
