import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Sync state for a single offline-first row. Mirrors the lifecycle of an
/// offline CRUD entry: a freshly-created row is `pendingCreate` until the
/// INSERT succeeds; an edit becomes `pendingUpdate`; a deleted row is kept
/// as a tombstone with `pendingDelete` until the server DELETE returns 2xx.
///
/// Shared by the per-row stores (gear / gym / food) via the
/// `GearSyncState` / `GymSyncState` / `FoodSyncState` typedef aliases so the
/// store tests + screens keep their existing names.
enum SyncState { synced, pendingCreate, pendingUpdate, pendingDelete }

extension SyncStateWire on SyncState {
  String get wire {
    switch (this) {
      case SyncState.synced:
        return 'synced';
      case SyncState.pendingCreate:
        return 'pending_create';
      case SyncState.pendingUpdate:
        return 'pending_update';
      case SyncState.pendingDelete:
        return 'pending_delete';
    }
  }
}

SyncState syncStateFromWire(String? s) {
  switch (s) {
    case 'pending_create':
      return SyncState.pendingCreate;
    case 'pending_update':
      return SyncState.pendingUpdate;
    case 'pending_delete':
      return SyncState.pendingDelete;
    case 'synced':
    default:
      return SyncState.synced;
  }
}

/// The shape every per-row stored entry exposes to [OfflineSyncStore]. The
/// concrete stores ([StoredGear] / [StoredGymWorkout] / [StoredFood]) carry
/// their own typed fields on top of this.
abstract class SyncEntry {
  String get id;
  SyncState get syncState;
  DateTime get lastModifiedAt;
  bool get isTombstone;
  Map<String, dynamic> toJson();
}

/// Disk-backed per-row sync-state machine shared by the gear / gym / food
/// stores (decisions §73 + §122). One JSON file per row under
/// `<appDocs>/<storeSubdir>/`, an in-memory `ChangeNotifier` so screens
/// refresh on every mutation, and an on-demand drain (sign-in, connectivity
/// return, manual pull-to-refresh) in create → update → delete order.
///
/// Subclasses supply the entry type [S] and the four hooks: how to parse a
/// stored record off disk ([entryFromJson]), how to clone an entry into the
/// `synced` state without bumping its modification clock ([asSynced]), and
/// the three server-push calls ([pushCreate] / [pushUpdate] / [pushDelete]).
/// Everything else — the file IO, the crash-atomic `_rewriteAll`, the UUID
/// mint, the drain loop — lives here.
///
/// `LocalRunStore` / `LocalRouteStore` deliberately do NOT extend this: they
/// use a sidecar sync-state model keyed on a per-run clock, not the per-row
/// file model (decisions §122).
abstract class OfflineSyncStore<S extends SyncEntry> extends ChangeNotifier {
  static final Random _rand = Random.secure();

  Directory? dir;
  final Map<String, S> rowsById = <String, S>{};

  /// Subdirectory under the app-documents dir, e.g. `gear` / `gym` / `food`.
  String get storeSubdir;

  /// Prefix for this store's debug log lines, e.g. `local_gear_store`.
  String get debugLabel;

  /// Parse a stored record (the `{_v, row, sync_state, last_modified_at}`
  /// envelope plus any store-specific keys like gym's inline `sets`).
  S entryFromJson(Map<String, dynamic> json);

  /// Return a copy of [entry] in the `synced` state, preserving the
  /// modification clock (so a freshly-drained row doesn't read as newer than
  /// the server copy it was just pushed from).
  S asSynced(S entry);

  Future<void> pushCreate(ApiClient api, S entry);
  Future<void> pushUpdate(ApiClient api, S entry);
  Future<void> pushDelete(ApiClient api, S entry);

  /// True when at least one row hasn't been pushed to the server.
  bool get hasPending =>
      rowsById.values.any((e) => e.syncState != SyncState.synced);

  Future<void> init({Directory? overrideDirectory}) async {
    if (overrideDirectory != null) {
      dir = overrideDirectory;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      dir = Directory('${appDir.path}/$storeSubdir');
    }
    if (!dir!.existsSync()) {
      dir!.createSync(recursive: true);
    }
    await loadAll();
  }

