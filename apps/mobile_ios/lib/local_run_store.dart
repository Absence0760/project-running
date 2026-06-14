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
  // The authoritative full-history projection — one lightweight RunSummary per
  // run on disk, newest-first, kept in lockstep with the per-run files. Unlike
  // `_runs` (which becomes a resident window) `_summaries` always holds every
  // row, so cold-load reads ONE index file instead of N, all-time consumers
  // see the whole history via `summaryRuns`, and the windowing of `_runs` never
  // shrinks the set the sync drain / filters work over. Persisted to
  // `index.json` (batched, atomic) as a cache of the per-run files — never the
  // sole source of truth (a missing / drifted index self-heals from the files).
  List<RunSummary> _summaries = [];
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
  // Compact on-disk projection of every run (one RunSummary each). Read first
  // on cold-load so a large history doesn't pay N file decodes up front.
  static const _indexFilename = 'index.json';

  File get _inProgressFile => File('${_dir.path}/$_inProgressFilename');
  File get _syncedIdsFile => File('${_dir.path}/$_syncedIdsFilename');
  File get _pendingRemoteDeletesFile =>
      File('${_dir.path}/$_pendingRemoteDeletesFilename');
  File get _indexFile => File('${_dir.path}/$_indexFilename');

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

  /// The full-history lightweight index (every row, newest-first). Filters /
  /// sorts that need the whole set read this instead of [runs] (which becomes a
  /// resident window). Carries scalars only — no track.
  List<RunSummary> get summaries => List.unmodifiable(_summaries);

  /// Full history as track-less [Run]s rebuilt from [summaries]. The seam every
  /// all-time consumer (fitness, mileage, goals, gear backfill, period summary,
  /// recap, intensity) reads so it keeps whole-history correctness without the
  /// store holding every full [Run] resident. Anything needing a track must
  /// hydrate the real run via [runById].
  List<Run> get summaryRuns => [for (final s in _summaries) s.toRun()];

  // Unsynced runs are ALWAYS resident in `_runs` (the residency invariant:
  // window ∪ unsynced), and they carry their GPS track — which the sync drain
  // uploads — so this reads the full Runs from `_runs`, never the track-less
  // summaries. Correctness after windowing rests on that invariant; the
  // architecture guards pin it.
  List<Run> get unsyncedRuns =>
      _runs.where((r) => !_syncedIds.contains(r.id)).toList();

  int get unsyncedCount => unsyncedRuns.length;

  /// Default count of newest full [Run]s held resident once the store windows.
  /// The resident set is this newest slice UNION all unsynced runs (which must
  /// always be reachable for the sync drain — see [unsyncedRuns]).
  static const int kResidentWindow = 200;

  /// Effective resident-window size for cold-load hydration. Overridable in
  /// tests so the windowing behaviour can be exercised without seeding hundreds
  /// of run files.
  @visibleForTesting
  int residentWindow = kResidentWindow;

  /// The newest [count] resident runs ∪ all unsynced, newest-first. The History
  /// timeline + run-list feed read this rather than [summaries] when they need
  /// full [Run]s (not just scalars). Identical to [runs] until the store
  /// windows; afterwards it's an explicit, sized view.
  List<Run> recentWindow([int count = kResidentWindow]) {
    // Sort by date first — `save` inserts a new run at the front assuming it's
    // the newest, which a manual back-dated add-run can violate, so `_runs`
    // insertion order isn't a reliable date order.
    final sorted = [..._runs]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final out = sorted.take(count).toList();
    final ids = out.map((r) => r.id).toSet();
    for (final r in sorted) {
      if (!_syncedIds.contains(r.id) && ids.add(r.id)) out.add(r);
    }
    out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return out;
  }

  /// Resolve a full [Run] (with track + complete metadata) by id: a resident
  /// copy if present, else hydrated from its on-disk file, else null when the id
  /// isn't in the index at all. The on-demand hydration path every detail /
  /// nav surface uses so it works for a run outside the resident window.
  Future<Run?> runById(String id) async {
    for (final r in _runs) {
      if (r.id == id) return r;
    }
    if (!_summaries.any((s) => s.id == id)) return null;
    final loaded = await _readRunFile(File('${_dir.path}/$id.json'));
    return loaded?.run;
  }

  /// Hydrate the next [count] oldest not-yet-resident runs (by index order)
  /// into [_runs] from disk, returning how many were added. The run-list's
  /// "load more" calls this to extend the window before falling back to a cloud
  /// fetch. A no-op (returns 0) while every row is already resident.
  Future<int> hydrateOlder(int count) async {
    if (count <= 0) return 0;
    final residentIds = _runs.map((r) => r.id).toSet();
    final missing = _summaries
        .where((s) => !residentIds.contains(s.id))
        .take(count)
        .map((s) => s.id)
        .toList();
    if (missing.isEmpty) return 0;
    final loaded = await Future.wait(
      missing.map((id) => _readRunFile(File('${_dir.path}/$id.json'))),
      eagerError: false,
    );
    var added = 0;
    for (final entry in loaded) {
      if (entry == null) continue;
      _runs.add(entry.run);
      added++;
    }
    if (added > 0) {
      _runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      notifyListeners();
    }
    return added;
  }

  /// Lazily yield every run on disk (full [Run]s with tracks), newest-first by
  /// the index order, without buffering the whole history in memory. Backs the
  /// backup export, which must include the complete history — including unsynced
  /// runs whose track lives only in the local file.
  Stream<Run> iterateAllRuns() async* {
    for (final s in _summaries) {
      final run = await runById(s.id);
      if (run != null) yield run;
    }
  }

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
    _summaries = [
      for (final r in _runs)
        RunSummary.fromRun(r, synced: _syncedIds.contains(r.id)),
    ];
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
    _upsertSummary(stamped, synced: false, atFront: true);
    await _persistIndex();
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
    // Newer-wins must also catch a synced run that's been windowed out of
    // `_runs` — its summary still carries the modification clock. Without this,
    // a delta fetch would silently clobber a locally-newer out-of-window edit.
    final existingSummary = existing == null
        ? _summaries.where((s) => s.id == run.id).firstOrNull
        : null;
    final localTs = existing != null
        ? _lastModifiedOf(existing)
        : (existingSummary != null
            ? _lastModifiedOf(existingSummary.toRun())
            : null);
    if (localTs != null && localTs.isAfter(_lastModifiedOf(run))) {
      // Local is newer — keep it.
      return;
    }

    // Preserve the local track if the remote one is empty (tracks live in
    // Storage now and aren't returned by getRuns). The resident copy has it in
    // memory; an out-of-window copy is hydrated from disk.
    Run? existingFull = existing;
    if (run.track.isEmpty && existingFull == null && existingSummary != null) {
      existingFull = await runById(run.id);
    }
    final merged = (run.track.isEmpty &&
            existingFull != null &&
            existingFull.track.isNotEmpty)
        ? Run(
            id: run.id,
            startedAt: run.startedAt,
            duration: run.duration,
            distanceMetres: run.distanceMetres,
            track: existingFull.track,
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
    _upsertSummary(merged, synced: true);
    _sortSummaries();
    await _persistIndex();
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
      // Newer-wins also against an out-of-window synced run via its summary
      // clock; preserve a local track by hydrating the evicted copy from disk.
      final existingSummary = existing == null
          ? _summaries.where((s) => s.id == run.id).firstOrNull
          : null;
      final localTs = existing != null
          ? _lastModifiedOf(existing)
          : (existingSummary != null
              ? _lastModifiedOf(existingSummary.toRun())
              : null);
      if (localTs != null && localTs.isAfter(_lastModifiedOf(run))) continue;
      Run? existingFull = existing;
      if (run.track.isEmpty && existingFull == null && existingSummary != null) {
        existingFull = await runById(run.id);
      }
      final merged = (run.track.isEmpty &&
              existingFull != null &&
              existingFull.track.isNotEmpty)
          ? Run(
              id: run.id,
              startedAt: run.startedAt,
              duration: run.duration,
              distanceMetres: run.distanceMetres,
              track: existingFull.track,
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
      _upsertSummary(merged, synced: true);
    }
    _runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _sortSummaries();
    await _persistIndex();
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
    _upsertSummary(stamped, synced: false);
    await _persistIndex();
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
    _summaries.removeWhere((s) => s.id == runId);
    _syncedIds.remove(runId);
    await _persistIndex();
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
    _summaries.removeWhere((s) => ids.contains(s.id));
    _syncedIds.removeAll(ids);
    await _persistIndex();
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
    _markSummariesSynced({runId});
    await _persistSyncedIds();
    notifyListeners();
  }

  /// Mark several runs as synced and persist once — used by [SyncService]
  /// after a `saveRunsBatch` call so N successful runs produce a single
  /// sidecar write instead of N.
  Future<void> markManySynced(Iterable<String> runIds) async {
    if (runIds.isEmpty) return;
    final ids = runIds.toSet();
    _syncedIds.addAll(ids);
    _markSummariesSynced(ids);
    await _persistSyncedIds();
    notifyListeners();
  }

  Future<void> _persistSyncedIds() async {
    // Drop ids for runs that no longer exist locally — a run deleted
    // server-side (on another device / web) is never given a local
    // delete() call; it just stops arriving in the delta fetch, so its
    // id would otherwise linger in the sidecar forever and the on-disk
    // set would grow without bound.
    //
    // Prune against `_summaries` (the full track-less projection of EVERY
    // local row), NOT `_runs` (the resident window of newest-N ∪ unsynced).
    // delete()/deleteMany() drop the summary together with the file, so a
    // missing summary is exactly "no local file". Using `_runs` would drop
    // the sidecar id of any SYNCED run outside the resident window, so the
    // next cold load re-classifies it as unsynced (residency invariant) and
    // re-uploads its full track on the next drain.
    final liveIds = _summaries.map((s) => s.id).toSet();
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

  /// Insert or replace [run]'s summary, keeping `_summaries` in lockstep with
  /// the per-run files. [atFront] mirrors `_runs.insert(0, …)` for a freshly
  /// recorded run; otherwise the caller re-sorts via [_sortSummaries].
  void _upsertSummary(Run run, {required bool synced, bool atFront = false}) {
    _summaries.removeWhere((s) => s.id == run.id);
    final summary = RunSummary.fromRun(run, synced: synced);
    if (atFront) {
      _summaries.insert(0, summary);
    } else {
      _summaries.add(summary);
    }
  }

  void _sortSummaries() =>
      _summaries.sort((a, b) => b.startedAt.compareTo(a.startedAt));

  /// Flip the in-memory `synced` flag on the matching summaries. Does NOT
  /// persist the index — `markSynced` already writes the authoritative
  /// `synced_ids` sidecar, and cold-load reconciles the index's flag against
  /// it, so writing the index here would be a redundant second disk write on
  /// the hot sync-drain path (the index's `synced` is a cache of a cache).
  void _markSummariesSynced(Set<String> ids) {
    for (var i = 0; i < _summaries.length; i++) {
      final s = _summaries[i];
      if (ids.contains(s.id) && !s.synced) _summaries[i] = s.withSynced(true);
    }
  }

  /// Serialise `_summaries` (with `synced` refreshed from the authoritative
  /// sidecar) to `index.json` atomically. Batched — every mutation method calls
  /// this once at its end, never per-row. Non-fatal on failure: the in-memory
  /// set stays correct and cold-load self-heals the disk copy from the per-run
  /// files next launch.
  Future<void> _persistIndex() async {
    try {
      await writeJsonAtomic(_indexFile, {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'summaries': [
          for (final s in _summaries)
            s.withSynced(_syncedIds.contains(s.id)).toIndexJson(),
        ],
      });
    } catch (e) {
      debugPrint('local_run_store: failed to persist index: $e');
    }
  }

  /// Read `index.json` into `RunSummary`s, or null when the file is absent,
  /// unparseable, or structurally invalid (missing / non-list `summaries`).
  /// Never throws — a bad index is a cache miss that triggers a full-walk
  /// rebuild, never a cold-load crash.
  Future<List<RunSummary>?> _readIndex() async {
    final file = _indexFile;
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final version = localStoreRecordVersion(data);
      if (version > kLocalStoreSchemaVersion) {
        debugPrint(
            'local_run_store: index _v=$version (> $kLocalStoreSchemaVersion); reading known fields only');
      }
      final list = data['summaries'];
      if (list is! List) return null;
      return [
        for (final e in list)
          if (e is Map<String, dynamic>) RunSummary.fromIndexJson(e),
      ];
    } catch (e) {
      debugPrint('local_run_store: failed to read index: $e');
      return null;
    }
  }

  /// Test-only: read the on-disk index back so a test can assert it was
  /// maintained without depending on the cold-load fast path.
  @visibleForTesting
  Future<List<RunSummary>?> debugReadIndex() => _readIndex();

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
    _summaries = [];
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
        .where((f) => !f.path.endsWith(_indexFilename))
        .toList();
    final fileById = {for (final f in files) _runIdFromPath(f.path): f};

    // Read the sidecar first. If present, it's the authoritative source
    // of sync state — the per-run `synced` field is legacy and may be
    // stale (markSynced no longer rewrites the run file).
    final Set<String>? sidecarIds = await _readSyncedIdsSidecar();
    final index = await _readIndex();

    // Fast path: a valid index whose id-set matches the on-disk run files
    // (membership only — names, no reads). Load `_summaries` from the index
    // (ONE file) and hydrate only the resident window — the whole point of the
    // windowed store. A missing / corrupt / drifted index (crash between a run
    // write and the index flush, a hand-planted / removed file) falls through
    // to the full-walk rebuild below: the post-crash self-heal + first-launch
    // migration.
    final indexMatches = index != null &&
        index.length == fileById.length &&
        index.every((s) => fileById.containsKey(s.id));
    if (indexMatches) {
      // Determine the authoritative synced set FIRST: the sidecar when present
      // (markSynced writes the sidecar, not the index, so the index's per-row
      // `synced` flag can lag), else fall back to the index's own flag.
      if (sidecarIds != null) {
        _syncedIds.addAll(sidecarIds.where(fileById.containsKey));
      } else {
        for (final s in index) {
          if (s.synced) _syncedIds.add(s.id);
        }
      }
      // Reconcile each summary's `synced` against that authoritative set so the
      // in-memory index never serves a stale flag (the on-disk flag is repaired
      // on the next mutation's index write).
      _summaries = [
        for (final s in index) s.withSynced(_syncedIds.contains(s.id)),
      ];
      _sortSummaries();
      // Residency invariant: newest [kResidentWindow] by date ∪ ALL unsynced
      // (unsynced runs carry their track + must always be drainable by sync).
      final residentIds = <String>{};
      for (final s in _summaries.take(residentWindow)) {
        residentIds.add(s.id);
      }
      for (final s in _summaries) {
        if (!_syncedIds.contains(s.id)) residentIds.add(s.id);
      }
      final loaded = await Future.wait(
        residentIds.map((id) => _readRunFile(fileById[id]!)),
        eagerError: false,
      );
      for (final entry in loaded) {
        if (entry != null) _runs.add(entry.run);
      }
      _runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      if (sidecarIds == null && _syncedIds.isNotEmpty) {
        await _persistSyncedIds();
      }
      notifyListeners();
      return;
    }

    // Slow path (self-heal / migration): read every run file in parallel,
    // rebuild `_summaries`, and persist the index so the next cold-start takes
    // the fast path. `_runs` holds the full set for this one session (the read
    // is already paid); the next launch windows it. `Future.wait` keeps the
    // cold-start parallel rather than O(n) sequential.
    final loaded = await Future.wait(files.map(_readRunFile), eagerError: false);
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

    if (sidecarIds == null && _syncedIds.isNotEmpty) {
      await _persistSyncedIds();
    }

    _runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _summaries = [
      for (final r in _runs)
        RunSummary.fromRun(r, synced: _syncedIds.contains(r.id)),
    ];
    // Skip the write for a brand-new empty store (no runs AND no prior index).
    if (_runs.isNotEmpty || _indexFile.existsSync()) {
      await _persistIndex();
    }
    notifyListeners();
  }

  /// Extract a run id from its `<id>.json` file path. Run files are named for
  /// their (UUID) id, which never contains a path separator or `.json`.
  static String _runIdFromPath(String path) {
    final name = path.split('/').last;
    return name.endsWith('.json')
        ? name.substring(0, name.length - '.json'.length)
        : name;
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
