import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Sync state for a single gym workout. Mirrors [GearSyncState]: a
/// freshly-logged workout is `pendingCreate` until the INSERT succeeds;
/// a title / set-list edit becomes `pendingUpdate`; a deleted workout is
/// kept as a tombstone with `pendingDelete` until the server DELETE
/// returns 2xx.
enum GymSyncState { synced, pendingCreate, pendingUpdate, pendingDelete }

extension on GymSyncState {
  String get wire {
    switch (this) {
      case GymSyncState.synced:
        return 'synced';
      case GymSyncState.pendingCreate:
        return 'pending_create';
      case GymSyncState.pendingUpdate:
        return 'pending_update';
      case GymSyncState.pendingDelete:
        return 'pending_delete';
    }
  }
}

/// One stored workout in the [LocalGymStore]. Holds the `gym_workouts`
/// row shape plus the workout's sets inline (the composer always edits
/// the whole set list, so they travel together) and the sync-state tag.
/// Sets are positional — `set_index` is the list index, assigned on the
/// eventual INSERT.
class StoredGymWorkout {
  StoredGymWorkout({
    required this.row,
    required this.sets,
    required this.syncState,
    DateTime? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.now().toUtc();

  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> sets;
  final GymSyncState syncState;
  final DateTime lastModifiedAt;

  String get id => row['id'] as String;
  bool get isTombstone => syncState == GymSyncState.pendingDelete;

  DateTime? get startedAt {
    final v = row['started_at'];
    return v is String ? DateTime.tryParse(v) : null;
  }

  Map<String, dynamic> toJson() => {
        'row': row,
        'sets': sets,
        'sync_state': syncState.wire,
        'last_modified_at': lastModifiedAt.toIso8601String(),
      };

  factory StoredGymWorkout.fromJson(Map<String, dynamic> json) =>
      StoredGymWorkout(
        row: Map<String, dynamic>.from(json['row'] as Map),
        sets: ((json['sets'] as List?) ?? const [])
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList(),
        syncState: _fromWire(json['sync_state'] as String?),
        lastModifiedAt:
            DateTime.tryParse(json['last_modified_at'] as String? ?? '')
                    ?.toUtc() ??
                DateTime.now().toUtc(),
      );

  static GymSyncState _fromWire(String? s) {
    switch (s) {
      case 'pending_create':
        return GymSyncState.pendingCreate;
      case 'pending_update':
        return GymSyncState.pendingUpdate;
      case 'pending_delete':
        return GymSyncState.pendingDelete;
      case 'synced':
      default:
        return GymSyncState.synced;
    }
  }
}

/// Disk-backed store for the user's gym workouts. Mirrors
/// [LocalGearStore] (decisions §73): one JSON file per workout under
/// `<appDocs>/gym/`, in-memory `ChangeNotifier` so screens refresh on
/// every mutation, sync drained on demand (sign-in, connectivity
/// return, manual pull-to-refresh).
///
/// Offline contract:
/// - `createLocal` mints a v4 UUID (the client value becomes the server
///   id — `gym_workouts.id` defaults to gen_random_uuid() but accepts a
///   client value, so no temp-id reconciliation is needed), marks the
///   workout pendingCreate, and stores its sets inline.
/// - `updateLocal` patches workout fields and/or replaces the set list
///   while preserving pendingCreate (a workout created offline that's
///   edited offline stays pendingCreate; the eventual INSERT carries the
///   latest values + sets).
/// - `deleteLocal` on a synced workout writes a tombstone; on a workout
///   that was only ever local (pendingCreate) it just drops the file.
/// - `syncWithServer(api)` drains every non-synced workout in the order
///   create → update → delete. Failures leave the workout in its pending
///   state for the next drain.
class LocalGymStore extends ChangeNotifier {
  static final Random _rand = Random.secure();

  Directory? _dir;
  final Map<String, StoredGymWorkout> _rows = <String, StoredGymWorkout>{};

  /// Live workouts (excludes tombstones), newest-started first.
  List<StoredGymWorkout> get workouts {
    final live = _rows.values.where((w) => !w.isTombstone).toList();
    live.sort((a, b) {
      final at = a.startedAt;
      final bt = b.startedAt;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
    return live;
  }

  /// A single live workout by id, or null if missing / a tombstone.
  StoredGymWorkout? byId(String id) {
    final w = _rows[id];
    return (w == null || w.isTombstone) ? null : w;
  }

  /// True when at least one workout hasn't been pushed to the server.
  bool get hasPending =>
      _rows.values.any((w) => w.syncState != GymSyncState.synced);

  Future<void> init({Directory? overrideDirectory}) async {
    if (overrideDirectory != null) {
      _dir = overrideDirectory;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      _dir = Directory('${appDir.path}/gym');
    }
    if (!_dir!.existsSync()) {
      _dir!.createSync(recursive: true);
    }
    await _loadAll();
  }

  Future<void> _loadAll() async {
    _rows.clear();
    final dir = _dir;
    if (dir == null) return;
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = entity.readAsStringSync();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final stored = StoredGymWorkout.fromJson(json);
        _rows[stored.id] = stored;
      } catch (e) {
        debugPrint('local_gym_store: corrupt row ${entity.path}: $e');
      }
    }
    notifyListeners();
  }

  /// Mint a new UUID and persist a pending-create workout. Returns the
  /// stored shape so the caller can render it immediately.
  Future<StoredGymWorkout> createLocal({
    String? title,
    required DateTime startedAt,
    int? durationS,
    String? notes,
    bool isPublic = false,
    List<GymSetInput> sets = const [],
  }) async {
    final id = _newUuid();
    final now = DateTime.now().toUtc();
    final row = <String, dynamic>{
      'id': id,
      'title': title,
      'started_at': startedAt.toUtc().toIso8601String(),
      'duration_s': durationS,
      'notes': notes,
      'is_public': isPublic,
      'external_id': null,
      'last_modified_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    };
    final stored = StoredGymWorkout(
      row: row,
      sets: _setsToMaps(sets),
      syncState: GymSyncState.pendingCreate,
      lastModifiedAt: now,
    );
    await _persist(stored);
    return stored;
  }

  /// Patch an existing workout's fields and/or replace its sets. Preserves
  /// `pendingCreate` if the workout hasn't been pushed yet — the next sync
  /// replays the full insert with the merged values + sets.
  Future<void> updateLocal(
    String id, {
    String? title,
    int? durationS,
    String? notes,
    bool? isPublic,
    List<GymSetInput>? sets,
  }) async {
    final existing = _rows[id];
    if (existing == null) return;
    final now = DateTime.now().toUtc();
    final next = Map<String, dynamic>.from(existing.row);
    if (title != null) next['title'] = title;
    if (durationS != null) next['duration_s'] = durationS;
    if (notes != null) next['notes'] = notes;
    if (isPublic != null) next['is_public'] = isPublic;
    next['last_modified_at'] = now.toIso8601String();
    final stored = StoredGymWorkout(
      row: next,
      sets: sets != null ? _setsToMaps(sets) : existing.sets,
      syncState: existing.syncState == GymSyncState.pendingCreate
          ? GymSyncState.pendingCreate
          : GymSyncState.pendingUpdate,
      lastModifiedAt: now,
    );
    await _persist(stored);
  }

  /// Delete a workout. A workout that was only ever local (pendingCreate)
  /// disappears immediately; a synced or pendingUpdate workout becomes a
  /// pendingDelete tombstone so the next sync issues the server DELETE.
  Future<void> deleteLocal(String id) async {
    final existing = _rows[id];
    if (existing == null) return;
    if (existing.syncState == GymSyncState.pendingCreate) {
      _rows.remove(id);
      final file = File('${_dir!.path}/$id.json');
      if (file.existsSync()) file.deleteSync();
      notifyListeners();
      return;
    }
    final tombstone = StoredGymWorkout(
      row: existing.row,
      sets: existing.sets,
      syncState: GymSyncState.pendingDelete,
    );
    await _persist(tombstone);
  }

  /// Replace the in-memory state from a fresh server fetch (workout rows
  /// each paired with their sets). Pending-* workouts are preserved as-is
  /// — only `synced` rows are overwritten so an offline edit isn't
  /// clobbered by the server's older copy.
  Future<void> replaceFromServer(
    List<({Map<String, dynamic> workout, List<Map<String, dynamic>> sets})>
        serverWorkouts,
  ) async {
    final preserved = <String, StoredGymWorkout>{};
    for (final entry in _rows.entries) {
      if (entry.value.syncState != GymSyncState.synced) {
        preserved[entry.key] = entry.value;
      }
    }
    _rows.clear();
    for (final w in serverWorkouts) {
      final id = w.workout['id'] as String;
      if (preserved.containsKey(id)) {
        _rows[id] = preserved.remove(id)!;
      } else {
        _rows[id] = StoredGymWorkout(
          row: w.workout,
          sets: w.sets
              .map((s) => Map<String, dynamic>.from(s))
              .toList(),
          syncState: GymSyncState.synced,
        );
      }
    }
    _rows.addAll(preserved);
    await _rewriteAll();
    notifyListeners();
  }

  /// Push every pending workout to the server. Returns the count of
  /// workouts successfully drained — caller can surface a banner when ≥1.
  Future<int> syncWithServer(ApiClient api) async {
    var drained = 0;
    for (final stored in List<StoredGymWorkout>.from(_rows.values)) {
      try {
        switch (stored.syncState) {
          case GymSyncState.pendingCreate:
            await api.createGymWorkout(
              id: stored.id,
              title: stored.row['title'] as String?,
              startedAt: stored.startedAt ?? DateTime.now().toUtc(),
              durationS: (stored.row['duration_s'] as num?)?.toInt(),
              notes: stored.row['notes'] as String?,
              isPublic: (stored.row['is_public'] as bool?) ?? false,
              lastModifiedAt: stored.lastModifiedAt,
              sets: _mapsToSets(stored.sets),
            );
            await _markSynced(stored.id);
            drained++;
            break;
          case GymSyncState.pendingUpdate:
            await api.updateGymWorkout(
              stored.id,
              title: stored.row['title'] as String?,
              durationS: (stored.row['duration_s'] as num?)?.toInt(),
              notes: stored.row['notes'] as String?,
              isPublic: (stored.row['is_public'] as bool?) ?? false,
              lastModifiedAt: stored.lastModifiedAt,
              sets: _mapsToSets(stored.sets),
            );
            await _markSynced(stored.id);
            drained++;
            break;
          case GymSyncState.pendingDelete:
            await api.deleteGymWorkout(stored.id);
            await _dropRow(stored.id);
            drained++;
            break;
          case GymSyncState.synced:
            break;
        }
      } catch (e) {
        debugPrint('local_gym_store: sync failed for ${stored.id}: $e');
      }
    }
    return drained;
  }

  Future<void> _markSynced(String id) async {
    final existing = _rows[id];
    if (existing == null) return;
    final stored = StoredGymWorkout(
      row: existing.row,
      sets: existing.sets,
      syncState: GymSyncState.synced,
      lastModifiedAt: existing.lastModifiedAt,
    );
    await _persist(stored);
  }

  Future<void> _dropRow(String id) async {
    _rows.remove(id);
    final file = File('${_dir!.path}/$id.json');
    if (file.existsSync()) file.deleteSync();
    notifyListeners();
  }

  Future<void> _persist(StoredGymWorkout stored) async {
    _rows[stored.id] = stored;
    final file = File('${_dir!.path}/${stored.id}.json');
    await writeJsonAtomic(file, stored.toJson());
    notifyListeners();
  }

  /// Re-point the on-disk state at the current `_rows`. Writes every
  /// workout first — each through `writeJsonAtomic`, which writes a `.tmp`
  /// sibling then renames it over the target, so a crash mid-rewrite leaves
  /// either the prior file or the fully written new one, never a partial or
  /// a wiped directory (which would silently lose unsynced pendingCreate
  /// workouts). Only once the new state is durably on disk do we delete
  /// files for ids that no longer exist.
  ///
  /// Both passes isolate per-file failures so one bad row can't abort the
  /// rest. A row whose write throws is still added to `keep` so its prior
  /// file (left intact by the atomic write) isn't then deleted as an orphan
  /// — degrading to "this row keeps its last-good version" rather than
  /// losing it.
  Future<void> _rewriteAll() async {
    final dir = _dir;
    if (dir == null) return;
    final keep = <String>{};
    for (final stored in _rows.values) {
      final file = File('${dir.path}/${stored.id}.json');
      keep.add(file.path);
      try {
        await writeJsonAtomic(file, stored.toJson());
      } catch (e) {
        debugPrint('local_gym_store: rewrite write failed ${file.path}: $e');
      }
    }
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (keep.contains(entity.path)) continue;
      try {
        await entity.delete();
      } catch (e) {
        debugPrint('local_gym_store: orphan delete failed ${entity.path}: $e');
      }
    }
  }

  static List<Map<String, dynamic>> _setsToMaps(List<GymSetInput> sets) => [
        for (final s in sets)
          <String, dynamic>{
            'exercise_name': s.exerciseName,
            'reps': s.reps,
            'weight_kg': s.weightKg,
            'rpe': s.rpe,
          },
      ];

  static List<GymSetInput> _mapsToSets(List<Map<String, dynamic>> sets) => [
        for (final s in sets)
          (
            exerciseName: s['exercise_name'] as String,
            reps: (s['reps'] as num?)?.toInt(),
            weightKg: (s['weight_kg'] as num?)?.toDouble(),
            rpe: (s['rpe'] as num?)?.toDouble(),
          ),
      ];

  /// Crypto-strong v4 UUID. Avoids pulling in a dedicated `uuid`
  /// package — `Random.secure()` is enough.
  static String _newUuid() {
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
    _rows.clear();
    notifyListeners();
  }
}
