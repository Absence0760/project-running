import 'dart:async';
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

/// True when [at] falls outside the half-open fetch window `[start, end)`.
///
/// A windowed [OfflineSyncStore.replaceFromServer]-style refresh may only prune
/// a synced row the fetch COULD have returned; a row outside the window is
/// absent because it was never asked for, not because the server deleted it.
/// This is the one place that decides which, because the half-open convention
/// is the whole contract: three stores carried the predicate — two byte for
/// byte, one open-coded with the `end` bound dropped — and a drift on any one
/// of them changes which synced rows a refresh is allowed to clobber, with
/// nothing in the tree comparing them.
///
/// A null [at] cannot be placed, so it is in-window and therefore eligible for
/// prune, which is what preserves the full-replace contract when both bounds
/// are null. Compares absolute instants, so a UTC timestamp and a local window
/// bound compare correctly.
bool outsideFetchWindow(DateTime? at, DateTime? start, DateTime? end) {
  if (at == null) return false;
  if (start != null && at.isBefore(start)) return true;
  if (end != null && !at.isBefore(end)) return true;
  return false;
}

/// Reads a `timestamptz` column off a row map as an absolute instant,
/// normalised to UTC.
///
/// The UTC step is the reason this is not a bare [DateTime.tryParse]:
/// `tryParse` answers with a LOCAL `DateTime` whenever the text carries no
/// zone designator, and every value read here is re-serialised through
/// `toIso8601String()`, which then writes no zone designator either. The next
/// reader re-anchors that wall clock in whatever zone it is in — Postgres
/// among them, since it resolves a zone-less literal in the session's own
/// TimeZone, so a stored crossing pushed from a device two hours east of UTC
/// would land two hours off.
///
/// NOT for a `date` column. `gear.purchased_at` / `gear.retired_at` are
/// `date`, whose zone-less text is a calendar DAY rather than an instant:
/// parsing it gives local midnight, and converting THAT to UTC moves the day
/// itself for every device west of Greenwich. [LocalGearStore] keeps its own
/// reader for that reason (decisions § 1289).
DateTime? parseServerTimestamp(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toUtc();
  return null;
}

