import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists runs as JSON files on disk for offline-first sync.
///
/// Each run is stored as a separate file: `<run-id>.json`.
/// Unsynced runs have `"synced": false` in the JSON.
///
/// An in-progress run is stored separately as `in_progress.json` and is
/// rewritten every few seconds during a recording, so a crash mid-run can
/// be recovered on next launch.
class LocalRunStore extends ChangeNotifier {
  late Directory _dir;
  List<Run> _runs = [];
  final Set<String> _syncedIds = {};
  // Run ids whose cloud-side delete failed on the first attempt, mapped
  // to the user_id who queued the delete. The local copy was kept so the
  // UI stays consistent with the cloud; the SyncService drains this queue
  // on its usual triggers (foreground, connectivity-on, startup) and
  // removes ids on success. Persisted to its own sidecar so a crash mid-
  // retry doesn't lose the work item.
  //
  // The owner-tag (value) parallels the run owner-tag pattern (decisions
  // §67): on a shared device where User A queues a delete then signs
  // out and User B signs in, B's sync drain MUST skip A's pending
  // deletes — otherwise the queue retries A's deletes under B's session,
  // RLS rejects every one, and the queue gets stuck failing forever.
  // A null value means "untagged" (legacy entries from before owner-
  // tagging shipped, or queued while signed-out) — those drain under
  // whichever user is signed in next, matching the run adoption rule.
  final Map<String, String?> _pendingRemoteDeletes = {};

  /// Returns the currently-signed-in user id (or `null` for the
  /// "offline / not signed in" case). Set once at app bootstrap so
  /// every locally-saved run stamps `metadata.created_by_user_id` —
  /// the owner tag the SyncService consults during drain to keep
  /// User A's runs from accidentally syncing under User B's account
  /// on a shared device.
  ///
  /// Null by default — tests don't set it, so saved runs land
  /// without the stamp (treated as untagged / adoptable). Production
  /// wires `() => apiClient?.userId` in `main.dart`.
  ///
  /// See `docs/architecture/decisions.md § 67` for the owner-tag design.
  String? Function()? currentUserIdProvider;

  static const _inProgressFilename = 'in_progress.json';
  // Sidecar file listing the ids of runs that have synced to the cloud.
  // The per-run JSON used to carry a `synced` boolean and `markSynced`
  // read-decoded-re-encoded-rewrote the whole run file just to flip that
  // bool — for a 50-run offline backlog that was 50 full round-trips
  // through the filesystem + JSON codec. The sidecar is a few kilobytes,
  // written once per markSynced call (or once per batch).
  static const _syncedIdsFilename = 'synced_ids.json';
  static const _pendingRemoteDeletesFilename = 'pending_remote_deletes.json';

  File get _inProgressFile => File('${_dir.path}/$_inProgressFilename');
  File get _syncedIdsFile => File('${_dir.path}/$_syncedIdsFilename');
  File get _pendingRemoteDeletesFile =>
      File('${_dir.path}/$_pendingRemoteDeletesFilename');

  // Per-active-run waypoint cursor — how many waypoints of the
  // current in-progress run we've already persisted. Lets
  // saveInProgress append ONLY new waypoints since the last save
  // instead of re-encoding the whole track every tick. Persona-hunt
  // Round 3 finding Ultra #2: pre-fix a 50-hour 100-mile race
  // re-encoded + atomically rewrote the entire ~14 MB JSON every
  // 10 s — ~250 GB cumulative writes, battery + flash wear. Per-
  // tick cost is now O(new-waypoints) instead of O(total).
  int _inProgressWaypointsWritten = 0;
  String? _inProgressRunId;

  List<Run> get runs => List.unmodifiable(_runs);

  List<Run> get unsyncedRuns =>
      _runs.where((r) => !_syncedIds.contains(r.id)).toList();

  int get unsyncedCount => unsyncedRuns.length;

