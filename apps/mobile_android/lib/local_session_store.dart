import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'offline_sync_store.dart';

/// Sync state for a single session plan. Alias of the shared [SyncState] so the
/// store tests + screens keep the `SessionSyncState` name.
typedef SessionSyncState = SyncState;

/// One block inside a [StoredSessionPlan], with its items carried inline (a
/// plan is never partially useful, so the children travel with the parent in
/// one file — same rationale as gym routines / workouts).
class StoredSessionBlock {
  StoredSessionBlock({
    required this.id,
    required this.position,
    this.name,
    required this.items,
  });

  final String id;
  final int position;
  final String? name;
  final List<StoredSessionItem> items;

  Map<String, dynamic> toJson() => {
        'id': id,
        'position': position,
        'name': name,
        'items': [for (final it in items) it.toJson()],
      };

  factory StoredSessionBlock.fromJson(Map<String, dynamic> json) =>
      StoredSessionBlock(
        id: json['id'] as String? ?? '',
        position: (json['position'] as num?)?.toInt() ?? 0,
        name: json['name'] as String?,
        items: ((json['items'] as List?) ?? const [])
            .map((it) =>
                StoredSessionItem.fromJson(Map<String, dynamic>.from(it as Map)))
            .toList(),
      );
}

/// One movement item inside a [StoredSessionBlock]. `kind` is the raw
/// `'hold' | 'reps' | 'flow'` wire value.
class StoredSessionItem {
  StoredSessionItem({
    required this.id,
    required this.position,
    required this.movementName,
    required this.kind,
    this.durationS,
    this.reps,
    this.perSide = false,
    this.tempo,
    this.cue,
  });

  final String id;
  final int position;
  final String movementName;
  final String kind;
  final int? durationS;
  final int? reps;
  final bool perSide;
  final String? tempo;
  final String? cue;

  Map<String, dynamic> toJson() => {
        'id': id,
        'position': position,
        'movement_name': movementName,
        'kind': kind,
        'duration_s': durationS,
        'reps': reps,
        'per_side': perSide,
        'tempo': tempo,
        'cue': cue,
      };

  factory StoredSessionItem.fromJson(Map<String, dynamic> json) =>
      StoredSessionItem(
        id: json['id'] as String? ?? '',
        position: (json['position'] as num?)?.toInt() ?? 0,
        movementName: json['movement_name'] as String? ?? '',
        kind: json['kind'] as String? ?? 'hold',
        durationS: (json['duration_s'] as num?)?.toInt(),
        reps: (json['reps'] as num?)?.toInt(),
        perSide: (json['per_side'] as bool?) ?? false,
        tempo: json['tempo'] as String?,
        cue: json['cue'] as String?,
      );
}

