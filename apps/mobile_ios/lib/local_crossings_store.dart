import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'offline_sync_store.dart';

/// Sync state for a single checkpoint crossing. Alias of the shared
/// [SyncState] so the store tests + screens keep the `CrossingSyncState` name.
typedef CrossingSyncState = SyncState;

/// One stored crossing in the [LocalCrossingsStore]. Holds the
/// `checkpoint_crossings` row map (non-health columns the volunteer collected,
/// plus the optional Art 9 weigh-in fields when the gated UI captured them)
/// plus the sync-state tag.
class StoredCrossing implements SyncEntry {
  StoredCrossing({
    required this.row,
    required this.syncState,
    DateTime? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.now().toUtc();

  final Map<String, dynamic> row;
  @override
  final SyncState syncState;
  @override
  final DateTime lastModifiedAt;

  @override
  String get id => row['id'] as String;
  @override
  bool get isTombstone => syncState == SyncState.pendingDelete;

  @override
  Map<String, dynamic> toJson() => {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'row': row,
        'sync_state': syncState.wire,
        'last_modified_at': lastModifiedAt.toIso8601String(),
      };

  factory StoredCrossing.fromJson(Map<String, dynamic> json) => StoredCrossing(
        row: Map<String, dynamic>.from(json['row'] as Map),
        syncState: syncStateFromWire(json['sync_state'] as String?),
        lastModifiedAt: storedClockOrEpoch(json['last_modified_at']),
      );
}

/// True when [raw] — an `instance_start` off a stored or server row — names
/// the same occurrence as [at].
///
/// An INSTANT comparison, deliberately not the string equality this replaced
/// (decisions § 1343). One occurrence has several spellings on the wire:
/// PostgREST answers `2026-06-01T18:00:00+00:00`, `CheckpointCrossingRow`
/// re-serialises that as `…T18:00:00.000Z`, and a row this store wrote before
/// § 1343 carries the writer's bare wall clock with no designator at all.
/// Comparing the text meant a server-fetched crossing never matched the
/// instance the screen was asking about, so "who has already been stamped
/// here" listed only the stamps this phone had made.
bool sameInstance(dynamic raw, DateTime at) {
  final parsed = parseServerTimestamp(raw);
  return parsed != null && parsed.isAtSameMomentAs(at);
}

/// Disk-backed store for aid-station checkpoint crossings logged by a
/// volunteer offline. Mirrors [LocalGearStore]'s pattern: one JSON file per
/// row under `<appDocs>/crossings/`, an in-memory `ChangeNotifier` so the
/// check-in screen refreshes on every stamp, and an on-demand drain
/// (connectivity return / pull-to-refresh) through the single-writer RPC.
///
/// The per-row sync-state machine (load / persist / drain / crash-atomic
/// rewrite / UUID mint) lives in [OfflineSyncStore]; this class supplies the
/// crossing-specific create / replace-from-server logic.
///
/// Offline contract:
/// - `createLocal` mints a v4 UUID and marks the row pendingCreate. Each stamp
///   (IN, then OUT later) is its own `createLocal` — the server-side RPC merges
///   them (earliest in, latest out) onto one canonical row, so the client never
///   resolves the conflict and there is no edit path. A re-stamp of an
///   already-pending row is also just another pendingCreate that the server
///   collapses.
/// - `pushCreate` calls `api.upsertCheckpointCrossing(...)`.
/// - `syncWithServer(api)` drains every pendingCreate row through the RPC with
///   per-row failure isolation; a failed push stays pending for the next drain.
class LocalCrossingsStore extends OfflineSyncStore<StoredCrossing> {
  @override
  String get storeSubdir => 'crossings';

  @override
  String get debugLabel => 'local_crossings_store';

  @override
  StoredCrossing entryFromJson(Map<String, dynamic> json) =>
      StoredCrossing.fromJson(json);

  // No windowed surface — the index is only a cold-load fast path, so
  // [summaryTimestampKey] stays null (the base default).
  @override
  Map<String, dynamic> summaryOf(StoredCrossing entry) => {
        'id': entry.id,
        'sync_state': entry.syncState.wire,
        'checkpoint_id': entry.row['checkpoint_id'],
        'bib': entry.row['bib'],
        'user_id': entry.row['user_id'],
      };

  @override
  StoredCrossing asSynced(StoredCrossing entry) => StoredCrossing(
        row: entry.row,
        syncState: SyncState.synced,
        lastModifiedAt: entry.lastModifiedAt,
      );

  @override
  StoredCrossing asPendingCreate(StoredCrossing entry) => StoredCrossing(
        row: entry.row,
        syncState: SyncState.pendingCreate,
        lastModifiedAt: entry.lastModifiedAt,
      );

  /// Read-only snapshot of the live rows (excludes tombstones).
  List<Map<String, dynamic>> get rows => rowsById.values
      .where((c) => !c.isTombstone)
      .map((c) => c.row)
      .toList();

  /// Crossings logged for one checkpoint at one event instance (live rows
  /// only), so the screen can show who's already been stamped here.
  List<Map<String, dynamic>> rowsForCheckpoint(
    String eventId,
    String checkpointId,
    DateTime instanceStart,
  ) {
    final at = instanceStart.toUtc();
    return rows
        .where((r) =>
            r['event_id'] == eventId &&
            r['checkpoint_id'] == checkpointId &&
            sameInstance(r['instance_start'], at))
        .toList();
  }

  /// Mint a UUID and persist a pending-create crossing. Identity is
  /// account-optional: pass [userId] OR [bib] + [runnerName]. The health
  /// fields ([bodyWeightKg] / [bodyWeightPct] / [medicalHold] / [medicalNote])
  /// travel with [healthConsent] — the server drops them unless the checkpoint
  /// requires a weigh-in AND consent is true (fail-closed, §150). Returns the
  /// stored shape so the caller can render it immediately.
  Future<StoredCrossing> createLocal({
    required String eventId,
    required String checkpointId,
    required DateTime instanceStart,
    String? userId,
    String? bib,
    String? runnerName,
    DateTime? inTime,
    DateTime? outTime,
    bool healthConsent = false,
    double? bodyWeightKg,
    double? bodyWeightPct,
    bool? medicalHold,
    String? medicalNote,
  }) async {
    final id = OfflineSyncStore.newUuid();
    final now = DateTime.now().toUtc();
    final row = <String, dynamic>{
      'id': id,
      'event_id': eventId,
      'checkpoint_id': checkpointId,
      'instance_start': instanceStartKey(instanceStart),
      'user_id': userId,
      'bib': bib,
      'runner_name': runnerName,
      'in_time': inTime?.toIso8601String(),
      'out_time': outTime?.toIso8601String(),
      'health_consent': healthConsent,
      'body_weight_kg': bodyWeightKg,
      'body_weight_pct': bodyWeightPct,
      'medical_hold': medicalHold,
      'medical_note': medicalNote,
      'recorded_at': now.toIso8601String(),
    };
    final stored = StoredCrossing(
      row: row,
      syncState: SyncState.pendingCreate,
      lastModifiedAt: now,
    );
    await persist(stored);
    return stored;
  }

  /// How long a SYNCED crossing is kept in the local cache, measured from its
  /// `recorded_at`. 90 days mirrors the server-side Art 9 scrub window on
  /// `checkpoint_crossings.recorded_at` (migration `20270317_001`): by the time
  /// the server has stripped the weigh-in fields, a phone-side copy of a
  /// months-old race has no operational purpose left. Deliberately generous —
  /// a crossing is race-day evidence, and a multi-day event plus its
  /// incident-review tail must fit comfortably inside the window.
  ///
  /// A crossing that has NOT been pushed is never eligible: an unsynced stamp
  /// is unsent data and is the only copy that exists, however long the
  /// volunteer stays offline.
  static const Duration kSyncedRetention = Duration(days: 90);

  /// Replace the in-memory state from a fresh server fetch (non-health
  /// columns). Pending rows are preserved as-is — only `synced` rows are
  /// overwritten so an offline stamp isn't clobbered by the server's copy.
  ///
  /// This is also where [kSyncedRetention] is applied: the whole live set is
  /// rebuilt here and written back by [rewriteAll], so dropping an expired
  /// synced crossing during the rebuild both evicts it from memory and deletes
  /// its file (it simply isn't in the keep-set). A crossing whose `recorded_at`
  /// can't be parsed is kept — an undatable audit record is never assumed old.
  ///
  /// [eventId] / [instanceStart] scope the prune to the rows the fetch could
  /// actually have returned — mirroring the `windowStart` / `fetchLimit` guard
  /// [LocalGymStore.replaceFromServer] carries. A synced row outside that scope
  /// is absent from [serverRows] because it was not asked for, NOT because the
  /// server deleted it; pruning it strands the volunteer with an empty
  /// "already stamped here" list for every other aid station, offline, which is
  /// the entire reason this store exists. Both null = full replace, correct
  /// only when the caller fetched the COMPLETE set.
  Future<void> replaceFromServer(
    List<Map<String, dynamic>> serverRows, {
    String? eventId,
    DateTime? instanceStart,
  }) async {
    requireInitialised('replaceFromServer');
    final now = DateTime.now().toUtc();
    final at = instanceStart?.toUtc();
    bool outOfScope(Map<String, dynamic> row) =>
        eventId != null &&
        (row['event_id'] != eventId ||
            (at != null && !sameInstance(row['instance_start'], at)));
    final preserved = <String, StoredCrossing>{};
    for (final entry in rowsById.entries) {
      if (entry.value.syncState != SyncState.synced) {
        preserved[entry.key] = entry.value;
        continue;
      }
      if (!outOfScope(entry.value.row)) continue;
      // Retention still runs over the rows the fetch didn't cover, or the
      // 90-day Art 9 mirror would silently stop expiring every other event.
      if (_beyondRetention(entry.value.row['recorded_at'], now)) continue;
      preserved[entry.key] = entry.value;
    }
    rowsById.clear();
    for (final row in serverRows) {
      final id = row['id'] as String;
      if (preserved.containsKey(id)) {
        rowsById[id] = preserved.remove(id)!;
        continue;
      }
      if (_beyondRetention(row['recorded_at'], now)) continue;
      rowsById[id] = StoredCrossing(row: row, syncState: SyncState.synced);
    }
    rowsById.addAll(preserved);
    await rewriteAll();
    notifyListeners();
  }

  static bool _beyondRetention(dynamic recordedAt, DateTime now) {
    final at = parseServerTimestamp(recordedAt);
    if (at == null) return false;
    return now.difference(at) > kSyncedRetention;
  }

  @override
  Future<void> pushCreate(ApiClient api, StoredCrossing stored) =>
      api.upsertCheckpointCrossing(
        eventId: stored.row['event_id'] as String,
        checkpointId: stored.row['checkpoint_id'] as String,
        // A row written before § 1343 carries the unnormalised local wall
        // clock; reading it back through [parseServerTimestamp] recovers the
        // instant that produced it, and [instanceStartKey] then sends what
        // every other writer of the key now sends. A crossing whose stored
        // instance is unreadable is refused rather than filed under a guessed
        // occurrence — the drain isolates the failure per row and the stamp
        // stays pending.
        instanceStart: parseServerTimestamp(stored.row['instance_start']) ??
            (throw StateError(
                'local_crossings_store: crossing ${stored.id} has no readable '
                'instance_start')),
        userId: stored.row['user_id'] as String?,
        bib: stored.row['bib'] as String?,
        runnerName: stored.row['runner_name'] as String?,
        inTime: parseServerTimestamp(stored.row['in_time']),
        outTime: parseServerTimestamp(stored.row['out_time']),
        healthConsent: (stored.row['health_consent'] as bool?) ?? false,
        bodyWeightKg: (stored.row['body_weight_kg'] as num?)?.toDouble(),
        bodyWeightPct: (stored.row['body_weight_pct'] as num?)?.toDouble(),
        medicalHold: stored.row['medical_hold'] as bool?,
        medicalNote: stored.row['medical_note'] as String?,
      );

  // A crossing is only ever created + merged server-side; there is no client
  // update or delete path (a re-stamp is another pendingCreate). The base
  // drain still needs these hooks, so they no-op.
  @override
  Future<void> pushUpdate(ApiClient api, StoredCrossing stored) =>
      pushCreate(api, stored);

  @override
  Future<void> pushDelete(ApiClient api, StoredCrossing stored) async {}
}
