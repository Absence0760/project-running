import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists routes as JSON files on disk.
class LocalRouteStore extends ChangeNotifier {
  /// Nullable so a save / saveBatch / delete that races ahead of
  /// `init()` can throw a meaningful StateError instead of
  /// LateInitializationError, and so a missed-init can be recovered
  /// from via `_ensureDir()` rather than blowing up downstream UI.
  Directory? _dir;
  List<Route> _routes = [];

  List<Route> get routes => List.unmodifiable(_routes);

  /// Test-only seed that populates the in-memory list directly,
  /// bypassing `init()` + `_loadAll()`. Mirrors `LocalRunStore.debugSeed`
  /// — same flutter_test fake-async hazard. Production code never
  /// touches it.
  @visibleForTesting
  void debugSeed(Iterable<Route> routes, {Directory? dir}) {
    if (dir != null) _dir = dir;
    _routes = List<Route>.from(routes);
    notifyListeners();
  }

  Future<void> init({Directory? overrideDirectory}) async {
    final Directory dir;
    if (overrideDirectory != null) {
      dir = overrideDirectory;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      dir = Directory('${appDir.path}/routes');
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _dir = dir;
    await _loadAll();
  }

  /// Recover from a missed / failed init() by lazily creating the
  /// directory. Without this, a routeStore that booted before
  /// `getApplicationDocumentsDirectory()` was ready (rare, but
  /// observed in field reports) would throw LateInitializationError
  /// on the first save and stay broken until app relaunch.
  Future<Directory> _ensureDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/routes');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<void> save(Route route) async {
    final dir = await _ensureDir();
    final file = File('${dir.path}/${route.id}.json');
    await file.writeAsString(jsonEncode(route.toJson()));
    _routes.removeWhere((r) => r.id == route.id);
    _routes.insert(0, route);
    notifyListeners();
  }

  /// Bulk variant of [save] — writes every file in parallel and only
  /// notifies once. Used by the routes screen's remote-sync path so a
  /// 100-route pull doesn't fire 100 listener callbacks (each rebuilding
  /// the list).
  Future<void> saveBatch(Iterable<Route> routes) async {
    if (routes.isEmpty) return;
    final list = routes.toList();
    final dir = await _ensureDir();
    await Future.wait(list.map((route) {
      final file = File('${dir.path}/${route.id}.json');
      return file.writeAsString(jsonEncode(route.toJson()));
    }));
    for (final route in list) {
      _routes.removeWhere((r) => r.id == route.id);
      _routes.insert(0, route);
    }
    notifyListeners();
  }

  Future<void> delete(String routeId) async {
    final dir = await _ensureDir();
    final file = File('${dir.path}/$routeId.json');
    if (file.existsSync()) await file.delete();
    _routes.removeWhere((r) => r.id == routeId);
    notifyListeners();
  }

  Future<void> _loadAll() async {
    _routes = [];
    final dir = _dir;
    if (dir == null) return; // init() not yet completed — nothing to load.
    // listSync is intentional — see LocalRunStore._loadAll for the
    // explanation (async _dir.list() deadlocks under `testWidgets`).
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    // Read all files in parallel — cold-start is bounded by the slowest
    // single read, not the sum of them. Same pattern as LocalRunStore.
    final loaded = await Future.wait(
      files.map(_readRouteFile),
      eagerError: false,
    );
    for (final route in loaded) {
      if (route != null) _routes.add(route);
    }
    notifyListeners();
  }

  Future<Route?> _readRouteFile(File file) async {
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return Route.fromJson(data);
    } catch (e) {
      debugPrint('Failed to load route file ${file.path}: $e');
      return null;
    }
  }
}
