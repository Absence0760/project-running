import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_session_store.dart';

Future<({LocalSessionStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('session_store_$tag');
  final store = LocalSessionStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

StoredSessionItem _item(String id,
        {int position = 0,
        String name = 'Pose',
        String kind = 'hold',
        int? durationS = 30,
        int? reps,
        bool perSide = false,
        String? cue}) =>
    StoredSessionItem(
      id: id,
      position: position,
      movementName: name,
      kind: kind,
      durationS: durationS,
      reps: reps,
      perSide: perSide,
      cue: cue,
    );

StoredSessionBlock _block(String id,
        {int position = 0, String? name, List<StoredSessionItem>? items}) =>
    StoredSessionBlock(
      id: id,
      position: position,
      name: name,
      items: items ?? [_item('$id-i0')],
    );

void main() {
  test('createLocal mints a v4 UUID + marks pendingCreate', () async {
    final f = await _store('create');
    try {
      final p = await f.store.createLocal(
        title: 'Morning Flow',
        discipline: 'Vinyasa',
        estDurationMin: 30,
        blocks: [_block('b0')],
      );
      expect(p.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(p.syncState, SessionSyncState.pendingCreate);
      expect(p.discipline, 'Vinyasa');
      expect(p.estDurationMin, 30);
      expect(f.store.plans, hasLength(1));
      expect(f.store.hasPending, isTrue);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('plans reload from disk + sort most-recently-modified first + children round-trip',
      () async {
    final f = await _store('reload');
    try {
      final a = await f.store.createLocal(
        title: 'A',
        blocks: [
          _block('a-b0', name: 'Warmup', items: [
            _item('a-i0', name: 'Cat-Cow', perSide: true, cue: 'Breathe'),
          ]),
        ],
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = await f.store.createLocal(title: 'B', blocks: [_block('b-b0')]);
      final reopened = LocalSessionStore();
      await reopened.init(overrideDirectory: f.dir);
      expect(reopened.plans.map((p) => p.id), [b.id, a.id]);
      // Inline blocks + items survive the round-trip.
      final ra = reopened.byId(a.id)!;
      expect(ra.blocks.single.name, 'Warmup');
      final item = ra.blocks.single.items.single;
      expect(item.movementName, 'Cat-Cow');
      expect(item.perSide, isTrue);
      expect(item.cue, 'Breathe');
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('deleteLocal on a pendingCreate plan drops it outright', () async {
    final f = await _store('delete_local');
    try {
      final p = await f.store.createLocal(title: 'X', blocks: [_block('x-b0')]);
      await f.store.deleteLocal(p.id);
      expect(f.store.byId(p.id), isNull);
      expect(f.store.plans, isEmpty);
      expect(f.store.hasPending, isFalse);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('deleteLocal on a synced plan writes a pendingDelete tombstone',
      () async {
    final f = await _store('delete_synced');
    try {
      await f.store.replaceFromServer([
        (
          plan: <String, dynamic>{
            'id': 's-1',
            'title': 'Synced',
            'updated_at': DateTime.utc(2026, 5, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 5, 1).toIso8601String(),
          },
          blocks: [_block('s-b0')],
        ),
      ]);
      expect(f.store.byId('s-1')!.syncState, SessionSyncState.synced);
      await f.store.deleteLocal('s-1');
      // Hidden from the live list, but a tombstone remains for the drain.
      expect(f.store.byId('s-1'), isNull);
      expect(f.store.hasPending, isTrue);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('replaceFromServer preserves a local pendingCreate', () async {
    final f = await _store('preserve_pending');
    try {
      final pending =
          await f.store.createLocal(title: 'Local', blocks: [_block('l-b0')]);
      await f.store.replaceFromServer([
        (
          plan: <String, dynamic>{
            'id': 's-server',
            'title': 'Server',
            'updated_at': DateTime.utc(2026, 4, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 4, 1).toIso8601String(),
          },
          blocks: [_block('srv-b0')],
        ),
      ]);
      expect(f.store.byId(pending.id), isNotNull,
          reason: 'pendingCreate preserved across replaceFromServer');
      expect(f.store.byId('s-server'), isNotNull);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('replaceFromServer is newer-wins on a synced copy', () async {
    final f = await _store('newer_wins');
    try {
      // Seed a synced plan dated old.
      await f.store.replaceFromServer([
        (
          plan: <String, dynamic>{
            'id': 's-1',
            'title': 'Old',
            'updated_at': DateTime.utc(2026, 3, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 3, 1).toIso8601String(),
          },
          blocks: [_block('s-b0')],
        ),
      ]);
      final local = f.store.byId('s-1')!;
      await f.store.replaceFromServer([
        (
          plan: <String, dynamic>{
            'id': 's-1',
            'title': 'Newer server',
            'updated_at': DateTime.utc(2026, 5, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 3, 1).toIso8601String(),
          },
          blocks: [_block('s-b0')],
        ),
      ]);
      // A strictly-newer server fetch overwrites the stale local synced copy.
      expect(f.store.byId('s-1')!.title, 'Newer server');
      expect(local.title, 'Old');
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('drain pushes pending create then delete in order', () async {
    final f = await _store('drain');
    try {
      // A pendingCreate (build/save) and a synced-then-deleted tombstone.
      await f.store.createLocal(title: 'New', blocks: [_block('n-b0')]);
      await f.store.replaceFromServer([
        (
          plan: <String, dynamic>{
            'id': 'del-1',
            'title': 'ToDelete',
            'updated_at': DateTime.utc(2026, 2, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 2, 1).toIso8601String(),
          },
          blocks: [_block('del-b0')],
        ),
      ]);
      await f.store.deleteLocal('del-1');
      final api = _RecordingApi();
      final drained = await f.store.syncWithServer(api);
      expect(drained, 2);
      expect(api.created, hasLength(1));
      expect(api.deleted, ['del-1']);
      // After a clean drain nothing is pending.
      expect(f.store.hasPending, isFalse);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}

class _RecordingApi extends ApiClient {
  final List<String> created = [];
  final List<String> deleted = [];

  @override
  Future<SessionPlanRow> createSessionPlan({
    String? id,
    required String title,
    String? discipline,
    String? equipment,
    int? estDurationMin,
    bool isPublic = false,
    DateTime? updatedAt,
    List<SessionPlanBlockInput> blocks = const [],
    List<SessionPlanItemInput> items = const [],
  }) async {
    created.add(id ?? 'server-generated');
    final now = DateTime.now().toUtc();
    return SessionPlanRow(
      id: id ?? 'server-generated',
      authorId: 'test-user',
      title: title,
      discipline: discipline,
      equipment: equipment,
      estDurationMin: estDurationMin,
      isPublic: isPublic,
      createdAt: now,
      updatedAt: updatedAt ?? now,
    );
  }

  @override
  Future<void> deleteSessionPlan(String id) async => deleted.add(id);
}