/// One stored session plan in the [LocalSessionStore]. Holds the
/// `session_plans` row shape plus its blocks + their items inline, and the
/// sync-state tag.
class StoredSessionPlan implements SyncEntry {
  StoredSessionPlan({
    required this.row,
    required this.blocks,
    required this.syncState,
    DateTime? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.now().toUtc();

  final Map<String, dynamic> row;
  final List<StoredSessionBlock> blocks;
  @override
  final SyncState syncState;
  @override
  final DateTime lastModifiedAt;

  @override
  String get id => row['id'] as String;
  @override
  bool get isTombstone => syncState == SyncState.pendingDelete;

  String get title => (row['title'] as String?) ?? '';
  String? get discipline => row['discipline'] as String?;
  String? get equipment => row['equipment'] as String?;
  int? get estDurationMin => (row['est_duration_min'] as num?)?.toInt();

  @override
  Map<String, dynamic> toJson() => {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'row': row,
        'blocks': [for (final b in blocks) b.toJson()],
        'sync_state': syncState.wire,
        'last_modified_at': lastModifiedAt.toIso8601String(),
      };

  factory StoredSessionPlan.fromJson(Map<String, dynamic> json) =>
      StoredSessionPlan(
        row: Map<String, dynamic>.from(json['row'] as Map),
        blocks: ((json['blocks'] as List?) ?? const [])
            .map((b) =>
                StoredSessionBlock.fromJson(Map<String, dynamic>.from(b as Map)))
            .toList(),
        syncState: syncStateFromWire(json['sync_state'] as String?),
        lastModifiedAt:
            DateTime.tryParse(json['last_modified_at'] as String? ?? '')
                    ?.toUtc() ??
                DateTime.now().toUtc(),
      );
}

/// Disk-backed store for the user's session plans (session_planner.md). Sibling
/// of [LocalRoutineStore] over [OfflineSyncStore]: one JSON file per plan under
/// `<appDocs>/sessions/`, with the plan's blocks + their items carried
/// **inline** (a plan is never partially useful). In-memory `ChangeNotifier`
/// so the detail / library screens refresh on every mutation; sync drained on
/// demand.
///
/// Offline contract:
/// - `createLocal` mints a v4 UUID (the client value becomes the server id —
///   `session_plans.id` defaults to gen_random_uuid() but accepts a client
///   value, so no temp-id reconciliation), marks the plan pendingCreate, and
///   stores its blocks + items inline.
/// - `deleteLocal` on a synced plan writes a tombstone; on a plan that was
///   only ever local (pendingCreate) it just drops the file.
/// - `syncWithServer(api)` drains every non-synced plan in create → delete
///   order. The web is the canonical editor, so an edit recreates (delete +
///   re-create) — mirroring [LocalRoutineStore.pushUpdate].
class LocalSessionStore extends OfflineSyncStore<StoredSessionPlan> {
  @override
  String get storeSubdir => 'sessions';

  @override
  String get debugLabel => 'local_session_store';

  @override
  StoredSessionPlan entryFromJson(Map<String, dynamic> json) =>
      StoredSessionPlan.fromJson(json);

  @override
  String? get summaryTimestampKey => 'updated_at';

  @override
  Map<String, dynamic> summaryOf(StoredSessionPlan entry) => {
        'id': entry.id,
        'sync_state': entry.syncState.wire,
        'updated_at': entry.row['updated_at'],
        'title': entry.row['title'],
      };

  @override
  StoredSessionPlan asSynced(StoredSessionPlan entry) => StoredSessionPlan(
        row: entry.row,
        blocks: entry.blocks,
        syncState: SyncState.synced,
        lastModifiedAt: entry.lastModifiedAt,
      );

  @override
  StoredSessionPlan asPendingCreate(StoredSessionPlan entry) =>
      StoredSessionPlan(
        row: entry.row,
        blocks: entry.blocks,
        syncState: SyncState.pendingCreate,
        lastModifiedAt: entry.lastModifiedAt,
      );

  /// Live plans (excludes tombstones), most-recently-updated first — the
  /// library order, matching web `fetchSessionPlans`.
  List<StoredSessionPlan> get plans {
    final live = rowsById.values.where((p) => !p.isTombstone).toList();
    live.sort((a, b) => b.lastModifiedAt.compareTo(a.lastModifiedAt));
    return live;
  }

  /// A single live plan by id, or null if missing / a tombstone.
  StoredSessionPlan? byId(String id) {
    final p = rowsById[id];
    return (p == null || p.isTombstone) ? null : p;
  }

  /// Mint a new UUID and persist a pending-create plan. Returns the stored
  /// shape so the caller can navigate to it immediately.
  Future<StoredSessionPlan> createLocal({
    required String title,
    String? discipline,
    String? equipment,
    int? estDurationMin,
    bool isPublic = false,
    List<StoredSessionBlock> blocks = const [],
  }) async {
    final id = OfflineSyncStore.newUuid();
    final now = DateTime.now().toUtc();
    final row = <String, dynamic>{
      'id': id,
      'title': title.trim(),
      'discipline': discipline,
      'equipment': equipment,
      'est_duration_min': estDurationMin,
      'is_public': isPublic,
      'updated_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    };
    final stored = StoredSessionPlan(
      row: row,
      blocks: blocks,
      syncState: SyncState.pendingCreate,
      lastModifiedAt: now,
    );
    await persist(stored);
    return stored;
  }

  /// Delete a plan. A plan that was only ever local (pendingCreate) disappears
  /// immediately; a synced plan becomes a pendingDelete tombstone so the next
  /// sync issues the server DELETE (which cascades the blocks + items). Logged
  /// gym_workouts are untouched.
  Future<void> deleteLocal(String id) async {
    final existing = rowsById[id];
    if (existing == null) return;
    if (existing.syncState == SyncState.pendingCreate) {
      await dropRow(id);
      return;
    }
    final tombstone = StoredSessionPlan(
      row: existing.row,
      blocks: existing.blocks,
      syncState: SyncState.pendingDelete,
    );
    await persist(tombstone);
  }

  /// Replace the in-memory state from a fresh server fetch (each plan with its
  /// blocks + their items). Pending-* plans are preserved — only `synced` rows
  /// are overwritten so an offline create / delete isn't clobbered by the
  /// server's copy. Newer-wins on the synced copies, mirroring
  /// [LocalRoutineStore.replaceFromServer].
  Future<void> replaceFromServer(
    List<({Map<String, dynamic> plan, List<StoredSessionBlock> blocks})>
        serverPlans,
  ) async {
    final preserved = <String, StoredSessionPlan>{};
    final syncedLocal = <String, StoredSessionPlan>{};
    for (final entry in rowsById.entries) {
      if (entry.value.syncState != SyncState.synced) {
        preserved[entry.key] = entry.value;
      } else {
        syncedLocal[entry.key] = entry.value;
      }
    }
    rowsById.clear();
    for (final p in serverPlans) {
      final id = p.plan['id'] as String;
      if (preserved.containsKey(id)) {
        rowsById[id] = preserved.remove(id)!;
        continue;
      }
      final local = syncedLocal[id];
      final serverTs = _parseTs(p.plan['updated_at']);
      if (local != null &&
          serverTs != null &&
          local.lastModifiedAt.isAfter(serverTs)) {
        rowsById[id] = local;
      } else {
        rowsById[id] = StoredSessionPlan(
          row: p.plan,
          blocks: p.blocks,
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
  Future<void> pushCreate(ApiClient api, StoredSessionPlan stored) =>
      api.createSessionPlan(
        id: stored.id,
        title: stored.title,
        discipline: stored.discipline,
        equipment: stored.equipment,
        estDurationMin: stored.estDurationMin,
        isPublic: (stored.row['is_public'] as bool?) ?? false,
        updatedAt: stored.lastModifiedAt,
        blocks: _blocksToInput(stored.blocks),
        items: _itemsToInput(stored.blocks),
      );

  // The web is the canonical editor, so a plan never reaches pendingUpdate on
  // mobile — but the base class requires the hook. Recreate to stay correct if
  // a future mobile edit path ever flips the state.
  @override
  Future<void> pushUpdate(ApiClient api, StoredSessionPlan stored) async {
    await api.deleteSessionPlan(stored.id);
    await api.createSessionPlan(
      id: stored.id,
      title: stored.title,
      discipline: stored.discipline,
      equipment: stored.equipment,
      estDurationMin: stored.estDurationMin,
      isPublic: (stored.row['is_public'] as bool?) ?? false,
      updatedAt: stored.lastModifiedAt,
      blocks: _blocksToInput(stored.blocks),
      items: _itemsToInput(stored.blocks),
    );
  }

  @override
  Future<void> pushDelete(ApiClient api, StoredSessionPlan stored) =>
      api.deleteSessionPlan(stored.id);

  static List<SessionPlanBlockInput> _blocksToInput(
          List<StoredSessionBlock> blocks) =>
      [
        for (final b in blocks)
          (id: b.id, position: b.position, name: b.name),
      ];

  static List<SessionPlanItemInput> _itemsToInput(
          List<StoredSessionBlock> blocks) =>
      [
        for (final b in blocks)
          for (final it in b.items)
            (
              id: it.id,
              blockId: b.id,
              position: it.position,
              movementName: it.movementName,
              kind: it.kind,
              durationS: it.durationS,
              reps: it.reps,
              perSide: it.perSide,
              tempo: it.tempo,
              cue: it.cue,
            ),
      ];
}
