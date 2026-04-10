import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists runs as JSON files on disk for offline-first sync.
///
/// Each run is stored as a separate file: `<run-id>.json`.
/// Unsynced runs have `"synced": false` in the JSON.
class LocalRunStore extends ChangeNotifier {
  late Directory _dir;
  List<Run> _runs = [];
  final Set<String> _syncedIds = {};

  List<Run> get runs => List.unmodifiable(_runs);

  List<Run> get unsyncedRuns =>
      _runs.where((r) => !_syncedIds.contains(r.id)).toList();

  int get unsyncedCount => _runs.length - _syncedIds.length;

  /// Call once at startup.
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _dir = Directory('${appDir.path}/runs');
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
    metadata['last_modified_at'] = ts.toIso8601String();
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

  /// Mark a run as synced.
  Future<void> markSynced(String runId) async {
    final file = File('${_dir.path}/$runId.json');
    if (!file.existsSync()) return;

    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    data['synced'] = true;
    await file.writeAsString(jsonEncode(data));
    _syncedIds.add(runId);
    notifyListeners();
  }

  Future<void> _loadAll() async {
    _runs = [];
    _syncedIds.clear();

    final files = _dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    for (final file in files) {
      try {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final run = Run.fromJson(data['run'] as Map<String, dynamic>);
        _runs.add(run);
        if (data['synced'] == true) {
          _syncedIds.add(run.id);
        }
      } catch (e) {
        debugPrint('Failed to load run file ${file.path}: $e');
      }
    }

    // Sort newest first
    _runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    notifyListeners();
  }
}