  /// Run ids that the user asked to delete but whose remote-side
  /// `api.deleteRun` failed (network error, RLS, transient 5xx). The
  /// SyncService retries these on the next sync trigger. Surfaced as
  /// an unmodifiable view so callers can't mutate the set directly —
  /// use [markPendingRemoteDelete] / [clearPendingRemoteDelete].
  ///
  /// Includes every queued id regardless of owner — use
  /// [pendingRemoteDeletesForUser] for the per-user drainable subset.
  Set<String> get pendingRemoteDeleteIds =>
      Set<String>.unmodifiable(_pendingRemoteDeletes.keys);

  /// Subset of [pendingRemoteDeleteIds] that the currently-signed-in
  /// [userId] is allowed to drain. A pending delete is drainable when:
  ///
  ///  * its owner tag matches [userId], OR
  ///  * its owner tag is null (untagged / legacy / queued while signed-
  ///    out — adopts to whoever is signed in next, mirroring the run
  ///    owner-adoption rule).
  ///
  /// Used by [SyncService._drainPendingDeletes] to keep User A's
  /// queued deletes from being attempted under User B's session on a
  /// shared device. See `docs/architecture/decisions.md § 67` for the parallel
  /// run owner-tag design.
  Set<String> pendingRemoteDeletesForUser(String? userId) {
    if (userId == null) return const <String>{};
    return _pendingRemoteDeletes.entries
        .where((e) => e.value == null || e.value == userId)
        .map((e) => e.key)
        .toSet();
  }

  /// The owner user_id stamped on a pending-delete entry, or null when
  /// the entry is untagged (legacy / queued-while-signed-out) or the id
  /// isn't in the queue. Exposed for tests that need to assert the tag.
  @visibleForTesting
  String? debugPendingRemoteDeleteOwner(String runId) =>
      _pendingRemoteDeletes[runId];

  /// Test-only seed that populates the in-memory list directly,
  /// bypassing `init()` + `_loadAll()` and their parallel async file
  /// reads. The `Future.wait` over `readAsString` in `_loadAll`
  /// interacts poorly with `flutter_test`'s fake-async zone for
  /// non-empty directories (RunsScreen widget tests hang for >10
  /// minutes — same root cause as the listSync revert). Tests that
  /// need a populated store call this instead. Production code never
  /// touches it.
  @visibleForTesting
  void debugSeed(Iterable<Run> runs, {Directory? dir, bool synced = true}) {
    if (dir != null) _dir = dir;
    _runs = List<Run>.from(runs);
    _runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (synced) {
      _syncedIds.addAll(_runs.map((r) => r.id));
    }
    notifyListeners();
  }

  /// Call once at startup. Pass [overrideDirectory] in tests to avoid the
  /// `path_provider` plugin channel — the store will write runs to the
  /// supplied directory instead of the platform documents dir.
  Future<void> init({Directory? overrideDirectory}) async {
    if (overrideDirectory != null) {
      _dir = overrideDirectory;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      _dir = Directory('${appDir.path}/runs');
    }
    if (!_dir.existsSync()) {
      _dir.createSync(recursive: true);
    }
    await _loadAll();
  }

  /// Save a freshly-recorded run locally. Stamps `last_modified_at` and marks
  /// it as unsynced.
  Future<void> save(Run run) async {
    Run stamped = _withLastModified(run, DateTime.now());
    // Owner-tag the run with the userId that was signed in at save
    // time. Prevents the cross-user contamination bug on a shared
    // device — when User A records a run, signs out, and User B
    // signs in, the run still carries A's tag and the SyncService
    // skips it during B's drain. See `docs/architecture/decisions.md § 67`.
    final ownerId = currentUserIdProvider?.call();
    if (ownerId != null && ownerId.isNotEmpty) {
      stamped = _withCreatedByUserId(stamped, ownerId);
    }
    final file = File('${_dir.path}/${stamped.id}.json');
    final data = {
      kLocalStoreVersionKey: kLocalStoreSchemaVersion,
      'run': stamped.toJson(),
      'synced': false,
    };
    await writeJsonAtomic(file, data);
    _runs.removeWhere((r) => r.id == stamped.id);
    _runs.insert(0, stamped);
    notifyListeners();
  }

