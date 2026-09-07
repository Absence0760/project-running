import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'offline_sync_store.dart';

/// Sync state for a single recipe. Alias of the shared [SyncState] so the store
/// tests + screens keep the `RecipeSyncState` name.
typedef RecipeSyncState = SyncState;

/// One ingredient inside a [StoredRecipe], carried inline (a recipe is never
/// partially useful, so the ingredients travel with the parent in one file —
/// same rationale as meal templates / gym routines). Mirrors a
/// `recipe_ingredients` row.
class StoredRecipeIngredient {
  StoredRecipeIngredient({
    required this.itemName,
    this.quantity = 1,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.externalId,
  });

  final String itemName;
  final double quantity;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? externalId;

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        'quantity': quantity,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'external_id': externalId,
      };

  factory StoredRecipeIngredient.fromJson(Map<String, dynamic> json) =>
      StoredRecipeIngredient(
        itemName: json['item_name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
        calories: (json['calories'] as num?)?.toDouble(),
        proteinG: (json['protein_g'] as num?)?.toDouble(),
        carbsG: (json['carbs_g'] as num?)?.toDouble(),
        fatG: (json['fat_g'] as num?)?.toDouble(),
        externalId: json['external_id'] as String?,
      );
}

/// One stored recipe in the [LocalRecipeStore]. Holds the `recipes` row shape
/// plus its ingredients inline, and the sync-state tag. `ingredient_count` is
/// denormalised in the row (client-stamped, non-authoritative — matches the
/// server column).
class StoredRecipe implements SyncEntry {
  StoredRecipe({
    required this.row,
    required this.ingredients,
    required this.syncState,
    DateTime? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.now().toUtc();

  final Map<String, dynamic> row;
  final List<StoredRecipeIngredient> ingredients;
  @override
  final SyncState syncState;
  @override
  final DateTime lastModifiedAt;

  @override
  String get id => row['id'] as String;
  @override
  bool get isTombstone => syncState == SyncState.pendingDelete;

  String get name => (row['name'] as String?) ?? '';
  double get servings => (row['servings'] as num?)?.toDouble() ?? 1;
  String? get mealSlot => row['meal_slot'] as String?;
  int get ingredientCount => (row['ingredient_count'] as num?)?.toInt() ?? 0;

  @override
  Map<String, dynamic> toJson() => {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'row': row,
        'ingredients': [for (final it in ingredients) it.toJson()],
        'sync_state': syncState.wire,
        'last_modified_at': lastModifiedAt.toIso8601String(),
      };

  factory StoredRecipe.fromJson(Map<String, dynamic> json) => StoredRecipe(
        row: Map<String, dynamic>.from(json['row'] as Map),
        ingredients: ((json['ingredients'] as List?) ?? const [])
            .map((it) => StoredRecipeIngredient.fromJson(
                Map<String, dynamic>.from(it as Map)))
            .toList(),
        syncState: syncStateFromWire(json['sync_state'] as String?),
        lastModifiedAt: storedClockOrEpoch(json['last_modified_at']),
      );
}

/// Disk-backed store for the user's recipes (multi_modal.md Nutrition mid
/// tier). Sibling of [LocalMealTemplateStore]: one JSON file per recipe under
/// `<appDocs>/recipes/`, with the recipe's ingredients carried **inline** (a
/// recipe is never partially useful). In-memory `ChangeNotifier` so the
/// nutrition surfaces refresh on every mutation; sync drained on demand.
///
/// Offline contract:
/// - `createLocal` mints a v4 UUID (the client value becomes the server id —
///   `recipes.id` accepts a client value, so no temp-id reconciliation), marks
///   the recipe pendingCreate, and stores its ingredients inline.
/// - `deleteLocal` on a synced recipe writes a tombstone; on a recipe that was
///   only ever local (pendingCreate) it just drops the file.
/// - `syncWithServer(api)` drains every non-synced recipe in create → delete
///   order. There is no edit path (build / save / delete only, mirroring web).
class LocalRecipeStore extends OfflineSyncStore<StoredRecipe> {
  @override
  String get storeSubdir => 'recipes';

  @override
  String get debugLabel => 'local_recipe_store';

  @override
  StoredRecipe entryFromJson(Map<String, dynamic> json) =>
      StoredRecipe.fromJson(json);

  @override
  String? get summaryTimestampKey => 'last_modified_at';

  @override
  Map<String, dynamic> summaryOf(StoredRecipe entry) => {
        'id': entry.id,
        'sync_state': entry.syncState.wire,
        'last_modified_at': entry.row['last_modified_at'],
        'name': entry.row['name'],
        'ingredient_count': entry.ingredientCount,
      };

  @override
  StoredRecipe asSynced(StoredRecipe entry) => StoredRecipe(
        row: entry.row,
        ingredients: entry.ingredients,
        syncState: SyncState.synced,
        lastModifiedAt: entry.lastModifiedAt,
      );

  @override
  StoredRecipe asPendingCreate(StoredRecipe entry) => StoredRecipe(
        row: entry.row,
        ingredients: entry.ingredients,
        syncState: SyncState.pendingCreate,
        lastModifiedAt: entry.lastModifiedAt,
      );

  /// Live recipes (excludes tombstones), most-recently-modified first — the
  /// list order, matching web `fetchRecipes`.
  List<StoredRecipe> get recipes {
    final live = rowsById.values.where((r) => !r.isTombstone).toList();
    live.sort((a, b) => b.lastModifiedAt.compareTo(a.lastModifiedAt));
    return live;
  }

  /// A single live recipe by id, or null if missing / a tombstone.
  StoredRecipe? byId(String id) {
    final r = rowsById[id];
    return (r == null || r.isTombstone) ? null : r;
  }

  /// Mint a new UUID and persist a pending-create recipe. Blank-named
  /// ingredients are dropped (mirroring web `createRecipe`). Returns the stored
  /// shape so the caller can render it immediately.
  Future<StoredRecipe> createLocal({
    required String name,
    double servings = 1,
    String? mealSlot,
    List<StoredRecipeIngredient> ingredients = const [],
  }) async {
    final id = OfflineSyncStore.newUuid();
    final now = DateTime.now().toUtc();
    final kept = ingredients
        .where((it) => it.itemName.trim().isNotEmpty)
        .toList(growable: false);
    final row = <String, dynamic>{
      'id': id,
      'name': name.trim(),
      'servings': servings >= 1 ? servings : 1,
      'meal_slot': mealSlot,
      'ingredient_count': kept.length,
      'external_id': null,
      'last_modified_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    };
    final stored = StoredRecipe(
      row: row,
      ingredients: kept,
      syncState: SyncState.pendingCreate,
      lastModifiedAt: now,
    );
    await persist(stored);
    return stored;
  }

  /// Delete a recipe. A recipe that was only ever local (pendingCreate)
  /// disappears immediately; a synced recipe becomes a pendingDelete tombstone
  /// so the next sync issues the server DELETE (which cascades the
  /// ingredients). Logged food_log entries are untouched.
  Future<void> deleteLocal(String id) async {
    final existing = rowsById[id];
    if (existing == null) return;
    if (existing.syncState == SyncState.pendingCreate) {
      await dropRow(id);
      return;
    }
    final tombstone = StoredRecipe(
      row: existing.row,
      ingredients: existing.ingredients,
      syncState: SyncState.pendingDelete,
    );
    await persist(tombstone);
  }

  /// Replace the in-memory state from a fresh server fetch (each recipe with
  /// its ingredients). Pending-* recipes are preserved — only `synced` rows are
  /// overwritten so an offline create / delete isn't clobbered by the server's
  /// copy. Newer-wins on the synced copies, mirroring
  /// [LocalMealTemplateStore.replaceFromServer].
  Future<void> replaceFromServer(
    List<({Map<String, dynamic> recipe, List<StoredRecipeIngredient> ingredients})>
        serverRecipes,
  ) async {
    requireInitialised('replaceFromServer');
    final preserved = <String, StoredRecipe>{};
    final syncedLocal = <String, StoredRecipe>{};
    for (final entry in rowsById.entries) {
      if (entry.value.syncState != SyncState.synced) {
        preserved[entry.key] = entry.value;
      } else {
        syncedLocal[entry.key] = entry.value;
      }
    }
    rowsById.clear();
    for (final r in serverRecipes) {
      final id = r.recipe['id'] as String;
      if (preserved.containsKey(id)) {
        rowsById[id] = preserved.remove(id)!;
        continue;
      }
      final local = syncedLocal[id];
      final serverTs = parseServerTimestamp(r.recipe['last_modified_at']);
      if (local != null &&
          serverTs != null &&
          local.lastModifiedAt.isAfter(serverTs)) {
        rowsById[id] = local;
      } else {
        rowsById[id] = StoredRecipe(
          row: r.recipe,
          ingredients: r.ingredients,
          syncState: SyncState.synced,
          lastModifiedAt: serverTs,
        );
      }
    }
    rowsById.addAll(preserved);
    await rewriteAll();
    notifyListeners();
  }

  @override
  Future<void> pushCreate(ApiClient api, StoredRecipe stored) =>
      api.createRecipe(
        id: stored.id,
        name: stored.name,
        servings: stored.servings,
        mealSlot: stored.mealSlot,
        lastModifiedAt: stored.lastModifiedAt,
        ingredients: _ingredientsToInput(stored.ingredients),
      );

  // There is no edit path (build / save / delete only), so a recipe never
  // reaches pendingUpdate — but the base class requires the hook. Recreate to
  // stay correct if a future edit path ever flips the state.
  @override
  Future<void> pushUpdate(ApiClient api, StoredRecipe stored) async {
    await api.deleteRecipe(stored.id);
    await api.createRecipe(
      id: stored.id,
      name: stored.name,
      servings: stored.servings,
      mealSlot: stored.mealSlot,
      lastModifiedAt: stored.lastModifiedAt,
      ingredients: _ingredientsToInput(stored.ingredients),
    );
  }

  @override
  Future<void> pushDelete(ApiClient api, StoredRecipe stored) =>
      api.deleteRecipe(stored.id);

  static List<RecipeIngredientInput> _ingredientsToInput(
          List<StoredRecipeIngredient> ingredients) =>
      [
        for (final it in ingredients)
          (
            itemName: it.itemName,
            quantity: it.quantity,
            calories: it.calories,
            proteinG: it.proteinG,
            carbsG: it.carbsG,
            fatG: it.fatG,
            externalId: it.externalId,
          ),
      ];
}
