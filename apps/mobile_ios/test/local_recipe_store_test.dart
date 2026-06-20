import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/local_recipe_store.dart';

Future<({LocalRecipeStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('recipe_store_$tag');
  final store = LocalRecipeStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

StoredRecipeIngredient _ing(String name, {double? calories, double quantity = 1}) =>
    StoredRecipeIngredient(itemName: name, calories: calories, quantity: quantity);

void main() {
  test('createLocal mints a v4 UUID + marks pendingCreate, drops blanks',
      () async {
    final f = await _store('create');
    try {
      final r = await f.store.createLocal(
        name: 'Chilli',
        servings: 4,
        mealSlot: 'dinner',
        ingredients: [_ing('Beans', calories: 300), _ing('  '), _ing('Mince')],
      );
      expect(r.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(r.syncState, RecipeSyncState.pendingCreate);
      expect(r.ingredients, hasLength(2));
      expect(r.ingredientCount, 2);
      expect(r.servings, 4);
      expect(r.mealSlot, 'dinner');
      expect(f.store.recipes, hasLength(1));
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('createLocal clamps servings below 1 to 1', () async {
    final f = await _store('servings_clamp');
    try {
      final r = await f.store.createLocal(name: 'X', servings: 0, ingredients: [_ing('Egg')]);
      expect(r.servings, 1);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('recipes reload from disk + sort most-recently-modified first', () async {
    final f = await _store('reload');
    try {
      final a = await f.store.createLocal(name: 'A', ingredients: [_ing('Beans')]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = await f.store.createLocal(name: 'B', ingredients: [_ing('Rice')]);
      final reopened = LocalRecipeStore();
      await reopened.init(overrideDirectory: f.dir);
      expect(reopened.recipes.map((r) => r.id), [b.id, a.id]);
      expect(reopened.byId(a.id)!.ingredients.single.itemName, 'Beans');
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('ingredient macros + quantity round-trip on disk', () async {
    final f = await _store('roundtrip');
    try {
      final r = await f.store.createLocal(name: 'Stew', servings: 2, ingredients: [
        StoredRecipeIngredient(
          itemName: 'Mince',
          quantity: 3,
          calories: 640,
          proteinG: 48,
          carbsG: 52,
          fatG: 18,
          externalId: 'off:123',
        ),
      ]);
      final reopened = LocalRecipeStore();
      await reopened.init(overrideDirectory: f.dir);
      final it = reopened.byId(r.id)!.ingredients.single;
      expect(it.quantity, 3);
      expect(it.calories, 640);
      expect(it.proteinG, 48);
      expect(it.externalId, 'off:123');
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('deleteLocal on a pendingCreate recipe drops it outright', () async {
    final f = await _store('delete_local');
    try {
      final r = await f.store.createLocal(name: 'X', ingredients: [_ing('Egg')]);
      await f.store.deleteLocal(r.id);
      expect(f.store.byId(r.id), isNull);
      expect(f.store.recipes, isEmpty);
      expect(f.store.hasPending, isFalse);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('deleteLocal on a synced recipe writes a pendingDelete tombstone',
      () async {
    final f = await _store('delete_synced');
    try {
      await f.store.replaceFromServer([
        (
          recipe: <String, dynamic>{
            'id': 'r-1',
            'name': 'Synced',
            'servings': 2,
            'ingredient_count': 1,
            'last_modified_at': DateTime.utc(2026, 5, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 5, 1).toIso8601String(),
          },
          ingredients: [_ing('Yogurt')],
        ),
      ]);
      expect(f.store.byId('r-1')!.syncState, RecipeSyncState.synced);
      await f.store.deleteLocal('r-1');
      expect(f.store.byId('r-1'), isNull);
      expect(f.store.hasPending, isTrue);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('replaceFromServer preserves a local pendingCreate', () async {
    final f = await _store('newer_wins');
    try {
      final pending =
          await f.store.createLocal(name: 'Local', ingredients: [_ing('Toast')]);
      await f.store.replaceFromServer([
        (
          recipe: <String, dynamic>{
            'id': 'r-server',
            'name': 'Server',
            'servings': 1,
            'ingredient_count': 1,
            'last_modified_at': DateTime.utc(2026, 4, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 4, 1).toIso8601String(),
          },
          ingredients: [_ing('Apple')],
        ),
      ]);
      expect(f.store.byId(pending.id), isNotNull,
          reason: 'pendingCreate preserved across replaceFromServer');
      expect(f.store.byId('r-server'), isNotNull);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