  /// Return a copy of [run] with `metadata.created_by_user_id`
  /// stamped. Public so the SyncService can adopt previously-
  /// untagged runs onto a freshly-signed-in user.
  static Run withCreatedByUserId(Run run, String userId) =>
      _withCreatedByUserId(run, userId);

  static Run _withCreatedByUserId(Run run, String userId) {
    final metadata = Map<String, dynamic>.from(run.metadata ?? {});
    metadata[MetadataKeys.createdByUserId] = userId;
    return Run(
      id: run.id,
      startedAt: run.startedAt,
      duration: run.duration,
      distanceMetres: run.distanceMetres,
      track: run.track,
      routeId: run.routeId,
      source: run.source,
      externalId: run.externalId,
      metadata: metadata,
      createdAt: run.createdAt,
    );
  }

  /// Save a run that came from the backend. Marks it as already synced.
  ///
  /// Conflict resolution:
  /// - If a local copy already exists with a newer `last_modified_at`, the
  ///   remote copy is ignored. This prevents the cloud from clobbering local
  ///   edits that haven't been pushed yet.
  /// - Remote runs come back with an empty `track` (tracks are stored in
  ///   Storage and lazy-loaded). If the local copy already has the full track,
  ///   we preserve it so we don't drop GPS data when syncing.
  Future<void> saveFromRemote(Run run) async {
    final existing = _runs.where((r) => r.id == run.id).firstOrNull;
    if (existing != null) {
      final localTs = _lastModifiedOf(existing);
      final remoteTs = _lastModifiedOf(run);
      if (localTs.isAfter(remoteTs)) {
        // Local is newer — keep it.
        return;
      }
    }

    // Preserve the local track if the remote one is empty (tracks live in
    // Storage now and aren't returned by getRuns).
    final merged = (run.track.isEmpty && existing != null && existing.track.isNotEmpty)
        ? Run(
            id: run.id,
            startedAt: run.startedAt,
            duration: run.duration,
            distanceMetres: run.distanceMetres,
            track: existing.track,
            routeId: run.routeId,
            source: run.source,
            externalId: run.externalId,
            metadata: run.metadata,
            createdAt: run.createdAt,
          )
        : run;

    final file = File('${_dir.path}/${merged.id}.json');
    final data = {
      kLocalStoreVersionKey: kLocalStoreSchemaVersion,
      'run': merged.toJson(),
      'synced': true,
    };
    await writeJsonAtomic(file, data);
    _runs.removeWhere((r) => r.id == merged.id);
    _runs.insert(0, merged);
    _syncedIds.add(merged.id);
    _runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    notifyListeners();
  }

  /// Bulk variant of [saveFromRemote] used by the runs-screen pull-to-refresh
  /// path. A delta fetch can return up to 200 rows; calling [saveFromRemote]
  /// in a loop fired N file writes plus N `notifyListeners()` calls, each
  /// rebuilding the runs screen — a fresh user pulling for the first time
  /// rebuilt the screen 200 times. This variant batches all writes with
  /// `Future.wait`, then notifies listeners once at the end.
  Future<void> saveManyFromRemote(Iterable<Run> runs) async {
    if (runs.isEmpty) return;
    final toWrite = <Run>[];
    for (final run in runs) {
      final existing = _runs.where((r) => r.id == run.id).firstOrNull;
      if (existing != null) {
        final localTs = _lastModifiedOf(existing);
        final remoteTs = _lastModifiedOf(run);
        if (localTs.isAfter(remoteTs)) continue;
      }
      final merged = (run.track.isEmpty &&
              existing != null &&
              existing.track.isNotEmpty)
          ? Run(
              id: run.id,
              startedAt: run.startedAt,
              duration: run.duration,
              distanceMetres: run.distanceMetres,
              track: existing.track,
              routeId: run.routeId,
              source: run.source,
              externalId: run.externalId,
              metadata: run.metadata,
              createdAt: run.createdAt,
            )
          : run;
      toWrite.add(merged);
    }
    if (toWrite.isEmpty) return;
    await Future.wait(toWrite.map((merged) {
      final file = File('${_dir.path}/${merged.id}.json');
      final data = {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'run': merged.toJson(),
        'synced': true,
      };
      return writeJsonAtomic(file, data);
    }));
    for (final merged in toWrite) {
      _runs.removeWhere((r) => r.id == merged.id);
      _runs.insert(0, merged);
      _syncedIds.add(merged.id);
    }
    _runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    notifyListeners();
  }

