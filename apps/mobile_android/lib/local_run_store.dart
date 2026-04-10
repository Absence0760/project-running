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

  /// Save a run locally. Marks it as unsynced.
  Future<void> save(Run run) async {
    final file = File('${_dir.path}/${run.id}.json');
    final data = {
      'run': run.toJson(),
      'synced': false,
    };
    await file.writeAsString(jsonEncode(data));
    _runs.insert(0, run);
    notifyListeners();
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
