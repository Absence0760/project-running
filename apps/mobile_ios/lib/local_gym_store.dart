import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'offline_sync_store.dart';

/// Sync state for a single gym workout. Alias of the shared [SyncState] so the
/// store tests + screens keep the `GymSyncState` name.
typedef GymSyncState = SyncState;

/// One stored workout in the [LocalGymStore]. Holds the `gym_workouts`
/// row shape plus the workout's sets inline (the composer always edits
/// the whole set list, so they travel together) and the sync-state tag.
/// Sets are positional — `set_index` is the list index, assigned on the
/// eventual INSERT.
class StoredGymWorkout implements SyncEntry {
  StoredGymWorkout({
    required this.row,
    required this.sets,
    required this.syncState,
    DateTime? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.now().toUtc();

  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> sets;
  @override
  final SyncState syncState;
  @override
  final DateTime lastModifiedAt;

  @override
  String get id => row['id'] as String;
  @override
  bool get isTombstone => syncState == SyncState.pendingDelete;

  /// Typed domain view of this workout (scalars + inline sets). Lets screens
  /// read `.workout.title` instead of reaching into the raw `row` map.
  GymWorkout get workout => GymWorkout.fromRow(row, sets: sets);

  DateTime? get startedAt {
    final v = row['started_at'];
    return v is String ? DateTime.tryParse(v) : null;
  }

  @override
  Map<String, dynamic> toJson() => {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
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
        syncState: syncStateFromWire(json['sync_state'] as String?),
        lastModifiedAt:
            DateTime.tryParse(json['last_modified_at'] as String? ?? '')
                    ?.toUtc() ??
                DateTime.now().toUtc(),
      );
}

/// Disk-backed store for the user's gym workouts. Mirrors
/// [LocalGearStore] (decisions §73 + §122): one JSON file per workout under
/// `<appDocs>/gym/`, in-memory `ChangeNotifier` so screens refresh on
/// every mutation, sync drained on demand (sign-in, connectivity
/// return, manual pull-to-refresh). The per-row sync-state machine lives in
/// [OfflineSyncStore]; this class supplies the gym-specific create / update /
/// replace-from-server logic, including the inline `sets`.
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
class LocalGymStore extends OfflineSyncStore<StoredGymWorkout> {
  @override
  String get storeSubdir => 'gym';

  @override
  String get debugLabel => 'local_gym_store';

  @override
  StoredGymWorkout entryFromJson(Map<String, dynamic> json) =>
      StoredGymWorkout.fromJson(json);

  @override
  String? get summaryTimestampKey => 'started_at';

  @override
  Map<String, dynamic> summaryOf(StoredGymWorkout entry) => {
        'id': entry.id,
        'sync_state': entry.syncState.wire,
        'started_at': entry.row['started_at'],
        'title': entry.row['title'],
        'set_count': entry.sets.length,
      };

  @override
  StoredGymWorkout asSynced(StoredGymWorkout entry) => StoredGymWorkout(
        row: entry.row,
        sets: entry.sets,
        syncState: SyncState.synced,
        lastModifiedAt: entry.lastModifiedAt,
      );

  @override
  StoredGymWorkout asPendingCreate(StoredGymWorkout entry) => StoredGymWorkout(
        row: entry.row,
        sets: entry.sets,
        syncState: SyncState.pendingCreate,
        lastModifiedAt: entry.lastModifiedAt,
      );

  List<StoredGymWorkout>? _workoutsCache;
  int _workoutsCacheRevision = -1;

  /// Live workouts (excludes tombstones), newest-started first. Cached against
  /// [storeRevision] so the dashboard — which reads this several times per
  /// build and rebuilds on unrelated run/food/prefs mutations — re-sorts the
  /// whole gym history only after an actual change, not on every access. The
  /// sort key is parsed once per workout rather than per comparison.
  List<StoredGymWorkout> get workouts {
    if (_workoutsCache != null && _workoutsCacheRevision == storeRevision) {
      return _workoutsCache!;
    }
    final keyed = [
      for (final w in rowsById.values)
        if (!w.isTombstone) (w: w, t: w.startedAt),
    ];
    keyed.sort((a, b) {
      final at = a.t;
      final bt = b.t;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
    final out = [for (final e in keyed) e.w];
    _workoutsCache = out;
    _workoutsCacheRevision = storeRevision;
    return out;
  }

  /// Serialised live workouts (excludes tombstones) in the
  /// `StoredGymWorkout.toJson()` shape, for the backup archive's
  /// `gym_workouts.json`.
  List<Map<String, dynamic>> get backupRecords => rowsById.values
      .where((w) => !w.isTombstone)
      .map((w) => w.toJson())
      .toList();

  /// A single live workout by id, or null if missing / a tombstone.
  StoredGymWorkout? byId(String id) {
    final w = rowsById[id];
    return (w == null || w.isTombstone) ? null : w;
  }

  /// Mint a new UUID and persist a pending-create workout. Returns the
  /// stored shape so the caller can render it immediately.
  Future<StoredGymWorkout> createLocal({
    String? title,
    required DateTime startedAt,
    int? durationS,
    String? notes,
    bool isPublic = false,
    Map<String, dynamic>? metadata,
    List<GymSetInput> sets = const [],
  }) async {
    final id = OfflineSyncStore.newUuid();
    final now = DateTime.now().toUtc();
    final row = <String, dynamic>{
      'id': id,
      'title': title,
      'started_at': startedAt.toUtc().toIso8601String(),
      'duration_s': durationS,
      'notes': notes,
      'is_public': isPublic,
      'external_id': null,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      'last_modified_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    };
    final stored = StoredGymWorkout(
      row: row,
      sets: _setsToMaps(sets),
      syncState: SyncState.pendingCreate,
      lastModifiedAt: now,
    );
    await persist(stored);
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
    Map<String, dynamic>? metadata,
    List<GymSetInput>? sets,
  }) async {
    final existing = rowsById[id];
    if (existing == null) return;
    final now = DateTime.now().toUtc();
    final next = Map<String, dynamic>.from(existing.row);
    if (title != null) next['title'] = title;
    if (durationS != null) next['duration_s'] = durationS;
    if (notes != null) next['notes'] = notes;
    if (isPublic != null) next['is_public'] = isPublic;
    if (metadata != null) next['metadata'] = metadata;
    next['last_modified_at'] = now.toIso8601String();
    final stored = StoredGymWorkout(
      row: next,
      sets: sets != null ? _setsToMaps(sets) : existing.sets,
      syncState: existing.syncState == SyncState.pendingCreate
          ? SyncState.pendingCreate
          : SyncState.pendingUpdate,
      lastModifiedAt: now,
    );
    await persist(stored);
  }

  /// Delete a workout. A workout that was only ever local (pendingCreate)
  /// disappears immediately; a synced or pendingUpdate workout becomes a
  /// pendingDelete tombstone so the next sync issues the server DELETE.
  Future<void> deleteLocal(String id) async {
    final existing = rowsById[id];
    if (existing == null) return;
    if (existing.syncState == SyncState.pendingCreate) {
      await dropRow(id);
      return;
    }
    final tombstone = StoredGymWorkout(
      row: existing.row,
      sets: existing.sets,
      syncState: SyncState.pendingDelete,
    );
    await persist(tombstone);
  }

  /// Replace the in-memory state from a fresh server fetch (workout rows
  /// each paired with their sets). Pending-* workouts are preserved as-is
  /// — only `synced` rows are overwritten so an offline edit isn't
  /// clobbered by the server's older copy.
  ///
  /// The hydrating surfaces fetch only the newest N workouts
  /// (`fetchGymWorkoutsWithSets(limit:)`), so pass that limit as [fetchLimit].
  /// When the returned page is full (>= limit) there may be OLDER workouts the
  /// fetch couldn't see; their lower bound is the oldest `started_at` returned.
  /// A synced workout older than that bound is preserved (its absence is
  /// "outside the fetch window", not a server-side deletion) so opening the gym
  /// screen can't silently wipe synced history beyond the newest [fetchLimit].
  /// With no [fetchLimit] / window this is a full replace — correct only when
  /// the caller fetched the COMPLETE set.
  Future<void> replaceFromServer(
    List<({Map<String, dynamic> workout, List<Map<String, dynamic>> sets})>
        serverWorkouts, {
    DateTime? windowStart,
    DateTime? windowEnd,
    int? fetchLimit,
  }) async {
    if (windowStart == null &&
        fetchLimit != null &&
        serverWorkouts.length >= fetchLimit) {
      DateTime? oldest;
      for (final w in serverWorkouts) {
        final ts = _parseTs(w.workout['started_at']);
        if (ts != null && (oldest == null || ts.isBefore(oldest))) oldest = ts;
      }
      windowStart = oldest;
    }
    final preserved = <String, StoredGymWorkout>{};
    final syncedLocal = <String, StoredGymWorkout>{};
    for (final entry in rowsById.entries) {
      if (entry.value.syncState != SyncState.synced) {
        preserved[entry.key] = entry.value;
      } else if (_outsideWindow(entry.value.startedAt, windowStart, windowEnd)) {
        preserved[entry.key] = entry.value;
      } else {
        syncedLocal[entry.key] = entry.value;
      }
    }
    rowsById.clear();
    for (final w in serverWorkouts) {
      final id = w.workout['id'] as String;
      if (preserved.containsKey(id)) {
        rowsById[id] = preserved.remove(id)!;
        continue;
      }
      // Newer-wins: keep the local synced copy when its modification clock
      // is strictly ahead of the server's, so a stale server fetch can't
      // clobber a more-recent already-pushed edit. Mirrors
      // LocalRunStore.saveFromRemote's guard.
      final local = syncedLocal[id];
      final serverTs = _parseTs(w.workout['last_modified_at']);
      if (local != null &&
          serverTs != null &&
          local.lastModifiedAt.isAfter(serverTs)) {
        rowsById[id] = local;
      } else {
        // Build the synced row's clock from the server's last_modified_at
        // (not wall-clock now) so the next refresh's newer-wins compares
        // like-for-like.
        rowsById[id] = StoredGymWorkout(
          row: w.workout,
          sets: w.sets.map((s) => Map<String, dynamic>.from(s)).toList(),
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

  /// True when [at] falls outside the half-open fetch window `[start, end)`.
  /// A null timestamp is treated as in-window (eligible for prune), preserving
  /// the no-window full-replace contract. Compares absolute instants.
  static bool _outsideWindow(DateTime? at, DateTime? start, DateTime? end) {
    if (at == null) return false;
    if (start != null && at.isBefore(start)) return true;
    if (end != null && !at.isBefore(end)) return true;
    return false;
  }

  @override
  Future<void> pushCreate(ApiClient api, StoredGymWorkout stored) =>
      api.createGymWorkout(
        id: stored.id,
        title: stored.row['title'] as String?,
        startedAt: stored.startedAt ?? DateTime.now().toUtc(),
        durationS: (stored.row['duration_s'] as num?)?.toInt(),
        notes: stored.row['notes'] as String?,
        isPublic: (stored.row['is_public'] as bool?) ?? false,
        lastModifiedAt: stored.lastModifiedAt,
        metadata: _metadataOf(stored),
        sets: _mapsToSets(stored.sets),
      );

  static Map<String, dynamic>? _metadataOf(StoredGymWorkout stored) {
    final m = stored.row['metadata'];
    return m is Map ? Map<String, dynamic>.from(m) : null;
  }

  @override
  Future<void> pushUpdate(ApiClient api, StoredGymWorkout stored) =>
      api.updateGymWorkout(
        stored.id,
        title: stored.row['title'] as String?,
        durationS: (stored.row['duration_s'] as num?)?.toInt(),
        notes: stored.row['notes'] as String?,
        isPublic: (stored.row['is_public'] as bool?) ?? false,
        lastModifiedAt: stored.lastModifiedAt,
        metadata: _metadataOf(stored),
        sets: _mapsToSets(stored.sets),
      );

  @override
  Future<void> pushDelete(ApiClient api, StoredGymWorkout stored) =>
      api.deleteGymWorkout(stored.id);

  static List<Map<String, dynamic>> _setsToMaps(List<GymSetInput> sets) => [
        for (final s in sets)
          <String, dynamic>{
            'exercise_name': s.exerciseName,
            'reps': s.reps,
            'weight_kg': s.weightKg,
            'rpe': s.rpe,
            'duration_s': s.durationS,
          },
      ];

  static List<GymSetInput> _mapsToSets(List<Map<String, dynamic>> sets) => [
        for (final s in sets)
          (
            exerciseName: s['exercise_name'] as String,
            reps: (s['reps'] as num?)?.toInt(),
            weightKg: (s['weight_kg'] as num?)?.toDouble(),
            rpe: (s['rpe'] as num?)?.toDouble(),
            durationS: (s['duration_s'] as num?)?.toInt(),
          ),
      ];
}