  /// Whether a run with this id already exists locally.
  bool contains(String runId) => _runs.any((r) => r.id == runId);

  /// Replace an existing run with updated data (same id, new metadata).
  /// Stamps `last_modified_at = now` and marks the run unsynced so it gets
  /// pushed on the next sync.
  Future<void> update(Run updated) async {
    final file = File('${_dir.path}/${updated.id}.json');
    if (!file.existsSync()) return;

    final stamped = _withLastModified(updated, DateTime.now());
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    data[kLocalStoreVersionKey] = kLocalStoreSchemaVersion;
    data['run'] = stamped.toJson();
    data['synced'] = false;
    await writeJsonAtomic(file, data);

    final idx = _runs.indexWhere((r) => r.id == stamped.id);
    if (idx >= 0) _runs[idx] = stamped;
    _syncedIds.remove(stamped.id);
    notifyListeners();
  }

  Run _withLastModified(Run run, DateTime ts) {
    final metadata = Map<String, dynamic>.from(run.metadata ?? {});
    metadata[MetadataKeys.lastModifiedAt] = ts.toUtc().toIso8601String();
    return Run(
      id: run.id,
      startedAt: run.startedAt,
      duration: run.duration,
      distanceMetres: run.distanceMetres,
      track: run.track,
      routeId: run.routeId,
      source: run.source,
      externalId: run.externalId,
      metadata: metadata,
      createdAt: run.createdAt,
    );
  }

  static DateTime _lastModifiedOf(Run run) {
    final raw = run.metadata?[MetadataKeys.lastModifiedAt] as String?;
    if (raw != null) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    // Fall back to startedAt, NOT createdAt. `createdAt` is the server's
    // `created_at` insert timestamp — it's null for an offline run and,
    // for a synced run, reflects when the row first reached the server
    // rather than when the user last touched it, so it's ambiguous as a
    // modification clock. `startedAt` is the client's run-start instant:
    // stable, always present, and the same value on every device. Used
    // only for a legacy run that predates the metadata.last_modified_at
    // stamp; every save/update since stamps the key explicitly.
    return run.startedAt;
  }

  /// Delete a run from local storage.
  Future<void> delete(String runId) async {
    final file = File('${_dir.path}/$runId.json');
    if (file.existsSync()) {
      await file.delete();
    }
    _runs.removeWhere((r) => r.id == runId);
    _syncedIds.remove(runId);
    notifyListeners();
  }

  /// Delete a batch of runs in one shot. Removes each run's file from disk,
  /// updates the in-memory list, and notifies listeners exactly **once** at
  /// the end — so a bulk delete of N runs doesn't trigger N UI rebuilds.
  Future<void> deleteMany(Iterable<String> runIds) async {
    final ids = runIds.toSet();
    if (ids.isEmpty) return;
    for (final id in ids) {
      final file = File('${_dir.path}/$id.json');
      if (!file.existsSync()) continue;
      try {
        await file.delete();
      } catch (e) {
        debugPrint('Failed to delete run $id: $e');
      }
    }
    _runs.removeWhere((r) => ids.contains(r.id));
    _syncedIds.removeAll(ids);
    notifyListeners();
  }

