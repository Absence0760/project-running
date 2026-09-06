import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'offline_sync_store.dart';

/// Sync state for a single food-log entry. Alias of the shared [SyncState] so
/// the store tests + nutrition surfaces keep the `FoodSyncState` name.
typedef FoodSyncState = SyncState;

/// One stored entry in the [LocalFoodStore]. Holds the `food_log` row
/// shape plus the sync-state tag.
class StoredFood implements SyncEntry {
  StoredFood({
    required this.row,
    required this.syncState,
    DateTime? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.now().toUtc();

  final Map<String, dynamic> row;
  @override
  final SyncState syncState;
  @override
  final DateTime lastModifiedAt;

  @override
  String get id => row['id'] as String;
  @override
  bool get isTombstone => syncState == SyncState.pendingDelete;

  /// Typed domain view of this entry. Lets the nutrition surfaces read
  /// `.entry.itemName` instead of reaching into the raw `row` map.
  FoodEntry get entry => FoodEntry.fromRow(row);

  DateTime? get startedAt => parseServerTimestamp(row['started_at']);

  @override
  Map<String, dynamic> toJson() => {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'row': row,
        'sync_state': syncState.wire,
        'last_modified_at': lastModifiedAt.toIso8601String(),
      };

  factory StoredFood.fromJson(Map<String, dynamic> json) => StoredFood(
        row: Map<String, dynamic>.from(json['row'] as Map),
        syncState: syncStateFromWire(json['sync_state'] as String?),
        lastModifiedAt: storedClockOrNow(json['last_modified_at']),
      );
}

/// Disk-backed store for the user's food log. Mirrors [LocalGearStore]
/// (decisions §73 + §122): one JSON file per entry under `<appDocs>/food/`,
/// in-memory `ChangeNotifier` so screens refresh on every mutation, sync
/// drained on demand (sign-in, connectivity return, manual pull-to-refresh).
/// The per-row sync-state machine lives in [OfflineSyncStore]; this class
/// supplies the food-specific create / update / replace-from-server logic.
///
/// Offline contract:
/// - `createLocal` mints a v4 UUID (the client value becomes the server
///   id — `food_log.id` defaults to gen_random_uuid() but accepts a
///   client value, so no temp-id reconciliation is needed), marks the
///   entry pendingCreate.
/// - `updateLocal` patches fields while preserving pendingCreate (an
///   entry created offline that's edited offline stays pendingCreate; the
///   eventual INSERT carries the latest values).
/// - `deleteLocal` on a synced entry writes a tombstone; on an entry that
///   was only ever local (pendingCreate) it just drops the file.
/// - `syncWithServer(api)` drains every non-synced entry in the order
///   create → update → delete. Failures leave the entry in its pending
///   state for the next drain.
class LocalFoodStore extends OfflineSyncStore<StoredFood> {
  @override
  String get storeSubdir => 'food';

  @override
  String get debugLabel => 'local_food_store';

  @override
  StoredFood entryFromJson(Map<String, dynamic> json) =>
      StoredFood.fromJson(json);

  @override
  String? get summaryTimestampKey => 'started_at';

  @override
  Map<String, dynamic> summaryOf(StoredFood entry) => {
        'id': entry.id,
        'sync_state': entry.syncState.wire,
        'started_at': entry.row['started_at'],
        'item_name': entry.row['item_name'],
        'calories': entry.row['calories'],
      };

  @override
  StoredFood asSynced(StoredFood entry) => StoredFood(
        row: entry.row,
        syncState: SyncState.synced,
        lastModifiedAt: entry.lastModifiedAt,
      );

  @override
  StoredFood asPendingCreate(StoredFood entry) => StoredFood(
        row: entry.row,
        syncState: SyncState.pendingCreate,
        lastModifiedAt: entry.lastModifiedAt,
      );

  List<Map<String, dynamic>>? _rowsCache;
  int _rowsCacheRevision = -1;

  /// Live entries (excludes tombstones), newest-logged first. Cached against
  /// [storeRevision] so the nutrition screen's repeated per-frame reads (the
  /// day list + the 7-day trend) don't each re-sort the whole food history.
  /// The sort key is parsed once per entry rather than per comparison.
  List<Map<String, dynamic>> get rows {
    if (_rowsCache != null && _rowsCacheRevision == storeRevision) {
      return _rowsCache!;
    }
    final keyed = [
      for (final f in rowsById.values)
        if (!f.isTombstone) (row: f.row, t: f.startedAt),
    ];
    keyed.sort((a, b) {
      final at = a.t;
      final bt = b.t;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
    final out = [for (final e in keyed) e.row];
    _rowsCache = out;
    _rowsCacheRevision = storeRevision;
    return out;
  }

  /// Serialised live entries (excludes tombstones) in the
  /// `StoredFood.toJson()` shape, for the backup archive's `food_log.json`.
  List<Map<String, dynamic>> get backupRecords => rowsById.values
      .where((f) => !f.isTombstone)
      .map((f) => f.toJson())
      .toList();

  /// Live entries logged in the half-open day range [from, to),
  /// newest-logged first. The nutrition screen renders a single day.
  List<Map<String, dynamic>> entriesForRange(DateTime from, DateTime to) =>
      rows.where((r) {
        final at = parseServerTimestamp(r['started_at']);
        if (at == null) return false;
        return !at.isBefore(from) && at.isBefore(to);
      }).toList();

  /// Mint a new UUID and persist a pending-create entry. Returns the
  /// stored shape so the caller can render it immediately.
  Future<StoredFood> createLocal({
    required DateTime startedAt,
    required String itemName,
    String? mealSlot,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fiberG,
    double? sugarG,
    double? sodiumMg,
    double? saturatedFatG,
    double? cholesterolMg,
    bool isPublic = false,
  }) async {
    final id = OfflineSyncStore.newUuid();
    final now = DateTime.now().toUtc();
    final row = <String, dynamic>{
      'id': id,
      'started_at': startedAt.toUtc().toIso8601String(),
      'item_name': itemName,
      'meal_slot': mealSlot,
      'calories': calories,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'fat_g': fatG,
      'fiber_g': fiberG,
      'sugar_g': sugarG,
      'sodium_mg': sodiumMg,
      'saturated_fat_g': saturatedFatG,
      'cholesterol_mg': cholesterolMg,
      'is_public': isPublic,
      'external_id': null,
      'last_modified_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    };
    final stored = StoredFood(
      row: row,
      syncState: SyncState.pendingCreate,
      lastModifiedAt: now,
    );
    await persist(stored);
    return stored;
  }

  /// Patch an existing entry. Preserves `pendingCreate` if the entry
  /// hasn't been pushed yet — the next sync replays the full insert with
  /// the merged values.
  Future<void> updateLocal(
    String id, {
    String? itemName,
    String? mealSlot,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fiberG,
    double? sugarG,
    double? sodiumMg,
    double? saturatedFatG,
    double? cholesterolMg,
    bool? isPublic,
  }) async {
    final existing = rowsById[id];
    if (existing == null) return;
    final now = DateTime.now().toUtc();
    final next = Map<String, dynamic>.from(existing.row);
    if (itemName != null) next['item_name'] = itemName;
    if (mealSlot != null) next['meal_slot'] = mealSlot;
    if (calories != null) next['calories'] = calories;
    if (proteinG != null) next['protein_g'] = proteinG;
    if (carbsG != null) next['carbs_g'] = carbsG;
    if (fatG != null) next['fat_g'] = fatG;
    if (fiberG != null) next['fiber_g'] = fiberG;
    if (sugarG != null) next['sugar_g'] = sugarG;
    if (sodiumMg != null) next['sodium_mg'] = sodiumMg;
    if (saturatedFatG != null) next['saturated_fat_g'] = saturatedFatG;
    if (cholesterolMg != null) next['cholesterol_mg'] = cholesterolMg;
    if (isPublic != null) next['is_public'] = isPublic;
    next['last_modified_at'] = now.toIso8601String();
    final stored = StoredFood(
      row: next,
      syncState: existing.syncState == SyncState.pendingCreate
          ? SyncState.pendingCreate
          : SyncState.pendingUpdate,
      lastModifiedAt: now,
    );
    await persist(stored);
  }

  /// Delete an entry. An entry that was only ever local (pendingCreate)
  /// disappears immediately; a synced or pendingUpdate entry becomes a
  /// pendingDelete tombstone so the next sync issues the server DELETE.
  Future<void> deleteLocal(String id) async {
    final existing = rowsById[id];
    if (existing == null) return;
    if (existing.syncState == SyncState.pendingCreate) {
      await dropRow(id);
      return;
    }
    final tombstone = StoredFood(
      row: existing.row,
      syncState: SyncState.pendingDelete,
    );
    await persist(tombstone);
  }

  /// Replace the in-memory state from a fresh `food_log` fetch. Pending-*
  /// entries are preserved as-is — only `synced` rows are overwritten so
  /// an offline edit isn't clobbered by the server's older copy.
  ///
  /// When the fetch was WINDOWED (the nutrition + dashboard surfaces pull only
  /// the last 7 days), pass that window as `[windowStart, windowEnd)`. A synced
  /// row whose `started_at` falls OUTSIDE the window could not have been
  /// returned by the fetch, so its absence is "outside the window", NOT a
  /// server-side deletion — it is preserved (and its on-disk file kept). Within
  /// the window, an absent synced row is treated as deleted and pruned. With no
  /// window (both null) this is a full replace: every absent synced row is
  /// pruned, the right behaviour only when the caller fetched the COMPLETE set.
  Future<void> replaceFromServer(
    List<Map<String, dynamic>> serverRows, {
    DateTime? windowStart,
    DateTime? windowEnd,
  }) async {
    requireInitialised('replaceFromServer');
    final preserved = <String, StoredFood>{};
    final syncedLocal = <String, StoredFood>{};
    for (final entry in rowsById.entries) {
      if (entry.value.syncState != SyncState.synced) {
        preserved[entry.key] = entry.value;
      } else if (outsideFetchWindow(
          entry.value.startedAt, windowStart, windowEnd)) {
        preserved[entry.key] = entry.value;
      } else {
        syncedLocal[entry.key] = entry.value;
      }
    }
    rowsById.clear();
    for (final row in serverRows) {
      final id = row['id'] as String;
      if (preserved.containsKey(id)) {
        rowsById[id] = preserved.remove(id)!;
        continue;
      }
      // Newer-wins: keep the local synced copy when its modification clock
      // is strictly ahead of the server's, so a stale server fetch can't
      // clobber a more-recent already-pushed edit. Mirrors
      // LocalRunStore.saveFromRemote's guard.
      final local = syncedLocal[id];
      final serverTs = parseServerTimestamp(row['last_modified_at']);
      if (local != null &&
          serverTs != null &&
          local.lastModifiedAt.isAfter(serverTs)) {
        rowsById[id] = local;
      } else {
        // Build the synced row's clock from the server's last_modified_at
        // (not wall-clock now) so the next refresh's newer-wins compares
        // like-for-like.
        rowsById[id] = StoredFood(
          row: row,
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
  Future<void> pushCreate(ApiClient api, StoredFood stored) => api.logFood(
        id: stored.id,
        startedAt: stored.startedAt ?? DateTime.now().toUtc(),
        itemName: stored.row['item_name'] as String,
        mealSlot: stored.row['meal_slot'] as String?,
        calories: (stored.row['calories'] as num?)?.toDouble(),
        proteinG: (stored.row['protein_g'] as num?)?.toDouble(),
        carbsG: (stored.row['carbs_g'] as num?)?.toDouble(),
        fatG: (stored.row['fat_g'] as num?)?.toDouble(),
        fiberG: (stored.row['fiber_g'] as num?)?.toDouble(),
        sugarG: (stored.row['sugar_g'] as num?)?.toDouble(),
        sodiumMg: (stored.row['sodium_mg'] as num?)?.toDouble(),
        saturatedFatG: (stored.row['saturated_fat_g'] as num?)?.toDouble(),
        cholesterolMg: (stored.row['cholesterol_mg'] as num?)?.toDouble(),
        isPublic: (stored.row['is_public'] as bool?) ?? false,
        lastModifiedAt: stored.lastModifiedAt,
      );

  @override
  Future<void> pushUpdate(ApiClient api, StoredFood stored) =>
      api.updateFoodLog(
        stored.id,
        itemName: stored.row['item_name'] as String?,
        mealSlot: stored.row['meal_slot'] as String?,
        calories: (stored.row['calories'] as num?)?.toDouble(),
        proteinG: (stored.row['protein_g'] as num?)?.toDouble(),
        carbsG: (stored.row['carbs_g'] as num?)?.toDouble(),
        fatG: (stored.row['fat_g'] as num?)?.toDouble(),
        fiberG: (stored.row['fiber_g'] as num?)?.toDouble(),
        sugarG: (stored.row['sugar_g'] as num?)?.toDouble(),
        sodiumMg: (stored.row['sodium_mg'] as num?)?.toDouble(),
        saturatedFatG: (stored.row['saturated_fat_g'] as num?)?.toDouble(),
        cholesterolMg: (stored.row['cholesterol_mg'] as num?)?.toDouble(),
        isPublic: (stored.row['is_public'] as bool?) ?? false,
        lastModifiedAt: stored.lastModifiedAt,
      );

  @override
  Future<void> pushDelete(ApiClient api, StoredFood stored) =>
      api.deleteFoodLog(stored.id);
}
