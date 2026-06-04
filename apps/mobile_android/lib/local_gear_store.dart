import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Sync state for a single row. Mirrors the lifecycle of an offline
/// CRUD entry on the [GearScreen]: a freshly-created row is
/// `pendingCreate` until the INSERT succeeds; a retire / unretire /
/// rename / target-distance edit becomes `pendingUpdate`; a deleted
/// row is kept as a tombstone with `pendingDelete` until the server
/// DELETE returns 2xx.
enum GearSyncState { synced, pendingCreate, pendingUpdate, pendingDelete }

extension on GearSyncState {
  String get wire {
    switch (this) {
      case GearSyncState.synced:
        return 'synced';
      case GearSyncState.pendingCreate:
        return 'pending_create';
      case GearSyncState.pendingUpdate:
        return 'pending_update';
      case GearSyncState.pendingDelete:
        return 'pending_delete';
    }
  }
}

/// One stored row in the [LocalGearStore]. Holds the `gear_with_distance`
/// shape plus the sync-state tag. `total_distance_m` comes from the
/// server view; offline-created rows start at 0 and pick up the real
/// total on the next sync.
class StoredGear {
  StoredGear({
    required this.row,
    required this.syncState,
    DateTime? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.now().toUtc();

  final Map<String, dynamic> row;
  final GearSyncState syncState;
  final DateTime lastModifiedAt;

  String get id => row['id'] as String;
  bool get isTombstone => syncState == GearSyncState.pendingDelete;

  Map<String, dynamic> toJson() => {
        'row': row,
        'sync_state': syncState.wire,
        'last_modified_at': lastModifiedAt.toIso8601String(),
      };

  factory StoredGear.fromJson(Map<String, dynamic> json) => StoredGear(
        row: Map<String, dynamic>.from(json['row'] as Map),
        syncState: _fromWire(json['sync_state'] as String?),
        lastModifiedAt: DateTime.tryParse(
                json['last_modified_at'] as String? ?? '')
                ?.toUtc() ??
            DateTime.now().toUtc(),
      );

  static GearSyncState _fromWire(String? s) {
    switch (s) {
      case 'pending_create':
        return GearSyncState.pendingCreate;
      case 'pending_update':
        return GearSyncState.pendingUpdate;
      case 'pending_delete':
        return GearSyncState.pendingDelete;
      case 'synced':
      default:
        return GearSyncState.synced;
    }
  }
}

/// Disk-backed store for the user's gear inventory. Mirrors
/// [LocalRunStore]'s pattern: one JSON file per row under
/// `<appDocs>/gear/`, in-memory `ChangeNotifier` so screens refresh on
/// every mutation, sync drained on demand (sign-in, connectivity
/// return, manual pull-to-refresh).
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
class LocalGearStore extends ChangeNotifier {
  static final Random _rand = Random.secure();

  Directory? _dir;
  final Map<String, StoredGear> _rows = <String, StoredGear>{};

  /// Read-only snapshot of the live rows (excludes tombstones).
  List<Map<String, dynamic>> get rows => _rows.values
      .where((g) => !g.isTombstone)
      .map((g) => g.row)
      .toList();

  /// True when at least one row hasn't been pushed to the server.
  bool get hasPending =>
      _rows.values.any((g) => g.syncState != GearSyncState.synced);

  Future<void> init({Directory? overrideDirectory}) async {
    if (overrideDirectory != null) {
      _dir = overrideDirectory;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      _dir = Directory('${appDir.path}/gear');
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
        final stored = StoredGear.fromJson(json);
        _rows[stored.id] = stored;
      } catch (e) {
        debugPrint('local_gear_store: corrupt row ${entity.path}: $e');
      }
    }
    notifyListeners();
  }

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
    final id = _newUuid();
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
      syncState: GearSyncState.pendingCreate,
      lastModifiedAt: now,
    );
    await _persist(stored);
    return stored;
  }

  /// Patch an existing row. Preserves `pendingCreate` if the row hasn't
  /// been pushed yet — the next sync replays the full insert with the
  /// merged values.
  Future<void> updateLocal(String id, Map<String, dynamic> changes) async {
    final existing = _rows[id];
    if (existing == null) return;
    final next = Map<String, dynamic>.from(existing.row)..addAll(changes);
    final stored = StoredGear(
      row: next,
      syncState: existing.syncState == GearSyncState.pendingCreate
          ? GearSyncState.pendingCreate
          : GearSyncState.pendingUpdate,
    );
    await _persist(stored);
  }

  /// Stamp `retired_at` to today.
  Future<void> retireLocal(String id) async {
    await updateLocal(id, {
      'retired_at':
          DateTime.now().toUtc().toIso8601String().substring(0, 10),
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
    final existing = _rows[id];
    if (existing == null) return;
    if (existing.syncState == GearSyncState.pendingCreate) {
      _rows.remove(id);
      final file = File('${_dir!.path}/$id.json');
      if (file.existsSync()) file.deleteSync();
      notifyListeners();
      return;
    }
    final tombstone = StoredGear(
      row: existing.row,
      syncState: GearSyncState.pendingDelete,
    );
    await _persist(tombstone);
  }

  /// Replace the in-memory state from a fresh `gear_with_distance`
  /// fetch. Pending-* rows are preserved as-is — only rows in `synced`
  /// state are overwritten so an offline edit isn't clobbered by the
  /// server's older copy.
  Future<void> replaceFromServer(List<Map<String, dynamic>> serverRows) async {
    final preserved = <String, StoredGear>{};
    for (final entry in _rows.entries) {
      if (entry.value.syncState != GearSyncState.synced) {
        preserved[entry.key] = entry.value;
      }
    }
    _rows.clear();
    for (final row in serverRows) {
      final id = row['id'] as String;
      if (preserved.containsKey(id)) {
        _rows[id] = preserved.remove(id)!;
      } else {
        _rows[id] = StoredGear(row: row, syncState: GearSyncState.synced);
      }
    }
    _rows.addAll(preserved);
    await _rewriteAll();
    notifyListeners();
  }

  /// Push every pending row to the server. Returns the count of rows
  /// successfully drained — caller can surface a banner when ≥1.
  Future<int> syncWithServer(ApiClient api) async {
    var drained = 0;
    for (final stored in List<StoredGear>.from(_rows.values)) {
      try {
        switch (stored.syncState) {
          case GearSyncState.pendingCreate:
            await api.createGear(
              id: stored.id,
              kind: stored.row['kind'] as String,
              name: stored.row['name'] as String,
              brand: stored.row['brand'] as String?,
              model: stored.row['model'] as String?,
              purchasedAt: _parseDate(stored.row['purchased_at']),
              targetDistanceM:
                  (stored.row['target_distance_m'] as num?)?.toInt(),
              notes: stored.row['notes'] as String?,
            );
            await _markSynced(stored.id);
            drained++;
            break;
          case GearSyncState.pendingUpdate:
            await api.updateGear(
              stored.id,
              name: stored.row['name'] as String?,
              brand: stored.row['brand'] as String?,
              model: stored.row['model'] as String?,
              purchasedAt: _parseDate(stored.row['purchased_at']),
              retiredAt: _parseDate(stored.row['retired_at']),
              clearRetiredAt: stored.row['retired_at'] == null,
              targetDistanceM:
                  (stored.row['target_distance_m'] as num?)?.toInt(),
              notes: stored.row['notes'] as String?,
            );
            await _markSynced(stored.id);
            drained++;
            break;
          case GearSyncState.pendingDelete:
            await api.deleteGear(stored.id);
            await _dropRow(stored.id);
            drained++;
            break;
          case GearSyncState.synced:
            break;
        }
      } catch (e) {
        debugPrint('local_gear_store: sync failed for ${stored.id}: $e');
      }
    }
    return drained;
  }

  Future<void> _markSynced(String id) async {
    final existing = _rows[id];
    if (existing == null) return;
    // Preserve the modification clock — flipping to synced must NOT bump
    // lastModifiedAt to "now", or a subsequent newer-wins comparison would
    // treat a freshly-drained row as newer than the server copy it was just
    // pushed from. Mirrors the gym/food stores.
    final stored = StoredGear(
      row: existing.row,
      syncState: GearSyncState.synced,
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

  Future<void> _persist(StoredGear stored) async {
    _rows[stored.id] = stored;
    final file = File('${_dir!.path}/${stored.id}.json');
    await writeJsonAtomic(file, stored.toJson());
    notifyListeners();
  }

  /// Re-point the on-disk state at the current `_rows`. Writes every live
  /// row first (each atomic) so there is never a window where the
  /// directory is empty — a crash mid-rewrite leaves the prior files in
  /// place, not a wiped store. Only once the new state is durably on disk
  /// do we delete files for ids that no longer exist, each delete isolated
  /// so one failure can't abort the rest.
  Future<void> _rewriteAll() async {
    final dir = _dir;
    if (dir == null) return;
    final keep = <String>{};
    for (final stored in _rows.values) {
      final file = File('${dir.path}/${stored.id}.json');
      await writeJsonAtomic(file, stored.toJson());
      keep.add(file.path);
    }
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (keep.contains(entity.path)) continue;
      try {
        await entity.delete();
      } catch (e) {
        debugPrint('local_gear_store: orphan delete failed ${entity.path}: $e');
      }
    }
  }

  static DateTime? _parseDate(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
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

  /// The full stored entry (including its sync state + modification clock)
  /// for [id], or null. Test-only — production reads go through [rows].
  @visibleForTesting
  StoredGear? debugStored(String id) => _rows[id];
}