  /// Persist the current state of an in-progress recording. Called
  /// periodically during a run so a crash or force-kill doesn't lose
  /// everything.
  ///
  /// Append-only NDJSON format (one record per line). First record
  /// after a clear writes a snapshot of the full run; subsequent
  /// records write only NEW waypoints since the last save plus an
  /// updated header. The loader concatenates waypoints in order and
  /// uses the LAST valid header. A corrupt trailing line (mid-write
  /// crash) is skipped — earlier lines still reconstruct a valid
  /// partial run. Persona-hunt Round 3 finding Ultra #2.
  Future<void> saveInProgress(Run run) async {
    final path = _inProgressFile.path;
    // Reset the cursor if the active run id changed OR the file is
    // gone (post-clearInProgress). A fresh write starts with the
    // full track + header.
    final isFreshRun = _inProgressRunId != run.id ||
        !File(path).existsSync();
    if (isFreshRun) {
      _inProgressRunId = run.id;
      _inProgressWaypointsWritten = 0;
    }
    final newSlice = run.track.length > _inProgressWaypointsWritten
        ? run.track.sublist(_inProgressWaypointsWritten)
        : const <Waypoint>[];

    // Build the header from Run.toJson() with track stripped — the
    // loader passes this back to Run.fromJson verbatim plus the
    // reconstructed track, so it must use the exact same wire shape.
    final header = Map<String, dynamic>.from(run.toJson())..remove('track');
    final record = {
      'h': header,
      'w': [for (final wp in newSlice) wp.toJson()],
      't': DateTime.now().toIso8601String(),
      if (isFreshRun) 'snap': true,
    };
    await compute(_appendInProgressLine, {'path': path, 'data': record});
    _inProgressWaypointsWritten = run.track.length;
  }

  /// Load an in-progress run left over from a previous session, if any.
  /// Returns null when there's nothing to recover.
  ///
  /// The read + JSON decode runs in a background isolate via [compute].
  /// For an ultra-length session (a 6 h+ run accumulates 20 k+ waypoints,
  /// which serialises to ~1.5+ MB of JSON) the decode alone was a 300-
  /// 500 ms UI stall on startup — long enough to push first-frame past
  /// the typical app-launch budget. Moving it off-isolate keeps the
  /// recovery transparent to the user. The final `Run.fromJson` call
  /// stays on the calling isolate because the Run object needs to
  /// cross back over anyway.
  Future<Run?> loadInProgress() async {
    final file = _inProgressFile;
    if (!file.existsSync()) return null;
    try {
      final data = await compute(_readInProgress, file.path);
      if (data == null) {
        // File existed but had no parseable record (truly corrupt
        // or empty). Delete so the next session doesn't keep
        // tripping over it — same contract the legacy single-blob
        // shape carried.
        try {
          await file.delete();
        } catch (_) {/* swallow */}
        return null;
      }
      // Restore the cursor so a save AFTER recovery writes
      // incrementally onto the existing file.
      _inProgressRunId = data['id'] as String?;
      final wps = data['waypoints'] as List<dynamic>? ?? const [];
      _inProgressWaypointsWritten = wps.length;
      return Run.fromJson({
        ...?(data['header'] as Map<String, dynamic>?),
        'track': wps,
      });
    } catch (e) {
      debugPrint('Failed to load in-progress run: $e');
      try {
        await file.delete();
      } catch (e2) {
        debugPrint('local_run_store: corrupt in-progress delete failed: $e2');
      }
      return null;
    }
  }

