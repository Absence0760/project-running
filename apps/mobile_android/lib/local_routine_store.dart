import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'offline_sync_store.dart';

/// Sync state for a single routine. Alias of the shared [SyncState] so the
/// store tests + screens keep the `RoutineSyncState` name.
typedef RoutineSyncState = SyncState;

/// One planned set inside a [StoredRoutineExercise] — targets only. A single
/// rep target lives in [targetRepsMin] with [targetRepsMax] null (the
/// canonical single-target rep shape; a range fills both).
class StoredRoutineSet {
  StoredRoutineSet({
    this.setType = 'working',
    this.targetRepsMin,
    this.targetRepsMax,
    this.targetWeightKg,
    this.targetRpe,
    this.restS,
    this.targetDurationS,
    this.targetDistanceM,
  });

  final String setType;
  final int? targetRepsMin;
  final int? targetRepsMax;
  final double? targetWeightKg;
  final double? targetRpe;
  final num? restS;
  final int? targetDurationS;
  final double? targetDistanceM;

  Map<String, dynamic> toJson() => {
        'set_type': setType,
        'target_reps_min': targetRepsMin,
        'target_reps_max': targetRepsMax,
        'target_weight_kg': targetWeightKg,
        'target_rpe': targetRpe,
        'rest_s': restS,
        'target_duration_s': targetDurationS,
        'target_distance_m': targetDistanceM,
      };

  factory StoredRoutineSet.fromJson(Map<String, dynamic> json) =>
      StoredRoutineSet(
        setType: json['set_type'] as String? ?? 'working',
        targetRepsMin: (json['target_reps_min'] as num?)?.toInt(),
        targetRepsMax: (json['target_reps_max'] as num?)?.toInt(),
        targetWeightKg: (json['target_weight_kg'] as num?)?.toDouble(),
        targetRpe: (json['target_rpe'] as num?)?.toDouble(),
        restS: json['rest_s'] as num?,
        targetDurationS: (json['target_duration_s'] as num?)?.toInt(),
        targetDistanceM: (json['target_distance_m'] as num?)?.toDouble(),
      );
}

/// One planned exercise inside a [StoredRoutine], with its planned sets
/// carried inline (a routine is never partially useful, so the children
/// travel with the parent in one file — same rationale as gym workouts).
class StoredRoutineExercise {
  StoredRoutineExercise({
    required this.exerciseName,
    required this.exerciseKey,
    required this.sets,
    this.supersetGroup,
    this.supersetOrder,
    this.modality = 'weight_reps',
    this.progression = 'none',
    this.progressionParams = const {},
  });

  final String exerciseName;
  final String exerciseKey;
  final List<StoredRoutineSet> sets;
  final int? supersetGroup;
  final int? supersetOrder;
  final String modality;
  final String progression;
  final Map<String, dynamic> progressionParams;

  Map<String, dynamic> toJson() => {
        'exercise_name': exerciseName,
        'exercise_key': exerciseKey,
        'superset_group': supersetGroup,
        'superset_order': supersetOrder,
        'modality': modality,
        'progression': progression,
        'progression_params': progressionParams,
        'sets': [for (final s in sets) s.toJson()],
      };