/// The modification clock a stored record carries, or `now` when it carries
/// none this build can read.
///
/// Seven `fromJson` factories spelled this out, each casting the field with
/// `as String?` before parsing it. So an absent clock, an empty one and an
/// unparseable one all fell back to now, while a clock of the wrong TYPE threw
/// — and the load and restore paths both catch, so the whole record was
/// discarded instead. Nothing chose that: a record is not worth less than its
/// clock, and on the restore path the record came out of a backup archive
/// carrying work that exists nowhere else (decisions § 1290).
DateTime storedClockOrNow(dynamic v) =>
    parseServerTimestamp(v) ?? DateTime.now().toUtc();

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

  /// Last-known on-disk JSON per row id. Lets [rewriteAll] skip re-writing a
  /// row whose serialized content is byte-identical to what's already on disk
  /// (the overwhelmingly common pull-to-refresh case where the server returns
  /// the same rows) — turning a populated refresh from N forced fsync writes
  /// into 0. Populated on cold-load + every write; a skipped row keeps its
  /// existing file, so the crash-atomic write-before-prune contract is intact.
  final Map<String, String> _writtenJson = <String, String>{};

  /// Serialises every directory-mutating operation this store performs.
  ///
  /// Each public write below owns a whole directory transition: [persist]
  /// writes a row file then the index, [dropRow] removes a row file then
  /// rewrites the index, [rewriteAll] writes every row then prunes what is
  /// left, [clear] deletes every file outright, and [loadAll] rebuilds the
  /// resident state from what it finds. Every caller awaits its own call, but
  /// two callers over one store are ordinary — a screen firing a save
  /// unawaited, a connectivity return draining while the user edits, sign-out
  /// landing mid-save — and nothing ordered them against each other.
  ///
  /// Two measured interleavings. [clear] deletes EVERY file in the directory,
  /// including the `.tmp` sibling of an in-flight [persist], so that write's
  /// `rename` then failed with a `PathNotFoundException` naming a temp path
  /// its caller has never heard of. Worse, and silent: a delete that overtook
  /// an in-flight write to the same id renamed the row's file back into place
  /// AFTER the delete removed it, leaving `rowsById` saying the row was gone
  /// and the next cold-load resurrecting it — no exception anywhere.
  ///
  /// A whole-directory chain rather than a per-id lock, because [clear],
  /// [rewriteAll], [loadAll] and the index flush are directory-wide: per-id
  /// exclusion would still let each of them race a row write. Ordering costs
  /// nothing here — these are single small files, and every existing caller
  /// already awaited them one at a time.
  ///
  /// Keyed on the directory, NOT on the instance, because the interleaving
  /// that matters is between two instances: the sign-out wipe constructs a
  /// throwaway store per screen-owned type precisely because all instances of
  /// a type share one on-disk directory (`offline_store_wipe.dart`), so a
  /// per-instance chain would have left its [clear] free to race the live
  /// screen's write. `serialiseStoreWrite` holds that shape for the sibling
  /// file stores too (§ 828); a separate isolate is out of reach of any
  /// in-process lock, which is what `kAtomicOrphanMinAge` already allows for.
  String get _chainKey =>
      dir?.path ?? 'uninitialised:${identityHashCode(this)}';

  Future<T> _serialised<T>(Future<T> Function() body) =>
      serialiseStoreWrite(_chainKey, body);

  /// Test-only: a future that completes once every write queued so far has
  /// finished. A widget test whose UI signal is the in-memory row (which
  /// [persist] installs synchronously, before its file write) is otherwise
  /// free to tear its temp directory down under a write still in flight.
  ///
  /// Only awaitable when the write it waits on was queued from inside
  /// `tester.runAsync`; after a fake-zone tap, wait on an observable
  /// outcome with `pumpUntil` instead. The wait is bounded and reports
  /// itself rather than hanging when it is not (decisions § 1093).
  @visibleForTesting
  Future<void> debugWritesSettled() => storeWritesSettled(_chainKey);

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

  /// Count of rows not yet pushed to the server (creates, updates, and
  /// delete tombstones alike).
  int get pendingCount =>
      rowsById.values.where((e) => e.syncState != SyncState.synced).length;

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

  Future<void> loadAll() => _serialised(_loadAll);

  Future<void> _loadAll() async {
    rowsById.clear();
    _summaries.clear();
    _writtenJson.clear();
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
        // Baseline for the rewriteAll diff: the bytes actually on disk. If a
        // later rewrite's serialized form matches this, the write is skipped;
        // if the on-disk form was a drifted/older shape it won't match and the
        // row is rewritten (upgraded).
        _writtenJson[stored.id] = raw;
      } catch (e) {
        debugPrint('$debugLabel: corrupt row ${entity.path}: $e');
      }
    }

    sweepStoreScratchFiles(d, onError: (m) => debugPrint('$debugLabel: $m'));

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
      // unused store. Removing it was measured (decisions § 1196) and does not
      // merely cost that write: `_readIndex` short-circuits on a missing file,
      // so this is the ONLY real-async await a fresh empty store's `init()`
      // would carry, and a widget test that inits one outside
      // `tester.runAsync` then never completes it. That failure is a HANG, not
      // a teardown report — the store-write watch (§ 1129) speaks at teardown
      // and a test that never ends never reaches it.
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
    // Drain guard, mirroring SyncService._syncing. `session_detail_screen`
    // fires this unawaited and several screens drain on both a manual refresh
    // and a connectivity return, so two concurrent drains over one store are
    // reachable — they would push the same row twice and race each other's
    // state writes.
    if (_syncing) return 0;
    _syncing = true;
    try {
      var drained = 0;
      for (final stored in List<S>.from(rowsById.values)) {
        try {
          switch (stored.syncState) {
            case SyncState.pendingCreate:
              await pushCreate(api, stored);
              await markSynced(stored);
              drained++;
              break;
            case SyncState.pendingUpdate:
              await pushUpdate(api, stored);
              await markSynced(stored);
              drained++;
              break;
            case SyncState.pendingDelete:
              await pushDelete(api, stored);
              await dropIfUnchanged(stored);
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
    } finally {
      _syncing = false;
    }
  }

  bool _syncing = false;

  /// Flip [pushed] to `synced` — but only while it is still the resident copy.
  ///
  /// [syncWithServer] snapshots the rows, awaits a network push, then marks.
  /// Marking by id alone flipped WHATEVER was resident at that later moment,
  /// so an edit made during the push was recorded as synced and never sent;
  /// `replaceFromServer`'s newer-wins then preserved the local copy, leaving a
  /// divergence that is permanent and invisible on both sides. The
  /// delete-during-push variant was worse: it flipped the fresh tombstone to
  /// `synced`, so the server row survived with no local record that it should
  /// be gone.
  ///
  /// Entries are immutable and every mutation installs a new instance, so
  /// identity is an exact "did this row change under us" test. A false
  /// negative only costs one more drain.
  ///
  /// The test runs INSIDE the write chain, because [persist] only QUEUES:
  /// a screen's edit fired while the chain was busy — which is where the
  /// drain's own previous mark leaves it — had not yet installed its new
  /// instance when the check looked, so the check passed and the pre-push
  /// copy then landed on top of the edit, marked `synced`. That is the loss
  /// this guard exists to prevent, moved one step later and made permanent:
  /// a `synced` row is never pushed again, and `replaceFromServer`'s
  /// newer-wins keeps the local copy. `LocalRunStore.markSynced` had it
  /// inside its chain already.
  /// [serialiseStoreWrite] is re-entrant, so the [persist] inside runs INLINE
  /// rather than queueing behind the chain this already holds — which is what
  /// lets the decision and the write it implies be one step, without closing
  /// the subclass seam that lets a fake store persist nowhere.
  Future<void> markSynced(S pushed) async {
    await _serialised(() async {
      final existing = rowsById[pushed.id];
      if (existing == null) return;
      if (!identical(existing, pushed)) {
        debugPrint('$debugLabel: ${pushed.id} changed during its push — left '
            'pending for the next drain');
        return;
      }
      await persist(asSynced(existing));
    });
  }

  /// Drop [pushed] now that its server DELETE has returned — but only while
  /// it is still the resident copy, and decided inside the write chain for
  /// exactly the reason [markSynced] is. A row re-created during the push is
  /// a NEW local row that has never been sent, and dropping it deletes a row
  /// the runner is looking at.
  @protected
  Future<void> dropIfUnchanged(S pushed) async {
    await _serialised(() async {
      final existing = rowsById[pushed.id];
      if (existing == null) return;
      if (!identical(existing, pushed)) {
        debugPrint('$debugLabel: ${pushed.id} was replaced during its delete '
            'push — keeping the resident row');
        return;
      }
      await dropRow(pushed.id);
    });
  }

  /// Refuse a write on a store that was never [init]ed.
  ///
  /// [dir] is null only in that case, and every write path then dies on a bare
  /// `dir!` — an opaque "Null check operator used on a null value" that reads
  /// like a bug in the caller. Worse, the in-memory mutation happened first, so
  /// the row appeared in the list, the screen reported a failure over the top
  /// of it, and nothing was ever written to disk or drained to the server
  /// (`NutritionScreen` shipped in exactly that state). Raising here, BEFORE
  /// `rowsById` is touched, keeps the resident state honest: a write that
  /// cannot be durable leaves no trace that says it was.
  @protected
  void requireInitialised(String op) {
    if (dir != null) return;
    throw StateError(
        '$debugLabel: $op before init() — the store has no directory, so this '
        'write could never reach disk or the server');
  }

  Future<void> dropRow(String id) async {
    requireInitialised('dropRow');
    await _serialised(() => _dropRow(id));
  }

  Future<void> _dropRow(String id) async {
    rowsById.remove(id);
    _writtenJson.remove(id);
    final file = File('${dir!.path}/$id.json');
    if (file.existsSync()) file.deleteSync();
    if (_summaries.remove(id) != null) _indexDirty = true;
    await _persistIndex();
    notifyListeners();
  }

  Future<void> persist(S stored) async {
    requireInitialised('persist');
    return _serialised(() async {
      await _persistRow(stored);
      await _persistIndex();
      notifyListeners();
    });
  }

  /// Write a single row + reflect it in [_summaries] without flushing the
  /// index. Callers that persist a batch ([restoreFromBackup]) loop over this
  /// then flush once via [_persistIndex]. A tombstone leaves the index (it's
  /// not a live row) but still writes its on-disk file so the drain can push
  /// the server DELETE.
  Future<void> _persistRow(S stored) async {
    requireInitialised('persist');
    rowsById[stored.id] = stored;
    final file = File('${dir!.path}/${stored.id}.json');
    final json = stored.toJson();
    await writeJsonAtomic(file, json);
    _writtenJson[stored.id] = jsonEncode(json);
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
  ///
  /// Refuses on an uninitialised store like every other write path (§ 660).
  /// The callers are the subclasses' `replaceFromServer`, which have already
  /// rebuilt `rowsById` from the fetch by the time they get here, so each of
  /// them re-checks BEFORE that rebuild — a silent return here left the
  /// resident rows replaced and nothing on disk agreeing with them.
  Future<void> rewriteAll() async {
    requireInitialised('rewriteAll');
    await _serialised(_rewriteAll);
  }

  Future<void> _rewriteAll() async {
    final d = dir!;
    final keep = <String>{};
    for (final stored in rowsById.values) {
      final file = File('${d.path}/${stored.id}.json');
      keep.add(file.path); // keep regardless of whether we rewrite below
      final json = stored.toJson();
      final encoded = jsonEncode(json);
      // Skip the fsync when this row's serialized form is already on disk —
      // the common refresh case where the server returned identical rows. The
      // file is in `keep`, so the prune pass below won't touch it.
      if (_writtenJson[stored.id] == encoded) continue;
      try {
        await writeJsonAtomic(file, json);
        _writtenJson[stored.id] = encoded;
        rewriteAtomicWrites++;
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
        // And forget what that file held. The diff-skip above trusts
        // `_writtenJson` to say what is already on disk, so a row pruned here
        // and handed back UNCHANGED by a later fetch matched its own stale
        // entry and was never rewritten: resident, rendered, and absent from
        // disk until the next cold load dropped it.
        _writtenJson.remove(_idOfRowFile(entity.path));
      } catch (e) {
        debugPrint('$debugLabel: orphan delete failed ${entity.path}: $e');
      }
    }
    _rebuildSummaries();
    await _persistIndex();
  }

  /// The row id a `<id>.json` path carries.
  static String _idOfRowFile(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.endsWith('.json')
        ? name.substring(0, name.length - '.json'.length)
        : name;
  }

  /// Hydrate rows from a backup archive (the entry `toJson()` shape). Each is
  /// written as `pendingCreate` so [syncWithServer] pushes it once the user
  /// signs in. Additive + idempotent: an id already present is left untouched
  /// so re-running a restore can't clobber a locally-newer copy.
  Future<int> restoreFromBackup(
    List<Map<String, dynamic>> records, {
    bool generateNewIds = false,
  }) =>
      _serialised(() => _restoreFromBackup(records, generateNewIds));

  Future<int> _restoreFromBackup(
    List<Map<String, dynamic>> records,
    bool generateNewIds,
  ) async {
    var imported = 0;
    for (final json in records) {
      try {
        final record = generateNewIds ? _reKeyed(json) : json;
        if (record == null) {
          debugPrint('$debugLabel: restore refused a record it cannot re-key');
          continue;
        }
        final parsed = entryFromJson(record);
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

  /// Re-mint a restored record's id, so restoring SOMEONE ELSE's archive
  /// can't queue a create against a primary key that already exists. Returns
  /// null when the record's shape carries no id to re-mint — refusing is the
  /// only safe answer there, because a queued foreign id produces a
  /// `pendingCreate` whose INSERT can never succeed: `pushCreate` fails on the
  /// PK (or RLS), the failure is swallowed, `hasPending` never clears, and
  /// every refresh re-runs the drain forever with no backoff.
  ///
  /// Every subclass keeps its id at `row['id']` and serialises the same
  /// `{row, sync_state, last_modified_at}` envelope, so this is generic; a
  /// future entry shape that breaks that gets refused rather than corrupted.
  Map<String, dynamic>? _reKeyed(Map<String, dynamic> json) {
    final row = json['row'];
    if (row is! Map || row['id'] is! String) return null;
    return {
      ...json,
      'row': {...Map<String, dynamic>.from(row), 'id': newUuid()},
    };
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

  /// Test-only: count of per-row atomic writes [rewriteAll] has performed.
  /// The diff-before-write skip means a refresh that changes nothing leaves
  /// this flat — the regression guard for the write-amplification fix.
  @visibleForTesting
  int rewriteAtomicWrites = 0;

  /// Wipe this store's in-memory state AND its on-disk files. Called on
  /// sign-out so a different user signing in on the same device can't read
  /// (or re-sync under their own account) the prior user's rows — including
  /// unsynced `pendingCreate` rows, which `replaceFromServer` would otherwise
  /// preserve and `syncWithServer` would push into the new account. The
  /// per-user scoping the settings cache gets via keyed entries (decisions
  /// §72) isn't available here — these stores aren't user-namespaced on disk —
  /// so sign-out clears them outright. Idempotent; tolerates a per-file delete
  /// failure so one undeletable file can't strand the rest still on disk.
  Future<void> clear() => _serialised(_clear);

  Future<void> _clear() async {
    rowsById.clear();
    _summaries.clear();
    _writtenJson.clear();
    _indexDirty = false;
    final d = dir;
    if (d != null && d.existsSync()) {
      // Delete EVERY file, not just `*.json`. The store owns this directory
      // outright, and `writeStringAtomic` leaves a `<name>.json.<n>.tmp`
      // sibling behind whenever the process dies between its flush and its
      // rename — an orphan that every listing in this layer filters out, so it
      // survives sign-out carrying a full row (for LocalCrossingsStore, a bib
      // number and weigh-in fields). The contract here is "nothing of the
      // prior user survives", which a filename filter can only ever
      // approximate.
      for (final entity in d.listSync()) {
        if (entity is! File) continue;
        try {
          entity.deleteSync();
        } catch (e) {
          debugPrint('$debugLabel: clear failed to delete ${entity.path}: $e');
        }
      }
    }
    notifyListeners();
  }

  @visibleForTesting
  void debugClear() {
    rowsById.clear();
    _writtenJson.clear();
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
      final at = parseServerTimestamp(raw);
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
