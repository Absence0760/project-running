import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Sync state for a single food-log entry. Mirrors [GearSyncState]: a
/// freshly-logged item is `pendingCreate` until the INSERT succeeds; a
/// portion / macro / meal-slot edit becomes `pendingUpdate`; a deleted
/// item is kept as a tombstone with `pendingDelete` until the server
/// DELETE returns 2xx.
enum FoodSyncState { synced, pendingCreate, pendingUpdate, pendingDelete }

extension on FoodSyncState {
  String get wire {
    switch (this) {
      case FoodSyncState.synced:
        return 'synced';
      case FoodSyncState.pendingCreate:
        return 'pending_create';
      case FoodSyncState.pendingUpdate:
        return 'pending_update';
      case FoodSyncState.pendingDelete:
        return 'pending_delete';
    }
  }
}

/// One stored entry in the [LocalFoodStore]. Holds the `food_log` row
/// shape plus the sync-state tag.
class StoredFood {
  StoredFood({
    required this.row,
    required this.syncState,
    DateTime? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.now().toUtc();

  final Map<String, dynamic> row;
  final FoodSyncState syncState;
  final DateTime lastModifiedAt;

  String get id => row['id'] as String;
  bool get isTombstone => syncState == FoodSyncState.pendingDelete;

  DateTime? get loggedAt {
    final v = row['logged_at'];
    return v is String ? DateTime.tryParse(v) : null;
  }

  Map<String, dynamic> toJson() => {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'row': row,
        'sync_state': syncState.wire,
        'last_modified_at': lastModifiedAt.toIso8601String(),
      };

  factory StoredFood.fromJson(Map<String, dynamic> json) => StoredFood(
        row: Map<String, dynamic>.from(json['row'] as Map),
        syncState: _fromWire(json['sync_state'] as String?),
        lastModifiedAt:
            DateTime.tryParse(json['last_modified_at'] as String? ?? '')
                    ?.toUtc() ??
                DateTime.now().toUtc(),
      );

  static FoodSyncState _fromWire(String? s) {
    switch (s) {
      case 'pending_create':
        return FoodSyncState.pendingCreate;
      case 'pending_update':
        return FoodSyncState.pendingUpdate;
      case 'pending_delete':
        return FoodSyncState.pendingDelete;
      case 'synced':
      default:
        return FoodSyncState.synced;
    }
  }
}

/// Disk-backed store for the user's food log. Mirrors [LocalGearStore]
/// (decisions §73): one JSON file per entry under `<appDocs>/food/`,
/// in-memory `ChangeNotifier` so screens refresh on every mutation, sync
/// drained on demand (sign-in, connectivity return, manual
/// pull-to-refresh).
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
class LocalFoodStore extends ChangeNotifier {
  static final Random _rand = Random.secure();

  Directory? _dir;
  final Map<String, StoredFood> _rows = <String, StoredFood>{};

  /// Live entries (excludes tombstones), newest-logged first.
  List<Map<String, dynamic>> get rows {
    final live = _rows.values.where((f) => !f.isTombstone).toList();
    live.sort((a, b) {
      final at = a.loggedAt;
      final bt = b.loggedAt;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
    return live.map((f) => f.row).toList();
  }

  /// Live entries logged in the half-open day range [from, to),
  /// newest-logged first. The nutrition screen renders a single day.
  List<Map<String, dynamic>> entriesForRange(DateTime from, DateTime to) =>
      rows.where((r) {
        final v = r['logged_at'];
        final at = v is String ? DateTime.tryParse(v) : null;
        if (at == null) return false;
        return !at.isBefore(from) && at.isBefore(to);
      }).toList();

  /// True when at least one entry hasn't been pushed to the server.
  bool get hasPending =>
      _rows.values.any((f) => f.syncState != FoodSyncState.synced);

  Future<void> init({Directory? overrideDirectory}) async {
    if (overrideDirectory != null) {
      _dir = overrideDirectory;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      _dir = Directory('${appDir.path}/food');
    }
    if (!_dir!.existsSync()) {
      _dir!.createSync(recursive: true);
    }
    await _loadAll();
  }

  Future<void> _loadAll() async {
    _rows.clear();
    final dir = _dir;
    if (dir == null) return;
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = entity.readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final stored = StoredFood.fromJson(_migrateRecord(json, entity.path));
        _rows[stored.id] = stored;
      } catch (e) {
        debugPrint('local_food_store: corrupt row ${entity.path}: $e');
      }
    }
    notifyListeners();
  }

  /// Forward-migration hook for a stored record read off disk. Resolves the
  /// `_v` schema stamp and upgrades older shapes to the current one. The
  /// current shape (v1) is forward-compatible with the legacy unstamped
  /// shape (v0), so the migration is a pass-through today; future
  /// incompatible changes bump [kLocalStoreSchemaVersion] and branch here.
  Map<String, dynamic> _migrateRecord(Map<String, dynamic> json, String path) {
    final version = localStoreRecordVersion(json);
    if (version > kLocalStoreSchemaVersion) {
      debugPrint(
          'local_food_store: record $path has _v=$version (> $kLocalStoreSchemaVersion); reading known fields only');
    }
    return json;
  }

  /// Mint a new UUID and persist a pending-create entry. Returns the
  /// stored shape so the caller can render it immediately.
  Future<StoredFood> createLocal({
    required DateTime loggedAt,
    required String itemName,
    String? mealSlot,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    bool isPublic = false,
  }) async {
    final id = _newUuid();
    final now = DateTime.now().toUtc();
    final row = <String, dynamic>{
      'id': id,
      'logged_at': loggedAt.toUtc().toIso8601String(),
      'item_name': itemName,
      'meal_slot': mealSlot,
      'calories': calories,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'fat_g': fatG,
      'is_public': isPublic,
      'external_id': null,
      'last_modified_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    };
    final stored = StoredFood(
      row: row,
      syncState: FoodSyncState.pendingCreate,
      lastModifiedAt: now,
    );
    await _persist(stored);
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
    bool? isPublic,
  }) async {
    final existing = _rows[id];
    if (existing == null) return;
    final now = DateTime.now().toUtc();
    final next = Map<String, dynamic>.from(existing.row);
    if (itemName != null) next['item_name'] = itemName;
    if (mealSlot != null) next['meal_slot'] = mealSlot;
    if (calories != null) next['calories'] = calories;
    if (proteinG != null) next['protein_g'] = proteinG;
    if (carbsG != null) next['carbs_g'] = carbsG;
    if (fatG != null) next['fat_g'] = fatG;
    if (isPublic != null) next['is_public'] = isPublic;
    next['last_modified_at'] = now.toIso8601String();
    final stored = StoredFood(
      row: next,
      syncState: existing.syncState == FoodSyncState.pendingCreate
          ? FoodSyncState.pendingCreate
          : FoodSyncState.pendingUpdate,
      lastModifiedAt: now,
    );
    await _persist(stored);
  }

  /// Delete an entry. An entry that was only ever local (pendingCreate)
  /// disappears immediately; a synced or pendingUpdate entry becomes a
  /// pendingDelete tombstone so the next sync issues the server DELETE.
  Future<void> deleteLocal(String id) async {
    final existing = _rows[id];
    if (existing == null) return;
    if (existing.syncState == FoodSyncState.pendingCreate) {
      _rows.remove(id);
      final file = File('${_dir!.path}/$id.json');
      if (file.existsSync()) file.deleteSync();
      notifyListeners();
      return;
    }
    final tombstone = StoredFood(
      row: existing.row,
      syncState: FoodSyncState.pendingDelete,
    );
    await _persist(tombstone);
  }

  /// Replace the in-memory state from a fresh `food_log` fetch. Pending-*
  /// entries are preserved as-is — only `synced` rows are overwritten so
  /// an offline edit isn't clobbered by the server's older copy.
  Future<void> replaceFromServer(List<Map<String, dynamic>> serverRows) async {
    final preserved = <String, StoredFood>{};
    final syncedLocal = <String, StoredFood>{};
    for (final entry in _rows.entries) {
      if (entry.value.syncState != FoodSyncState.synced) {
        preserved[entry.key] = entry.value;
      } else {
        syncedLocal[entry.key] = entry.value;
      }
    }
    _rows.clear();
    for (final row in serverRows) {
      final id = row['id'] as String;
      if (preserved.containsKey(id)) {
        _rows[id] = preserved.remove(id)!;
        continue;
      }
      // Newer-wins: keep the local synced copy when its modification clock
      // is strictly ahead of the server's, so a stale server fetch can't
      // clobber a more-recent already-pushed edit. Mirrors
      // LocalRunStore.saveFromRemote's guard.
      final local = syncedLocal[id];
      final serverTs = _parseTs(row['last_modified_at']);
      if (local != null &&
          serverTs != null &&
          local.lastModifiedAt.isAfter(serverTs)) {
        _rows[id] = local;
      } else {
        // Build the synced row's clock from the server's last_modified_at
        // (not wall-clock now) so the next refresh's newer-wins compares
        // like-for-like.
        _rows[id] = StoredFood(
          row: row,
          syncState: FoodSyncState.synced,
          lastModifiedAt: serverTs,
        );
      }
    }
    _rows.addAll(preserved);
    await _rewriteAll();
    notifyListeners();
  }

  static DateTime? _parseTs(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toUtc();
    return null;
  }

  /// Push every pending entry to the server. Returns the count of entries
  /// successfully drained — caller can surface a banner when ≥1.
  Future<int> syncWithServer(ApiClient api) async {
    var drained = 0;
    for (final stored in List<StoredFood>.from(_rows.values)) {
      try {
        switch (stored.syncState) {
          case FoodSyncState.pendingCreate:
            await api.logFood(
              id: stored.id,
              loggedAt: stored.loggedAt ?? DateTime.now().toUtc(),
              itemName: stored.row['item_name'] as String,
              mealSlot: stored.row['meal_slot'] as String?,
              calories: (stored.row['calories'] as num?)?.toDouble(),
              proteinG: (stored.row['protein_g'] as num?)?.toDouble(),
              carbsG: (stored.row['carbs_g'] as num?)?.toDouble(),
              fatG: (stored.row['fat_g'] as num?)?.toDouble(),
              isPublic: (stored.row['is_public'] as bool?) ?? false,
              lastModifiedAt: stored.lastModifiedAt,
            );
            await _markSynced(stored.id);
            drained++;
            break;
          case FoodSyncState.pendingUpdate:
            await api.updateFoodLog(
              stored.id,
              itemName: stored.row['item_name'] as String?,
              mealSlot: stored.row['meal_slot'] as String?,
              calories: (stored.row['calories'] as num?)?.toDouble(),
              proteinG: (stored.row['protein_g'] as num?)?.toDouble(),
              carbsG: (stored.row['carbs_g'] as num?)?.toDouble(),
              fatG: (stored.row['fat_g'] as num?)?.toDouble(),
              isPublic: (stored.row['is_public'] as bool?) ?? false,
              lastModifiedAt: stored.lastModifiedAt,
            );
            await _markSynced(stored.id);
            drained++;
            break;
          case FoodSyncState.pendingDelete:
            await api.deleteFoodLog(stored.id);
            await _dropRow(stored.id);
            drained++;
            break;
          case FoodSyncState.synced:
            break;
        }
      } catch (e) {
        debugPrint('local_food_store: sync failed for ${stored.id}: $e');
      }
    }
    return drained;
  }

  Future<void> _markSynced(String id) async {
    final existing = _rows[id];
    if (existing == null) return;
    final stored = StoredFood(
      row: existing.row,
      syncState: FoodSyncState.synced,
      lastModifiedAt: existing.lastModifiedAt,
    );
    await _persist(stored);
  }

  Future<void> _dropRow(String id) async {
    _rows.remove(id);
    final file = File('${_dir!.path}/$id.json');
    if (file.existsSync()) file.deleteSync();
    notifyListeners();
  }

  Future<void> _persist(StoredFood stored) async {
    _rows[stored.id] = stored;
    final file = File('${_dir!.path}/${stored.id}.json');
    await writeJsonAtomic(file, stored.toJson());
    notifyListeners();
  }

  /// Re-point the on-disk state at the current `_rows`. Writes every entry
  /// first — each through `writeJsonAtomic`, which writes a `.tmp` sibling
  /// then renames it over the target, so a crash mid-rewrite leaves either
  /// the prior file or the fully written new one, never a partial or a
  /// wiped directory (which would silently lose unsynced pendingCreate
  /// entries). Only once the new state is durably on disk do we delete
  /// files for ids that no longer exist.
  ///
  /// Both passes isolate per-file failures so one bad row can't abort the
  /// rest. A row whose write throws is still added to `keep` so its prior
  /// file (left intact by the atomic write) isn't then deleted as an orphan
  /// — degrading to "this row keeps its last-good version" rather than
  /// losing it.
  Future<void> _rewriteAll() async {
    final dir = _dir;
    if (dir == null) return;
    final keep = <String>{};
    for (final stored in _rows.values) {
      final file = File('${dir.path}/${stored.id}.json');
      keep.add(file.path);
      try {
        await writeJsonAtomic(file, stored.toJson());
      } catch (e) {
        debugPrint('local_food_store: rewrite write failed ${file.path}: $e');
      }
    }
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (keep.contains(entity.path)) continue;
      try {
        await entity.delete();
      } catch (e) {
        debugPrint('local_food_store: orphan delete failed ${entity.path}: $e');
      }
    }
  }

  /// Crypto-strong v4 UUID. Avoids pulling in a dedicated `uuid`
  /// package — `Random.secure()` is enough.
  static String _newUuid() {
    final b = List<int>.generate(16, (_) => _rand.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int n) => n.toRadixString(16).padLeft(2, '0');
    final s = b.map(hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  @visibleForTesting
  void debugClear() {
    _rows.clear();
    notifyListeners();
  }
}