  /// Remove the in-progress save file. Called on successful [stop] and on
  /// successful recovery (after promoting the partial run into the list).
  Future<void> clearInProgress() async {
    // Drop the per-run cursor so a subsequent saveInProgress starts
    // a fresh file with a full snapshot. (Ultra #2 cursor reset.)
    _inProgressRunId = null;
    _inProgressWaypointsWritten = 0;
    final file = _inProgressFile;
    if (file.existsSync()) {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('Failed to delete in-progress run: $e');
      }
    }
  }

  /// Mark a run as synced. Writes only the small sidecar file; the run's
  /// own JSON is untouched. For sync loops that mark many runs at once,
  /// prefer [markManySynced] which writes the sidecar once per batch.
  Future<void> markSynced(String runId) async {
    _syncedIds.add(runId);
    await _persistSyncedIds();
    notifyListeners();
  }

  /// Mark several runs as synced and persist once — used by [SyncService]
  /// after a `saveRunsBatch` call so N successful runs produce a single
  /// sidecar write instead of N.
  Future<void> markManySynced(Iterable<String> runIds) async {
    if (runIds.isEmpty) return;
    _syncedIds.addAll(runIds);
    await _persistSyncedIds();
    notifyListeners();
  }

  Future<void> _persistSyncedIds() async {
    // Drop ids for runs that no longer exist locally — a run deleted
    // server-side (on another device / web) is never given a local
    // delete() call; it just stops arriving in the delta fetch, so its
    // id would otherwise linger in the sidecar forever and the on-disk
    // set would grow without bound. `unsyncedRuns` already intersects
    // with `_runs`, so the only effect of a stale id is sidecar bloat;
    // self-heal it on every write.
    final liveIds = _runs.map((r) => r.id).toSet();
    _syncedIds.retainWhere(liveIds.contains);
    try {
      await writeJsonAtomic(_syncedIdsFile, {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'ids': _syncedIds.toList(),
      });
    } catch (e) {
      // Not fatal — the in-memory set is still correct for the rest of
      // the session; we'll retry on the next sync event.
      debugPrint('Failed to persist synced ids sidecar: $e');
    }
  }

  /// Record that a run's remote-side delete failed and should be retried
  /// by the SyncService on the next sync trigger. Idempotent — repeated
  /// calls don't grow the queue. Notifies listeners so any visible
  /// "pending delete" badge can update without a separate channel.
  ///
  /// [ownerUserId] is stamped onto the queued entry so the drain path
  /// can skip foreign-owned deletes on a shared device. Pass the
  /// currently-signed-in user id at the time of failure; pass null
  /// when no user is signed in (legacy adoption — first signed-in
  /// user picks it up).
  Future<void> markPendingRemoteDelete(
    String runId, {
    String? ownerUserId,
  }) async {
    final existed = _pendingRemoteDeletes.containsKey(runId);
    final prevOwner = existed ? _pendingRemoteDeletes[runId] : null;
    if (existed && prevOwner == ownerUserId) return;
    _pendingRemoteDeletes[runId] = ownerUserId;
    await _persistPendingRemoteDeletes();
    notifyListeners();
  }

  /// Bulk variant for the runs_screen batch-delete path — folds N
  /// failures into a single sidecar write + single notify.
  Future<void> markManyPendingRemoteDelete(
    Iterable<String> runIds, {
    String? ownerUserId,
  }) async {
    var changed = false;
    for (final id in runIds) {
      final existed = _pendingRemoteDeletes.containsKey(id);
      final prevOwner = existed ? _pendingRemoteDeletes[id] : null;
      if (!existed || prevOwner != ownerUserId) {
        _pendingRemoteDeletes[id] = ownerUserId;
        changed = true;
      }
    }
    if (!changed) return;
    await _persistPendingRemoteDeletes();
    notifyListeners();
  }

  /// Drop a run id from the retry queue. Called by the SyncService
  /// after a successful retry, or by the user if they purge the
  /// orphan locally.
  Future<void> clearPendingRemoteDelete(String runId) async {
    // containsKey guard, not `remove() != null` — entries can have a
    // null value (untagged / legacy) and Map.remove returns the value,
    // which would silently skip the persistence + notify for those.
    if (!_pendingRemoteDeletes.containsKey(runId)) return;
    _pendingRemoteDeletes.remove(runId);
    await _persistPendingRemoteDeletes();
    notifyListeners();
  }

  Future<void> _persistPendingRemoteDeletes() async {
    try {
      if (_pendingRemoteDeletes.isEmpty &&
          _pendingRemoteDeletesFile.existsSync()) {
        await _pendingRemoteDeletesFile.delete();
        return;
      }
      // New format: {"deletes": {id: owner_user_id_or_null}}. Old
      // format ({"ids": [...]}) is still readable (see
      // _readPendingRemoteDeletes) for one-way migration from existing
      // installs — the next write upgrades them.
      await writeJsonAtomic(_pendingRemoteDeletesFile, {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'deletes': _pendingRemoteDeletes,
      });
    } catch (e) {
      debugPrint('Failed to persist pending_remote_deletes sidecar: $e');
    }
  }

  Future<Map<String, String?>?> _readPendingRemoteDeletes() async {
    final file = _pendingRemoteDeletesFile;
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      // Prefer the new tagged shape when present.
      if (data['deletes'] is Map) {
        final raw = data['deletes'] as Map;
        final out = <String, String?>{};
        for (final entry in raw.entries) {
          final key = entry.key as String;
          final value = entry.value;
          out[key] = value is String ? value : null;
        }
        return out;
      }
      // Legacy untagged shape: {"ids": [...]} — every entry adopts to
      // whichever user signs in next. The next write upgrades the file
      // to the tagged shape.
      if (data['ids'] is List) {
        final ids = (data['ids'] as List).cast<String>();
        return <String, String?>{for (final id in ids) id: null};
      }
      return null;
    } catch (e) {
      debugPrint('Failed to read pending_remote_deletes sidecar: $e');
      return null;
    }
  }

  Future<void> _loadAll() async {
    _runs = [];
    _syncedIds.clear();
    _pendingRemoteDeletes.clear();

    final pendingDeletes = await _readPendingRemoteDeletes();
    if (pendingDeletes != null) _pendingRemoteDeletes.addAll(pendingDeletes);

    // listSync is intentional: the async stream form (`_dir.list()`)
    // deadlocks inside `testWidgets` because the I/O isolate's reply
    // ports interact poorly with the test binding's fake-async zone
    // (RunsScreen widget tests hang for >10 min). The directory listing
    // is small (one file per run) and runs once at cold-start, before
    // first frame, so the sync call is bounded; the per-file reads that
    // follow are still async + parallel.
    final files = _dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .where((f) => !f.path.endsWith(_inProgressFilename))
        .where((f) => !f.path.endsWith(_syncedIdsFilename))
        .where((f) => !f.path.endsWith(_pendingRemoteDeletesFilename))
        .toList();

    // Read the sidecar first. If present, it's the authoritative source
    // of sync state — the per-run `synced` field is legacy and may be
    // stale (markSynced no longer rewrites the run file).
    Set<String>? sidecarIds = await _readSyncedIdsSidecar();

    // Read all run files in parallel. Sequential reads meant cold-start
    // scaled linearly with run count — a user with 500 runs would wait
    // seconds on the first frame. `Future.wait` lets the scheduler batch
    // the I/O while we decode whatever comes back.
    final loaded = await Future.wait(
      files.map(_readRunFile),
      eagerError: false,
    );
    for (final entry in loaded) {
      if (entry == null) continue;
      _runs.add(entry.run);
      if (sidecarIds != null) {
        if (sidecarIds.contains(entry.run.id)) _syncedIds.add(entry.run.id);
      } else if (entry.synced) {
        // Migration path: no sidecar yet, read the legacy per-file flag.
        _syncedIds.add(entry.run.id);
      }
    }

    // If we migrated from legacy per-file flags, write the sidecar now so
    // the next launch takes the fast path.
    if (sidecarIds == null && _syncedIds.isNotEmpty) {
      await _persistSyncedIds();
    }

    // Sort newest first
    _runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    notifyListeners();
  }

  Future<Set<String>?> _readSyncedIdsSidecar() async {
    final file = _syncedIdsFile;
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return (data['ids'] as List).cast<String>().toSet();
    } catch (e) {
      debugPrint('Failed to read synced_ids sidecar: $e');
      return null;
    }
  }

  Future<_LoadedRun?> _readRunFile(File file) async {
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      // Forward-migration hook: the `{run, synced}` envelope is v1 and
      // forward-compatible with the legacy unstamped (v0) shape, so the
      // read is a pass-through today. A future incompatible change bumps
      // kLocalStoreSchemaVersion and branches on this version.
      final version = localStoreRecordVersion(data);
      if (version > kLocalStoreSchemaVersion) {
        debugPrint(
            'local_run_store: ${file.path} has _v=$version (> $kLocalStoreSchemaVersion); reading known fields only');
      }
      final run = Run.fromJson(data['run'] as Map<String, dynamic>);
      return _LoadedRun(run, data['synced'] == true);
    } catch (e) {
      debugPrint('Failed to load run file ${file.path}: $e');
      return null;
    }
  }
}

