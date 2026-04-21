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

  static const _inProgressFilename = 'in_progress.json';
  // Sidecar file listing the ids of runs that have synced to the cloud.
  // The per-run JSON used to carry a `synced` boolean and `markSynced`
  // read-decoded-re-encoded-rewrote the whole run file just to flip that
  // bool — for a 50-run offline backlog that was 50 full round-trips
  // through the filesystem + JSON codec. The sidecar is a few kilobytes,
  // written once per markSynced call (or once per batch).
  static const _syncedIdsFilename = 'synced_ids.json';

  File get _inProgressFile => File('${_dir.path}/$_inProgressFilename');
  File get _syncedIdsFile => File('${_dir.path}/$_syncedIdsFilename');

  List<Run> get runs => List.unmodifiable(_runs);

  List<Run> get unsyncedRuns =>
      _runs.where((r) => !_syncedIds.contains(r.id)).toList();

  int get unsyncedCount => _runs.length - _syncedIds.length;

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
    final stamped = _withLastModified(run, DateTime.now());
    final file = File('${_dir.path}/${stamped.id}.json');
    final data = {
      'run': stamped.toJson(),
      'synced': false,
    };
    await file.writeAsString(jsonEncode(data));
    _runs.removeWhere((r) => r.id == stamped.id);
    _runs.insert(0, stamped);
    notifyListeners();
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
      'run': merged.toJson(),
      'synced': true,
    };
    await file.writeAsString(jsonEncode(data));
    _runs.removeWhere((r) => r.id == merged.id);
    _runs.insert(0, merged);
    _syncedIds.add(merged.id);
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
    data['run'] = stamped.toJson();
    data['synced'] = false;
    await file.writeAsString(jsonEncode(data));

    final idx = _runs.indexWhere((r) => r.id == stamped.id);
    if (idx >= 0) _runs[idx] = stamped;
    _syncedIds.remove(stamped.id);
    notifyListeners();
  }

  Run _withLastModified(Run run, DateTime ts) {
    final metadata = Map<String, dynamic>.from(run.metadata ?? {});
    metadata['last_modified_at'] = ts.toUtc().toIso8601String();
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
    final raw = run.metadata?['last_modified_at'] as String?;
    if (raw != null) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return run.createdAt ?? run.startedAt;
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
  /// everything. The encode + write runs on a background isolate via
  /// [compute] — for a long run the track grows to thousands of waypoints
  /// and a sync encode on the UI thread jank-spikes every 10 seconds.
  Future<void> saveInProgress(Run run) async {
    final path = _inProgressFile.path;
    final payload = {
      'run': run.toJson(),
      'saved_at': DateTime.now().toIso8601String(),
    };
    await compute(_encodeAndWriteJson, {'path': path, 'data': payload});
  }

  /// Load an in-progress run left over from a previous session, if any.
  /// Returns null when there's nothing to recover.
  Future<Run?> loadInProgress() async {
    final file = _inProgressFile;
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return Run.fromJson(data['run'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Failed to load in-progress run: $e');
      // Corrupt file — remove it so we don't keep tripping over it.
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }
  }

  /// Remove the in-progress save file. Called on successful [stop] and on
  /// successful recovery (after promoting the partial run into the list).
  Future<void> clearInProgress() async {
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
    try {
      await _syncedIdsFile.writeAsString(jsonEncode({
        'ids': _syncedIds.toList(),
      }));
    } catch (e) {
      // Not fatal — the in-memory set is still correct for the rest of
      // the session; we'll retry on the next sync event.
      debugPrint('Failed to persist synced ids sidecar: $e');
    }
  }

  Future<void> _loadAll() async {
    _runs = [];
    _syncedIds.clear();

    final files = _dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .where((f) => !f.path.endsWith(_inProgressFilename))
        .where((f) => !f.path.endsWith(_syncedIdsFilename))
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

/// Top-level helper invoked via [compute] so the heavy `jsonEncode` +
/// blocking file write for a growing-track in-progress save doesn't run on
/// the UI isolate. Keep it top-level so it can be serialised across the
/// isolate boundary.
Future<void> _encodeAndWriteJson(Map<String, dynamic> args) async {
  final path = args['path'] as String;
  final data = args['data'] as Map<String, dynamic>;
  await File(path).writeAsString(jsonEncode(data));
}
