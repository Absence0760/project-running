import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'offline_sync_store.dart';

/// Sync state for a single gear row. Alias of the shared [SyncState] so the
/// store tests + screens keep the `GearSyncState` name.
typedef GearSyncState = SyncState;

/// One stored row in the [LocalGearStore]. Holds the `gear_with_distance`
/// shape plus the sync-state tag. `total_distance_m` comes from the
/// server view; offline-created rows start at 0 and pick up the real
/// total on the next sync.
class StoredGear implements SyncEntry {
  StoredGear({
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

  @override
  Map<String, dynamic> toJson() => {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'row': row,
        'sync_state': syncState.wire,
        'last_modified_at': lastModifiedAt.toIso8601String(),
      };

  factory StoredGear.fromJson(Map<String, dynamic> json) => StoredGear(
        row: Map<String, dynamic>.from(json['row'] as Map),
        syncState: syncStateFromWire(json['sync_state'] as String?),
        lastModifiedAt: DateTime.tryParse(
                json['last_modified_at'] as String? ?? '')
                ?.toUtc() ??
            DateTime.now().toUtc(),
      );
}

/// Disk-backed store for the user's gear inventory. Mirrors
/// [LocalRunStore]'s pattern: one JSON file per row under
/// `<appDocs>/gear/`, in-memory `ChangeNotifier` so screens refresh on
/// every mutation, sync drained on demand (sign-in, connectivity
/// return, manual pull-to-refresh).
///
/// The per-row sync-state machine (load / persist / drain / crash-atomic
/// rewrite / UUID mint) lives in [OfflineSyncStore]; this class supplies the
/// gear-specific create / update / replace-from-server logic.
///
/// Offline contract:
/// - `createLocal` mints a v4 UUID, marks the row pendingCreate.
/// - `updateLocal` / `retireLocal` / `unretireLocal` flip pendingUpdate
///   while preserving pendingCreate (a row created offline that's
///   edited offline stays pendingCreate; the eventual INSERT carries
///   the latest values).
/// - `deleteLocal` on a synced row writes a tombstone; on a row that
///   was only ever local (pendingCreate) it just drops the file.
/// - `syncWithServer(api)` drains every non-synced row in the order
///   create → update → delete. Failures leave the row in its pending
///   state for the next drain.
class LocalGearStore extends OfflineSyncStore<StoredGear> {
  @override
  String get storeSubdir => 'gear';

  @override
  String get debugLabel => 'local_gear_store';

  @override
  StoredGear entryFromJson(Map<String, dynamic> json) =>
      StoredGear.fromJson(json);

  // No windowed surface for gear — the index is only a cold-load fast path, so
  // [summaryTimestampKey] stays null (the base default).
  @override
  Map<String, dynamic> summaryOf(StoredGear entry) => {
        'id': entry.id,
        'sync_state': entry.syncState.wire,
        'kind': entry.row['kind'],
        'name': entry.row['name'],
        'retired_at': entry.row['retired_at'],
      };

  @override
  StoredGear asSynced(StoredGear entry) => StoredGear(
        row: entry.row,
        syncState: SyncState.synced,
        lastModifiedAt: entry.lastModifiedAt,
      );

  @override
  StoredGear asPendingCreate(StoredGear entry) => StoredGear(
        row: entry.row,
        syncState: SyncState.pendingCreate,
        lastModifiedAt: entry.lastModifiedAt,
      );

  /// Read-only snapshot of the live rows (excludes tombstones).
  List<Map<String, dynamic>> get rows => rowsById.values
      .where((g) => !g.isTombstone)
      .map((g) => g.row)
      .toList();

  /// Mint a new UUID and persist a pending-create row. The local id
  /// becomes the server id once `syncWithServer` succeeds. Returns the
  /// stored shape so the caller can render it immediately.
  Future<StoredGear> createLocal({
    required String kind,
    required String name,
    String? brand,
    String? model,
    DateTime? purchasedAt,
    int? targetDistanceM,
    String? notes,
  }) async {
    final id = OfflineSyncStore.newUuid();
    final now = DateTime.now().toUtc();
    final row = <String, dynamic>{
      'id': id,
      'kind': kind,
      'name': name,
      'brand': brand,
      'model': model,
      'purchased_at': purchasedAt?.toIso8601String().substring(0, 10),
      'retired_at': null,
      'target_distance_m': targetDistanceM,
      'notes': notes,
      'created_at': now.toIso8601String(),
      'total_distance_m': 0,
    };
    // Stamp the conflict-resolution clock explicitly at create time rather
    // than relying on the StoredGear default — keeps the value derived from
    // the same `now` as `created_at` and matches the gym/food stores.
    final stored = StoredGear(
      row: row,
      syncState: SyncState.pendingCreate,
      lastModifiedAt: now,
    );
    await persist(stored);
    return stored;
  }

  /// Patch an existing row. Preserves `pendingCreate` if the row hasn't
  /// been pushed yet — the next sync replays the full insert with the
  /// merged values.
  Future<void> updateLocal(String id, Map<String, dynamic> changes) async {
    final existing = rowsById[id];
    if (existing == null) return;
    final next = Map<String, dynamic>.from(existing.row)..addAll(changes);
    final stored = StoredGear(
      row: next,
      syncState: existing.syncState == SyncState.pendingCreate
          ? SyncState.pendingCreate
          : SyncState.pendingUpdate,
    );
    await persist(stored);
  }

  /// Stamp `retired_at` to today.
  Future<void> retireLocal(String id) async {
    // Local calendar date — `retired_at` is a DATE, and a UTC stamp rolls a
    // day early/late for runners behind/ahead of UTC. A local `DateTime`'s
    // `toIso8601String()` is the local wall-clock (no `Z`), so its first 10
    // chars are the local YYYY-MM-DD. Mirrors web `retireGear`'s `todayISO()`.
    await updateLocal(id, {
      'retired_at': DateTime.now().toIso8601String().substring(0, 10),
    });
  }

  /// Clear `retired_at`.
  Future<void> unretireLocal(String id) async {
    await updateLocal(id, {'retired_at': null});
  }

  /// Delete a row. A row that was only ever local (pendingCreate)
  /// disappears immediately; a synced or pendingUpdate row becomes a
  /// pendingDelete tombstone so the next sync issues the server DELETE.
  Future<void> deleteLocal(String id) async {
    final existing = rowsById[id];
    if (existing == null) return;
    if (existing.syncState == SyncState.pendingCreate) {
      rowsById.remove(id);
      final file = File('${dir!.path}/$id.json');
      if (file.existsSync()) file.deleteSync();
      notifyListeners();
      return;
    }
    final tombstone = StoredGear(
      row: existing.row,
      syncState: SyncState.pendingDelete,
    );
    await persist(tombstone);
  }

  /// Replace the in-memory state from a fresh `gear_with_distance`
  /// fetch. Pending-* rows are preserved as-is — only rows in `synced`
  /// state are overwritten so an offline edit isn't clobbered by the
  /// server's older copy.
  Future<void> replaceFromServer(List<Map<String, dynamic>> serverRows) async {
    final preserved = <String, StoredGear>{};
    for (final entry in rowsById.entries) {
      if (entry.value.syncState != SyncState.synced) {
        preserved[entry.key] = entry.value;
      }
    }
    rowsById.clear();
    for (final row in serverRows) {
      final id = row['id'] as String;
      if (preserved.containsKey(id)) {
        rowsById[id] = preserved.remove(id)!;
      } else {
        rowsById[id] = StoredGear(row: row, syncState: SyncState.synced);
      }
    }
    rowsById.addAll(preserved);
    await rewriteAll();
    notifyListeners();
  }

  @override
  Future<void> pushCreate(ApiClient api, StoredGear stored) => api.createGear(
        id: stored.id,
        kind: stored.row['kind'] as String,
        name: stored.row['name'] as String,
        brand: stored.row['brand'] as String?,
        model: stored.row['model'] as String?,
        purchasedAt: _parseDate(stored.row['purchased_at']),
        targetDistanceM: (stored.row['target_distance_m'] as num?)?.toInt(),
        notes: stored.row['notes'] as String?,
      );

  @override
  Future<void> pushUpdate(ApiClient api, StoredGear stored) => api.updateGear(
        stored.id,
        name: stored.row['name'] as String?,
        brand: stored.row['brand'] as String?,
        model: stored.row['model'] as String?,
        purchasedAt: _parseDate(stored.row['purchased_at']),
        retiredAt: _parseDate(stored.row['retired_at']),
        clearRetiredAt: stored.row['retired_at'] == null,
        targetDistanceM: (stored.row['target_distance_m'] as num?)?.toInt(),
        notes: stored.row['notes'] as String?,
      );

  @override
  Future<void> pushDelete(ApiClient api, StoredGear stored) =>
      api.deleteGear(stored.id);

  static DateTime? _parseDate(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}
