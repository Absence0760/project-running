import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-watch store for runs recorded while offline or not yet synced to
/// Supabase. Keyed by run id so a retry that already partially succeeded
/// can't duplicate. SharedPreferences backed — small dataset, one watch,
/// fine until we grow past "dogfoodable".
class LocalRunStore {
  static const _prefsKey = 'watch_wear.unsynced_runs';

  final Map<String, Run> _runs = {};
  SharedPreferences? _prefs;

  List<Run> get unsynced => List.unmodifiable(_runs.values);
  int get unsyncedCount => _runs.length;

  bool contains(String id) => _runs.containsKey(id);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getStringList(_prefsKey) ?? [];
    _runs.clear();
    for (final s in raw) {
      final run = Run.fromJson(jsonDecode(s) as Map<String, dynamic>);
      _runs[run.id] = run;
    }
  }

  Future<void> save(Run run) async {
    _runs[run.id] = run;
    await _persist();
  }

  Future<void> remove(String id) async {
    _runs.remove(id);
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final encoded = _runs.values.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(_prefsKey, encoded);
  }
}