  Future<void> loadAll() async {
    rowsById.clear();
    final d = dir;
    if (d == null) return;
    for (final entity in d.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = entity.readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final stored = entryFromJson(migrateRecord(json, entity.path));
        rowsById[stored.id] = stored;
      } catch (e) {
        debugPrint('$debugLabel: corrupt row ${entity.path}: $e');
      }
    }
    notifyListeners();
  }

  /// Forward-migration hook for a stored record read off disk. Resolves the
  /// `_v` schema stamp; the current shape (v1) is forward-compatible with the
  /// legacy unstamped shape (v0), so this is a pass-through today. A future
  /// incompatible change bumps [kLocalStoreSchemaVersion] and branches here.
  Map<String, dynamic> migrateRecord(Map<String, dynamic> json, String path) {
    final version = localStoreRecordVersion(json);
    if (version > kLocalStoreSchemaVersion) {
      debugPrint(
          '$debugLabel: record $path has _v=$version (> $kLocalStoreSchemaVersion); reading known fields only');
    }
    return json;
  }

  /// Push every pending row to the server in create → update → delete order
  /// (the natural `_rows` iteration is fine since each entry self-describes
  /// its state). Returns the count successfully drained — callers surface a
  /// banner when ≥1. Per-row failures are isolated: a failed push leaves the
  /// row in its pending state for the next drain.
  Future<int> syncWithServer(ApiClient api) async {
    var drained = 0;
    for (final stored in List<S>.from(rowsById.values)) {
      try {
        switch (stored.syncState) {
          case SyncState.pendingCreate:
            await pushCreate(api, stored);
            await markSynced(stored.id);
            drained++;
            break;
          case SyncState.pendingUpdate:
            await pushUpdate(api, stored);
            await markSynced(stored.id);
            drained++;
            break;
          case SyncState.pendingDelete:
            await pushDelete(api, stored);
            await dropRow(stored.id);
            drained++;
            break;
          case SyncState.synced:
            break;
        }
      } catch (e) {
        debugPrint('$debugLabel: sync failed for ${stored.id}: $e');
      }
    }
    return drained;
  }

  Future<void> markSynced(String id) async {
    final existing = rowsById[id];
    if (existing == null) return;
    await persist(asSynced(existing));
  }

  Future<void> dropRow(String id) async {
    rowsById.remove(id);
    final file = File('${dir!.path}/$id.json');
    if (file.existsSync()) file.deleteSync();
    notifyListeners();
  }

  Future<void> persist(S stored) async {
    rowsById[stored.id] = stored;
    final file = File('${dir!.path}/${stored.id}.json');
    await writeJsonAtomic(file, stored.toJson());
    notifyListeners();
  }

  /// Re-point the on-disk state at the current `rowsById`. Writes every row
  /// first — each through `writeJsonAtomic`, which writes a `.tmp` sibling
  /// then renames it over the target, so a crash mid-rewrite leaves either
  /// the prior file or the fully written new one, never a partial or a wiped
  /// directory (which would silently lose unsynced pendingCreate rows). Only
  /// once the new state is durably on disk do we delete files for ids that no
  /// longer exist. Both passes isolate per-file failures so one bad row can't
  /// abort the rest; a row whose write throws is still kept so its prior file
  /// (left intact by the atomic write) isn't then deleted as an orphan.
  Future<void> rewriteAll() async {
    final d = dir;
    if (d == null) return;
    final keep = <String>{};
    for (final stored in rowsById.values) {
      final file = File('${d.path}/${stored.id}.json');
      keep.add(file.path);
      try {
        await writeJsonAtomic(file, stored.toJson());
      } catch (e) {
        debugPrint('$debugLabel: rewrite write failed ${file.path}: $e');
      }
    }
    for (final entity in d.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (keep.contains(entity.path)) continue;
      try {
        await entity.delete();
      } catch (e) {
        debugPrint('$debugLabel: orphan delete failed ${entity.path}: $e');
      }
    }
  }

  /// Hydrate rows from a backup archive (the entry `toJson()` shape). Each is
  /// written as `pendingCreate` so [syncWithServer] pushes it once the user
  /// signs in. Additive + idempotent: an id already present is left untouched
  /// so re-running a restore can't clobber a locally-newer copy.
  Future<int> restoreFromBackup(List<Map<String, dynamic>> records) async {
    var imported = 0;
    for (final json in records) {
      try {
        final parsed = entryFromJson(json);
        if (rowsById.containsKey(parsed.id)) continue;
        await persist(asPendingCreate(parsed));
        imported++;
      } catch (e) {
        debugPrint('$debugLabel: restore skipped a record: $e');
      }
    }
    return imported;
  }

  /// Return a copy of [entry] forced into `pendingCreate`, preserving its
  /// modification clock. Used by [restoreFromBackup].
  S asPendingCreate(S entry);

  /// Crypto-strong v4 UUID. Avoids a dedicated `uuid` dep — `Random.secure()`
  /// is enough. The local id becomes the server id once the INSERT succeeds.
  static String newUuid() {
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
    rowsById.clear();
    notifyListeners();
  }

  /// The full stored entry (including sync state + modification clock) for
  /// [id], or null. Test-only — production reads go through the store's typed
  /// getters.
  @visibleForTesting
  S? debugStored(String id) => rowsById[id];
}
