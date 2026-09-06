import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'offline_sync_store.dart';

/// Sync state for a single meal template. Alias of the shared [SyncState] so
/// the store tests + screens keep the `MealTemplateSyncState` name.
typedef MealTemplateSyncState = SyncState;

/// One food item inside a [StoredMealTemplate], carried inline (a template is
/// never partially useful, so the items travel with the parent in one file —
/// same rationale as gym routines). Mirrors a `meal_template_items` row.
class StoredMealTemplateItem {
  StoredMealTemplateItem({
    required this.itemName,
    this.mealSlot,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.externalId,
  });

  final String itemName;
  final String? mealSlot;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? externalId;

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        'meal_slot': mealSlot,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'external_id': externalId,
      };

  factory StoredMealTemplateItem.fromJson(Map<String, dynamic> json) =>
      StoredMealTemplateItem(
        itemName: json['item_name'] as String? ?? '',
        mealSlot: json['meal_slot'] as String?,
        calories: (json['calories'] as num?)?.toDouble(),
        proteinG: (json['protein_g'] as num?)?.toDouble(),
        carbsG: (json['carbs_g'] as num?)?.toDouble(),
        fatG: (json['fat_g'] as num?)?.toDouble(),
        externalId: json['external_id'] as String?,
      );
}

/// One stored meal template in the [LocalMealTemplateStore]. Holds the
/// `meal_templates` row shape plus its items inline, and the sync-state tag.
/// `item_count` is denormalised in the row (client-stamped, non-authoritative
/// — matches the server column).
class StoredMealTemplate implements SyncEntry {
  StoredMealTemplate({
    required this.row,
    required this.items,
    required this.syncState,
    DateTime? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.now().toUtc();

  final Map<String, dynamic> row;
  final List<StoredMealTemplateItem> items;
  @override
  final SyncState syncState;
  @override
  final DateTime lastModifiedAt;

  @override
  String get id => row['id'] as String;
  @override
  bool get isTombstone => syncState == SyncState.pendingDelete;

  String get name => (row['name'] as String?) ?? '';
  String? get mealSlot => row['meal_slot'] as String?;
  int get itemCount => (row['item_count'] as num?)?.toInt() ?? 0;

  @override
  Map<String, dynamic> toJson() => {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'row': row,
        'items': [for (final it in items) it.toJson()],
        'sync_state': syncState.wire,
        'last_modified_at': lastModifiedAt.toIso8601String(),
      };

  factory StoredMealTemplate.fromJson(Map<String, dynamic> json) =>
      StoredMealTemplate(
        row: Map<String, dynamic>.from(json['row'] as Map),
        items: ((json['items'] as List?) ?? const [])
            .map((it) =>
                StoredMealTemplateItem.fromJson(Map<String, dynamic>.from(it as Map)))
            .toList(),
        syncState: syncStateFromWire(json['sync_state'] as String?),
        lastModifiedAt: storedClockOrNow(json['last_modified_at']),
      );
}

/// Disk-backed store for the user's meal templates (multi_modal.md Nutrition
/// mid tier). Sibling of [LocalRoutineStore] / [LocalFoodStore]: one JSON file
/// per template under `<appDocs>/meal_templates/`, with the template's items
/// carried **inline** (a template is never partially useful). In-memory
/// `ChangeNotifier` so the nutrition surfaces refresh on every mutation; sync
/// drained on demand.
///
/// Offline contract:
/// - `createLocal` mints a v4 UUID (the client value becomes the server id —
///   `meal_templates.id` accepts a client value, so no temp-id reconciliation),
///   marks the template pendingCreate, and stores its items inline.
/// - `deleteLocal` on a synced template writes a tombstone; on a template that
///   was only ever local (pendingCreate) it just drops the file.
/// - `syncWithServer(api)` drains every non-synced template in create → delete
///   order. There is no edit path (build / save / delete only, mirroring web).
class LocalMealTemplateStore extends OfflineSyncStore<StoredMealTemplate> {
  @override
  String get storeSubdir => 'meal_templates';

  @override
  String get debugLabel => 'local_meal_template_store';

  @override
  StoredMealTemplate entryFromJson(Map<String, dynamic> json) =>
      StoredMealTemplate.fromJson(json);

  @override
  String? get summaryTimestampKey => 'last_modified_at';

  @override
  Map<String, dynamic> summaryOf(StoredMealTemplate entry) => {
        'id': entry.id,
        'sync_state': entry.syncState.wire,
        'last_modified_at': entry.row['last_modified_at'],
        'name': entry.row['name'],
        'item_count': entry.itemCount,
      };

  @override
  StoredMealTemplate asSynced(StoredMealTemplate entry) => StoredMealTemplate(
        row: entry.row,
        items: entry.items,
        syncState: SyncState.synced,
        lastModifiedAt: entry.lastModifiedAt,
      );

  @override
  StoredMealTemplate asPendingCreate(StoredMealTemplate entry) =>
      StoredMealTemplate(
        row: entry.row,
        items: entry.items,
        syncState: SyncState.pendingCreate,
        lastModifiedAt: entry.lastModifiedAt,
      );

  /// Live templates (excludes tombstones), most-recently-modified first — the
  /// list order, matching web `fetchMealTemplates`.
  List<StoredMealTemplate> get templates {
    final live = rowsById.values.where((t) => !t.isTombstone).toList();
    live.sort((a, b) => b.lastModifiedAt.compareTo(a.lastModifiedAt));
    return live;
  }

  /// A single live template by id, or null if missing / a tombstone.
  StoredMealTemplate? byId(String id) {
    final t = rowsById[id];
    return (t == null || t.isTombstone) ? null : t;
  }

  /// Mint a new UUID and persist a pending-create template. Blank-named items
  /// are dropped (mirroring web `createMealTemplate`). Returns the stored shape
  /// so the caller can render it immediately.
  Future<StoredMealTemplate> createLocal({
    required String name,
    String? mealSlot,
    List<StoredMealTemplateItem> items = const [],
  }) async {
    final id = OfflineSyncStore.newUuid();
    final now = DateTime.now().toUtc();
    final kept =
        items.where((it) => it.itemName.trim().isNotEmpty).toList(growable: false);
    final row = <String, dynamic>{
      'id': id,
      'name': name.trim(),
      'meal_slot': mealSlot,
      'item_count': kept.length,
      'external_id': null,
      'last_modified_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    };
    final stored = StoredMealTemplate(
      row: row,
      items: kept,
      syncState: SyncState.pendingCreate,
      lastModifiedAt: now,
    );
    await persist(stored);
    return stored;
  }

  /// Delete a template. A template that was only ever local (pendingCreate)
  /// disappears immediately; a synced template becomes a pendingDelete
  /// tombstone so the next sync issues the server DELETE (which cascades the
  /// items). Logged food_log entries are untouched.
  Future<void> deleteLocal(String id) async {
    final existing = rowsById[id];
    if (existing == null) return;
    if (existing.syncState == SyncState.pendingCreate) {
      await dropRow(id);
      return;
    }
    final tombstone = StoredMealTemplate(
      row: existing.row,
      items: existing.items,
      syncState: SyncState.pendingDelete,
    );
    await persist(tombstone);
  }

  /// Replace the in-memory state from a fresh server fetch (each template with
  /// its items). Pending-* templates are preserved — only `synced` rows are
  /// overwritten so an offline create / delete isn't clobbered by the server's
  /// copy. Newer-wins on the synced copies, mirroring
  /// [LocalRoutineStore.replaceFromServer].
  Future<void> replaceFromServer(
    List<({Map<String, dynamic> template, List<StoredMealTemplateItem> items})>
        serverTemplates,
  ) async {
    requireInitialised('replaceFromServer');
    final preserved = <String, StoredMealTemplate>{};
    final syncedLocal = <String, StoredMealTemplate>{};
    for (final entry in rowsById.entries) {
      if (entry.value.syncState != SyncState.synced) {
        preserved[entry.key] = entry.value;
      } else {
        syncedLocal[entry.key] = entry.value;
      }
    }
    rowsById.clear();
    for (final t in serverTemplates) {
      final id = t.template['id'] as String;
      if (preserved.containsKey(id)) {
        rowsById[id] = preserved.remove(id)!;
        continue;
      }
      final local = syncedLocal[id];
      final serverTs = parseServerTimestamp(t.template['last_modified_at']);
      if (local != null &&
          serverTs != null &&
          local.lastModifiedAt.isAfter(serverTs)) {
        rowsById[id] = local;
      } else {
        rowsById[id] = StoredMealTemplate(
          row: t.template,
          items: t.items,
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
  Future<void> pushCreate(ApiClient api, StoredMealTemplate stored) =>
      api.createMealTemplate(
        id: stored.id,
        name: stored.name,
        mealSlot: stored.mealSlot,
        lastModifiedAt: stored.lastModifiedAt,
        items: _itemsToInput(stored.items),
      );

  // There is no edit path (build / save / delete only), so a template never
  // reaches pendingUpdate — but the base class requires the hook. Recreate to
  // stay correct if a future edit path ever flips the state.
  @override
  Future<void> pushUpdate(ApiClient api, StoredMealTemplate stored) async {
    await api.deleteMealTemplate(stored.id);
    await api.createMealTemplate(
      id: stored.id,
      name: stored.name,
      mealSlot: stored.mealSlot,
      lastModifiedAt: stored.lastModifiedAt,
      items: _itemsToInput(stored.items),
    );
  }

  @override
  Future<void> pushDelete(ApiClient api, StoredMealTemplate stored) =>
      api.deleteMealTemplate(stored.id);

  static List<MealTemplateItemInput> _itemsToInput(
          List<StoredMealTemplateItem> items) =>
      [
        for (final it in items)
          (
            itemName: it.itemName,
            mealSlot: it.mealSlot,
            calories: it.calories,
            proteinG: it.proteinG,
            carbsG: it.carbsG,
            fatG: it.fatG,
            externalId: it.externalId,
          ),
      ];
}
