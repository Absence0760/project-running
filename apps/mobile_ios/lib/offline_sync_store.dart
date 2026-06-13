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

  int _revision = 0;

  /// Monotonic counter bumped on every mutation (every [notifyListeners]).
  /// Subclasses cache derived views — a sorted list, an aggregate — keyed on
  /// this so a getter recomputes only after a change instead of on every
  /// read. The dashboard reads `workouts` / `rows` several times per build and
  /// rebuilds on unrelated store mutations, so an unkeyed re-sort of the whole
  /// history per access is the hot path this guards against.
  int get storeRevision => _revision;

  @override
  void notifyListeners() {
    _revision++;
    super.notifyListeners();
  }

  /// Compact on-disk summary index, keyed by row id. Each value is the
  /// [summaryOf] map for a live (non-tombstone) row. Kept in lockstep with
  /// [rowsById] in memory on every mutation (cheap, no disk); flushed once to
  /// `<storeSubdir>/index.json` via [_persistIndex] at the end of each mutation
  /// method (or batch). Cold-load reads this single file instead of N per-row
  /// files when the index's id-set matches the on-disk file id-set.
  final Map<String, Map<String, dynamic>> _summaries =
      <String, Map<String, dynamic>>{};

  /// Set when [_summaries] has drifted from what's on disk. Flushed (cleared)
  /// by [_persistIndex]; a pending flag at the end of a mutation method
  /// triggers exactly one index write per mutation.
  bool _indexDirty = false;

  static const _indexFilename = 'index.json';

  File get _indexFile => File('${dir!.path}/$_indexFilename');

  /// Subdirectory under the app-documents dir, e.g. `gear` / `gym` / `food`.
  String get storeSubdir;

  /// Prefix for this store's debug log lines, e.g. `local_gear_store`.
  String get debugLabel;

  /// Compact summary of [entry] for the on-disk index. MUST include `'id'`,
  /// `'sync_state'`, and (when [summaryTimestampKey] is non-null) the windowing
  /// timestamp. Subclasses add the few scalars their list / window surfaces
  /// read so the index can answer those without hydrating the full row.
  Map<String, dynamic> summaryOf(S entry);

  /// The key in [summaryOf]'s map carrying the ISO-8601 timestamp that
  /// [loadInWindow] / [estimateRowsInWindow] filter on. Null disables
  /// windowing (the index is then only a cold-load fast path).
  String? get summaryTimestampKey => null;

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
    _summaries.clear();
    _indexDirty = false;
    final d = dir;
    if (d == null) return;

    // Walk the per-row files. These stores expose full rows directly
    // (`rowsById` drives `workouts` / `rows` / `byId`), so unlike the windowed
    // LocalRunStore they always hydrate every row at cold-load. The index's
    // payoff here is (a) a cheap drift-validated summary view + (b) the
    // windowed `loadInWindow` / `estimateRowsInWindow` API that doesn't touch
    // the whole store.
    for (final entity in d.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (entity.path.endsWith(_indexFilename)) continue;
      try {
        final raw = entity.readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final stored = entryFromJson(migrateRecord(json, entity.path));
        rowsById[stored.id] = stored;
      } catch (e) {
        debugPrint('$debugLabel: corrupt row ${entity.path}: $e');
      }
    }

    // Reuse a valid, matching on-disk index for the summary view — its id-set
    // must equal the on-disk row-file id-set (membership only, no reads). A
    // missing / corrupt / drifted index (crash between a row write and the
    // index flush, a hand-planted / removed file) triggers a one-time rebuild
    // + persist: the post-crash self-heal and the first-launch migration.
    final liveRowIds = rowsById.values
        .where((e) => !e.isTombstone)
        .map((e) => e.id)
        .toSet();
    final index = await _readIndex();
    if (index != null &&
        index.keys.toSet().length == liveRowIds.length &&
        index.keys.toSet().containsAll(liveRowIds)) {
      _summaries.addAll(index);
    } else {
      _rebuildSummaries();
      // Skip writing an index for a fresh empty store (no rows AND no prior
      // index file) — there's nothing to cache, the rebuild-from-empty path is
      // O(0), and it avoids a pointless disk write on every cold-load of an
      // unused store. It also keeps widget tests that init an empty store
      // outside tester.runAsync from deadlocking the fake-async zone on the
      // index write (the first real createLocal flushes the index anyway).
      if (rowsById.isNotEmpty || _indexFile.existsSync()) {
        await _persistIndex();
      } else {
        _indexDirty = false;
      }
    }
    notifyListeners();
  }

  /// Rebuild [_summaries] from the resident [rowsById] (live rows only —
  /// tombstones never enter the index). Marks the index dirty.
  void _rebuildSummaries() {
    _summaries.clear();
    for (final entry in rowsById.values) {
      if (entry.isTombstone) continue;
      _summaries[entry.id] = summaryOf(entry);
    }
    _indexDirty = true;
  }

  /// Read + structurally validate the on-disk index. Returns a map keyed by id,
  /// or null on any error / structural invalidity (missing file, bad JSON,
  /// `summaries` absent or not a List, an element without a String `id`). A
  /// null return is a cache miss, never a crash.
  Future<Map<String, Map<String, dynamic>>?> _readIndex() async {
    final d = dir;
    if (d == null) return null;
    final file = _indexFile;
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final version = localStoreRecordVersion(data);
      if (version > kLocalStoreSchemaVersion) {
        debugPrint(
            '$debugLabel: index has _v=$version (> $kLocalStoreSchemaVersion); reading known fields only');
      }
      final summaries = data['summaries'];
      if (summaries is! List) return null;
      final out = <String, Map<String, dynamic>>{};
      for (final element in summaries) {
        if (element is! Map) return null;
        final summary = Map<String, dynamic>.from(element);
        final id = summary['id'];
        if (id is! String) return null;
        out[id] = summary;
      }
      return out;
    } catch (e) {
      debugPrint('$debugLabel: corrupt index, falling back to full walk: $e');
      return null;
    }
  }

  /// Flush [_summaries] to `index.json` when dirty. Self-heals by dropping any
  /// summary whose id is no longer resident before writing. A failed write is
  /// non-fatal — the in-memory index stays correct for the session and the next
  /// flush retries.
  Future<void> _persistIndex() async {
    // Only stores with a windowed surface persist the index — it's the backing
    // store for `loadInWindow` / `estimateRowsInWindow`. A store with no
    // windowing key (gear) reads its rows eagerly at cold-load and has no
    // window query, so an on-disk index would be dead weight; `summaryOf` still
    // exists for the in-memory summary view + any future opt-in.
    if (summaryTimestampKey == null) {
      _indexDirty = false;
      return;
    }
    if (!_indexDirty) return;
    final d = dir;
    if (d == null) return;
    final liveIds = rowsById.values
        .where((e) => !e.isTombstone)
        .map((e) => e.id)
        .toSet();
    _summaries.removeWhere((id, _) => !liveIds.contains(id));
    try {
      await writeJsonAtomic(_indexFile, {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'summaries': _summaries.values.toList(),
      });
      _indexDirty = false;
    } catch (e) {
      debugPrint('$debugLabel: failed to persist index: $e');
    }
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
    if (_summaries.remove(id) != null) _indexDirty = true;
    await _persistIndex();
    notifyListeners();
  }

  Future<void> persist(S stored) async {
    await _persistRow(stored);
    await _persistIndex();
    notifyListeners();
  }

  /// Write a single row + reflect it in [_summaries] without flushing the
  /// index. Callers that persist a batch ([restoreFromBackup]) loop over this
  /// then flush once via [_persistIndex]. A tombstone leaves the index (it's
  /// not a live row) but still writes its on-disk file so the drain can push
  /// the server DELETE.
  Future<void> _persistRow(S stored) async {
    rowsById[stored.id] = stored;
    final file = File('${dir!.path}/${stored.id}.json');
    await writeJsonAtomic(file, stored.toJson());
    if (stored.isTombstone) {
      if (_summaries.remove(stored.id) != null) _indexDirty = true;
    } else {
      _summaries[stored.id] = summaryOf(stored);
      _indexDirty = true;
    }
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
      if (entity.path.endsWith(_indexFilename)) continue;
      if (keep.contains(entity.path)) continue;
      try {
        await entity.delete();
      } catch (e) {
        debugPrint('$debugLabel: orphan delete failed ${entity.path}: $e');
      }
    }
    _rebuildSummaries();
    await _persistIndex();
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
        await _persistRow(asPendingCreate(parsed));
        imported++;
      } catch (e) {
        debugPrint('$debugLabel: restore skipped a record: $e');
      }
    }
    if (imported > 0) {
      await _persistIndex();
      notifyListeners();
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

  /// Read the on-disk index as a list of summary maps (newest the file's own
  /// order). Returns null on a missing / corrupt / structurally-invalid index.
  /// Test-only — production cold-load consumes the index via [loadAll].
  @visibleForTesting
  Future<List<Map<String, dynamic>>?> debugReadIndex() async {
    final index = await _readIndex();
    return index?.values.toList();
  }

  /// Load the full rows whose [summaryTimestampKey] timestamp falls in the
  /// half-open window `[from, to)`. Filters the in-memory index first, then
  /// hydrates only the matching ids from disk (their `<id>.json` files). Throws
  /// [StateError] when this store has no windowing timestamp.
  ///
  /// The single-day nutrition view uses this to replace its full-history scan.
  Future<List<S>> loadInWindow(DateTime from, DateTime to) async {
    final key = summaryTimestampKey;
    if (key == null) {
      throw StateError(
          '$debugLabel: loadInWindow requires a summaryTimestampKey');
    }
    final ids = _idsInWindow(key, from, to);
    final out = <S>[];
    for (final id in ids) {
      final resident = rowsById[id];
      if (resident != null) {
        if (!resident.isTombstone) out.add(resident);
        continue;
      }
      final hydrated = await _readRow(id);
      if (hydrated != null && !hydrated.isTombstone) out.add(hydrated);
    }
    return out;
  }

  /// Count the index rows whose timestamp falls in the half-open window
  /// `[from, to)` — without hydrating any full row. Throws [StateError] when
  /// this store has no windowing timestamp.
  Future<int> estimateRowsInWindow(DateTime from, DateTime to) async {
    final key = summaryTimestampKey;
    if (key == null) {
      throw StateError(
          '$debugLabel: estimateRowsInWindow requires a summaryTimestampKey');
    }
    return _idsInWindow(key, from, to).length;
  }

  List<String> _idsInWindow(String key, DateTime from, DateTime to) {
    final ids = <String>[];
    for (final summary in _summaries.values) {
      final raw = summary[key];
      final at = raw is String ? DateTime.tryParse(raw) : null;
      if (at == null) continue;
      if (!at.isBefore(from) && at.isBefore(to)) {
        ids.add(summary['id'] as String);
      }
    }
    return ids;
  }

  Future<S?> _readRow(String id) async {
    final file = File('${dir!.path}/$id.json');
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return entryFromJson(migrateRecord(json, file.path));
    } catch (e) {
      debugPrint('$debugLabel: corrupt row $id: $e');
      return null;
    }
  }
}