  factory StoredRoutineExercise.fromJson(Map<String, dynamic> json) =>
      StoredRoutineExercise(
        exerciseName: json['exercise_name'] as String? ?? '',
        exerciseKey: json['exercise_key'] as String? ?? '',
        supersetGroup: (json['superset_group'] as num?)?.toInt(),
        supersetOrder: (json['superset_order'] as num?)?.toInt(),
        modality: json['modality'] as String? ?? 'weight_reps',
        progression: json['progression'] as String? ?? 'none',
        progressionParams: json['progression_params'] is Map
            ? Map<String, dynamic>.from(json['progression_params'] as Map)
            : const {},
        sets: ((json['sets'] as List?) ?? const [])
            .map((s) => StoredRoutineSet.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );
}

/// One stored routine in the [LocalRoutineStore]. Holds the `gym_routines`
/// row shape plus its exercises + their planned sets inline, and the
/// sync-state tag. `exercise_count` is denormalised in the row (client-stamped,
/// non-authoritative — matches the server column).
class StoredRoutine implements SyncEntry {
  StoredRoutine({
    required this.row,
    required this.exercises,
    required this.syncState,
    DateTime? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.now().toUtc();

  final Map<String, dynamic> row;
  final List<StoredRoutineExercise> exercises;
  @override
  final SyncState syncState;
  @override
  final DateTime lastModifiedAt;

  @override
  String get id => row['id'] as String;
  @override
  bool get isTombstone => syncState == SyncState.pendingDelete;

  String get title => (row['title'] as String?) ?? '';
  String? get notes => row['notes'] as String?;
  int get exerciseCount => (row['exercise_count'] as num?)?.toInt() ?? 0;

  /// Non-null when this routine is a club-owned template
  /// (`gym_routines.club_id`). Personal routines leave it null. Gates the
  /// publish control + drives the "Club template" badge on the detail screen.
  String? get clubId => row['club_id'] as String?;

  /// True when this personal routine is published to the public library
  /// (`gym_routines.is_public_template`, migration 20270224_001). Drives the
  /// public publish/unpublish toggle + badge on the detail screen.
  bool get isPublicTemplate => (row['is_public_template'] as bool?) ?? false;

  @override
  Map<String, dynamic> toJson() => {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'row': row,
        'exercises': [for (final e in exercises) e.toJson()],
        'sync_state': syncState.wire,
        'last_modified_at': lastModifiedAt.toIso8601String(),
      };

  factory StoredRoutine.fromJson(Map<String, dynamic> json) => StoredRoutine(
        row: Map<String, dynamic>.from(json['row'] as Map),
        exercises: ((json['exercises'] as List?) ?? const [])
            .map((e) =>
                StoredRoutineExercise.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        syncState: syncStateFromWire(json['sync_state'] as String?),
        lastModifiedAt:
            DateTime.tryParse(json['last_modified_at'] as String? ?? '')
                    ?.toUtc() ??
                DateTime.now().toUtc(),
      );
}

/// Disk-backed store for the user's gym routines (gym_programming.md slice P1).
/// Sibling of [LocalGymStore] / [LocalGearStore] (decisions §73 + §122): one
/// JSON file per routine under `<appDocs>/routines/`, with the routine's
/// exercises + their planned sets carried **inline** (a routine is never
/// partially useful). In-memory `ChangeNotifier` so the library / detail
/// screens refresh on every mutation; sync drained on demand.
///
/// Offline contract:
/// - `createLocal` mints a v4 UUID (the client value becomes the server id —
///   `gym_routines.id` defaults to gen_random_uuid() but accepts a client
///   value, so no temp-id reconciliation), marks the routine pendingCreate,
///   and stores its exercises + planned sets inline.
/// - `deleteLocal` on a synced routine writes a tombstone; on a routine that
///   was only ever local (pendingCreate) it just drops the file.
/// - `syncWithServer(api)` drains every non-synced routine in create → delete
///   order. P1 has no edit path (build / save / delete only), mirroring web.
class LocalRoutineStore extends OfflineSyncStore<StoredRoutine> {
  @override
  String get storeSubdir => 'routines';

  @override
  String get debugLabel => 'local_routine_store';

  @override
  StoredRoutine entryFromJson(Map<String, dynamic> json) =>
      StoredRoutine.fromJson(json);

  @override
  String? get summaryTimestampKey => 'last_modified_at';

  @override
  Map<String, dynamic> summaryOf(StoredRoutine entry) => {
        'id': entry.id,
        'sync_state': entry.syncState.wire,
        'last_modified_at': entry.row['last_modified_at'],
        'title': entry.row['title'],
        'exercise_count': entry.exerciseCount,
      };

  @override
  StoredRoutine asSynced(StoredRoutine entry) => StoredRoutine(
        row: entry.row,
        exercises: entry.exercises,
        syncState: SyncState.synced,
        lastModifiedAt: entry.lastModifiedAt,
      );

  @override
  StoredRoutine asPendingCreate(StoredRoutine entry) => StoredRoutine(
        row: entry.row,
        exercises: entry.exercises,
        syncState: SyncState.pendingCreate,
        lastModifiedAt: entry.lastModifiedAt,
      );

  /// Live routines (excludes tombstones), most-recently-modified first —
  /// the library order, matching web `fetchGymRoutines`.
  List<StoredRoutine> get routines {
    final live = rowsById.values.where((r) => !r.isTombstone).toList();
    live.sort((a, b) => b.lastModifiedAt.compareTo(a.lastModifiedAt));
    return live;
  }

  /// A single live routine by id, or null if missing / a tombstone.
  StoredRoutine? byId(String id) {
    final r = rowsById[id];
    return (r == null || r.isTombstone) ? null : r;
  }

  /// Mint a new UUID and persist a pending-create routine. Blank-named
  /// exercises are dropped (mirroring web `createGymRoutine`). Returns the
  /// stored shape so the caller can navigate to it immediately.
  Future<StoredRoutine> createLocal({
    required String title,
    String? notes,
    List<StoredRoutineExercise> exercises = const [],
  }) async {
    final id = OfflineSyncStore.newUuid();
    final now = DateTime.now().toUtc();
    final kept = exercises
        .where((e) => e.exerciseName.trim().isNotEmpty)
        .toList(growable: false);
    final row = <String, dynamic>{
      'id': id,
      'title': title.trim(),
      'notes': notes,
      'periodisation': 'none',
      'exercise_count': kept.length,
      'external_id': null,
      'last_modified_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    };
    final stored = StoredRoutine(
      row: row,
      exercises: kept,
      syncState: SyncState.pendingCreate,
      lastModifiedAt: now,
    );
    await persist(stored);
    return stored;
  }

  /// Reflect a server-side public-library toggle in the local cache. The
  /// `set_gym_routine_public` RPC has already flipped `is_public_template`
  /// server-side; this updates the cached row in place (kept synced — the
  /// server is the source of truth) so the detail screen renders the new
  /// badge/toggle state offline. No-op for an unknown id.
  Future<void> setPublicLocal(String id, bool isPublic) async {
    final existing = rowsById[id];
    if (existing == null) return;
    final row = Map<String, dynamic>.from(existing.row);
    row['is_public_template'] = isPublic;
    await persist(StoredRoutine(
      row: row,
      exercises: existing.exercises,
      syncState: existing.syncState,
      lastModifiedAt: existing.lastModifiedAt,
    ));
  }

  /// Delete a routine. A routine that was only ever local (pendingCreate)
  /// disappears immediately; a synced routine becomes a pendingDelete
  /// tombstone so the next sync issues the server DELETE (which cascades the
  /// exercises + sets). Logged gym_workouts are untouched.
  Future<void> deleteLocal(String id) async {
    final existing = rowsById[id];
    if (existing == null) return;
    if (existing.syncState == SyncState.pendingCreate) {
      await dropRow(id);
      return;
    }
    final tombstone = StoredRoutine(
      row: existing.row,
      exercises: existing.exercises,
      syncState: SyncState.pendingDelete,
    );
    await persist(tombstone);
  }

  /// Replace the in-memory state from a fresh server fetch (each routine with
  /// its exercises + their planned sets). Pending-* routines are preserved —
  /// only `synced` rows are overwritten so an offline create / delete isn't
  /// clobbered by the server's copy. Newer-wins on the synced copies, mirroring
  /// [LocalGymStore.replaceFromServer].
  Future<void> replaceFromServer(
    List<({Map<String, dynamic> routine, List<StoredRoutineExercise> exercises})>
        serverRoutines,
  ) async {
    final preserved = <String, StoredRoutine>{};
    final syncedLocal = <String, StoredRoutine>{};
    for (final entry in rowsById.entries) {
      if (entry.value.syncState != SyncState.synced) {
        preserved[entry.key] = entry.value;
      } else {
        syncedLocal[entry.key] = entry.value;
      }
    }
    rowsById.clear();
    for (final r in serverRoutines) {
      final id = r.routine['id'] as String;
      if (preserved.containsKey(id)) {
        rowsById[id] = preserved.remove(id)!;
        continue;
      }
      final local = syncedLocal[id];
      final serverTs = _parseTs(r.routine['last_modified_at']);
      if (local != null &&
          serverTs != null &&
          local.lastModifiedAt.isAfter(serverTs)) {
        rowsById[id] = local;
      } else {
        rowsById[id] = StoredRoutine(
          row: r.routine,
          exercises: r.exercises,
          syncState: SyncState.synced,
          lastModifiedAt: serverTs,
        );
      }
    }
    rowsById.addAll(preserved);
    await rewriteAll();
    notifyListeners();
  }

  static DateTime? _parseTs(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toUtc();
    return null;
  }

  @override
  Future<void> pushCreate(ApiClient api, StoredRoutine stored) =>
      api.createGymRoutine(
        id: stored.id,
        title: stored.title,
        notes: stored.notes,
        lastModifiedAt: stored.lastModifiedAt,
        exercises: _exercisesToInput(stored.exercises),
      );

  // P1 has no edit path (build / save / delete only), so a routine never
  // reaches pendingUpdate — but the base class requires the hook. Recreate to
  // stay correct if a future edit path ever flips the state.
  @override
  Future<void> pushUpdate(ApiClient api, StoredRoutine stored) async {
    await api.deleteGymRoutine(stored.id);
    await api.createGymRoutine(
      id: stored.id,
      title: stored.title,
      notes: stored.notes,
      lastModifiedAt: stored.lastModifiedAt,
      exercises: _exercisesToInput(stored.exercises),
    );
  }

  @override
  Future<void> pushDelete(ApiClient api, StoredRoutine stored) =>
      api.deleteGymRoutine(stored.id);

  static List<GymRoutineExerciseInput> _exercisesToInput(
          List<StoredRoutineExercise> exercises) =>
      [
        for (final e in exercises)
          (
            exerciseName: e.exerciseName,
            exerciseKey: e.exerciseKey,
            supersetGroup: e.supersetGroup,
            supersetOrder: e.supersetOrder,
            modality: e.modality,
            progression: e.progression,
            progressionParams: e.progressionParams,
            sets: <GymRoutineSetInput>[
              for (final s in e.sets)
                (
                  setType: s.setType,
                  targetRepsMin: s.targetRepsMin,
                  targetRepsMax: s.targetRepsMax,
                  targetWeightKg: s.targetWeightKg,
                  targetRpe: s.targetRpe,
                  restS: s.restS,
                  targetDurationS: s.targetDurationS,
                  targetDistanceM: s.targetDistanceM,
                ),
            ],
          ),
      ];
}
