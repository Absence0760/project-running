import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists routes as JSON files on disk.
class LocalRouteStore extends ChangeNotifier {
  late Directory _dir;
  List<Route> _routes = [];

  List<Route> get routes => List.unmodifiable(_routes);

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _dir = Directory('${appDir.path}/routes');
    if (!_dir.existsSync()) {
      _dir.createSync(recursive: true);
    }
    await _loadAll();
  }

  Future<void> save(Route route) async {
    final file = File('${_dir.path}/${route.id}.json');
    await file.writeAsString(jsonEncode(route.toJson()));
    _routes.removeWhere((r) => r.id == route.id);
    _routes.insert(0, route);
    notifyListeners();
  }

  Future<void> delete(String routeId) async {
    final file = File('${_dir.path}/$routeId.json');
    if (file.existsSync()) await file.delete();
    _routes.removeWhere((r) => r.id == routeId);
    notifyListeners();
  }

  Future<void> _loadAll() async {
    _routes = [];
    final files = _dir
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
