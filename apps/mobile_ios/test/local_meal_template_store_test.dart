import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/local_meal_template_store.dart';

Future<({LocalMealTemplateStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('meal_template_store_$tag');
  final store = LocalMealTemplateStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

StoredMealTemplateItem _item(String name, {double? calories, String? slot}) =>
    StoredMealTemplateItem(itemName: name, calories: calories, mealSlot: slot);

void main() {
  test('createLocal mints a v4 UUID + marks pendingCreate, drops blanks',
      () async {
    final f = await _store('create');
    try {
      final t = await f.store.createLocal(
        name: 'Pre-run breakfast',
        mealSlot: 'breakfast',
        items: [_item('Oats', calories: 300), _item('  '), _item('Banana')],
      );
      expect(t.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(t.syncState, MealTemplateSyncState.pendingCreate);
      expect(t.items, hasLength(2));
      expect(t.itemCount, 2);
      expect(t.mealSlot, 'breakfast');
      expect(f.store.templates, hasLength(1));
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('templates reload from disk + sort most-recently-modified first',
      () async {
    final f = await _store('reload');
    try {
      final a = await f.store.createLocal(name: 'A', items: [_item('Oats')]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = await f.store.createLocal(name: 'B', items: [_item('Rice')]);
      final reopened = LocalMealTemplateStore();
      await reopened.init(overrideDirectory: f.dir);
      expect(reopened.templates.map((t) => t.id), [b.id, a.id]);
      expect(reopened.byId(a.id)!.items.single.itemName, 'Oats');
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('item macros + slot round-trip on disk', () async {
    final f = await _store('roundtrip');
    try {
      final t = await f.store.createLocal(name: 'Lunch', items: [
        StoredMealTemplateItem(
          itemName: 'Chicken bowl',
          mealSlot: 'lunch',
          calories: 640,
          proteinG: 48,
          carbsG: 52,
          fatG: 18,
          externalId: 'off:123',
        ),
      ]);
      final reopened = LocalMealTemplateStore();
      await reopened.init(overrideDirectory: f.dir);
      final it = reopened.byId(t.id)!.items.single;
      expect(it.mealSlot, 'lunch');
      expect(it.calories, 640);
      expect(it.proteinG, 48);
      expect(it.externalId, 'off:123');
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('deleteLocal on a pendingCreate template drops it outright', () async {
    final f = await _store('delete_local');
    try {
      final t = await f.store.createLocal(name: 'X', items: [_item('Egg')]);
      await f.store.deleteLocal(t.id);
      expect(f.store.byId(t.id), isNull);
      expect(f.store.templates, isEmpty);
      expect(f.store.hasPending, isFalse);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('deleteLocal on a synced template writes a pendingDelete tombstone',
      () async {
    final f = await _store('delete_synced');
    try {
      await f.store.replaceFromServer([
        (
          template: <String, dynamic>{
            'id': 't-1',
            'name': 'Synced',
            'item_count': 1,
            'last_modified_at': DateTime.utc(2026, 5, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 5, 1).toIso8601String(),
          },
          items: [_item('Yogurt')],
        ),
      ]);
      expect(f.store.byId('t-1')!.syncState, MealTemplateSyncState.synced);
      await f.store.deleteLocal('t-1');
      expect(f.store.byId('t-1'), isNull);
      expect(f.store.hasPending, isTrue);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('replaceFromServer preserves a local pendingCreate', () async {
    final f = await _store('newer_wins');
    try {
      final pending =
          await f.store.createLocal(name: 'Local', items: [_item('Toast')]);
      await f.store.replaceFromServer([
        (
          template: <String, dynamic>{
            'id': 't-server',
            'name': 'Server',
            'item_count': 1,
            'last_modified_at': DateTime.utc(2026, 4, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 4, 1).toIso8601String(),
          },
          items: [_item('Apple')],
        ),
      ]);
      expect(f.store.byId(pending.id), isNotNull,
          reason: 'pendingCreate preserved across replaceFromServer');
      expect(f.store.byId('t-server'), isNotNull);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