class _LoadedRun {
  final Run run;
  final bool synced;
  const _LoadedRun(this.run, this.synced);
}

/// Append a single NDJSON record to the in-progress file. Open-
/// append-flush-close per call — durable across a crash mid-tick
/// because earlier lines have already been fsync'd. Persona-hunt
/// Round 3 finding Ultra #2.
Future<void> _appendInProgressLine(Map<String, dynamic> args) async {
  final path = args['path'] as String;
  final data = args['data'] as Map<String, dynamic>;
  final f = File(path);
  // FileMode.writeOnlyAppend creates the file if missing.
  final sink = f.openWrite(mode: FileMode.writeOnlyAppend);
  try {
    sink.writeln(jsonEncode(data));
    await sink.flush();
  } finally {
    await sink.close();
  }
}

/// Read the NDJSON in-progress file + reconstruct (header, waypoints).
/// Tolerates a trailing partial / corrupt line (mid-write crash).
/// Also handles the legacy single-blob shape (`{run: {...}, saved_at:
/// ...}`) for a user upgrading mid-run — first line parses as the
/// legacy envelope, the helper unwraps it.
Future<Map<String, dynamic>?> _readInProgress(String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;
  final raw = await file.readAsString();
  if (raw.isEmpty) return null;
  Map<String, dynamic>? header;
  final waypoints = <dynamic>[];
  String? lastRunId;
  for (final line in raw.split('\n')) {
    if (line.isEmpty) continue;
    try {
      final rec = jsonDecode(line) as Map<String, dynamic>;
      // Legacy single-blob envelope (user mid-upgrade)? The old
      // shape was {run: <Run.toJson>, saved_at: ...}. Unwrap to the
      // same (header, waypoints) split the NDJSON path produces.
      if (rec['run'] is Map<String, dynamic>) {
        final runMap = Map<String, dynamic>.from(
            rec['run'] as Map<String, dynamic>);
        final legacyTrack = runMap['track'] as List<dynamic>? ?? const [];
        runMap.remove('track');
        header = runMap;
        waypoints
          ..clear()
          ..addAll(legacyTrack);
        lastRunId = runMap['id'] as String?;
        continue;
      }
      // NDJSON chunk shape: {h: header, w: [waypoints]}.
      final h = rec['h'] as Map<String, dynamic>?;
      if (h != null) {
        header = h;
        lastRunId = h['id'] as String?;
      }
      final w = rec['w'] as List<dynamic>? ?? const [];
      if (rec['snap'] == true) {
        // A snap line resets the buffer — handles the "fresh file
        // after clear" case + any future explicit re-snap.
        waypoints.clear();
      }
      waypoints.addAll(w);
    } catch (_) {
      // Trailing partial line from a mid-write crash, or a corrupt
      // record. Skip and keep the prior reconstruction.
      continue;
    }
  }
  if (header == null) return null;
  return {
    'id': lastRunId,
    'header': header,
    'waypoints': waypoints,
  };
}
