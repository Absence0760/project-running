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

  /// Sidecar set of route IDs that have been confirmed pushed to the
  /// cloud. Routes whose id is NOT in this set are queued for the
  /// next [SyncService] cycle. Mirrors `LocalRunStore._syncedIds` so
  /// the route-creation flow can save offline (signed-out, network
  /// down, Supabase init failed) and the route is preserved on disk
  /// regardless of cloud success.
  final Set<String> _syncedIds = {};
  static const _syncedIdsFilename = 'synced_route_ids.json';
  File get _syncedIdsFile => File('${_dir!.path}/$_syncedIdsFilename');

  /// Ids this process has deliberately dropped from [_syncedIds] (or
  /// [_offlinePinnedIds]) since its last successful sidecar write. The merge
  /// can't read a removal out of absence — absence equally means "the other
  /// isolate hasn't heard of it yet" — so removals travel explicitly while
  /// additions always win. Mirrors `LocalRunStore._clearedRemoteDeletes`.
  final Set<String> _syncedIdsCleared = {};
  final Set<String> _offlinePinnedCleared = {};

  /// Route ids whose owner tag this process has set or dropped since its last
  /// successful `route_owner_tags.json` write — the same ledger idea, for a
  /// map: only these keys override the on-disk map.
  final Set<String> _ownerTagsTouched = {};

  /// Per-device "save for offline" pins. A pinned route is one the
  /// user has explicitly marked to keep on this phone — surfaces a
  /// download_done badge in the routes list, and (forward-looking)
  /// would survive any future LRU eviction the route cache grows.
  /// Local-only: not synced to Supabase. A starred route gates what
  /// shows up on the watch picker; an offline-pinned route gates
  /// what stays on this device.
  final Set<String> _offlinePinnedIds = {};
  // Serialises sidecar writes: concurrent pin/unpin calls each await this
  // tail, so writes apply in call order and the last one to land reflects
  // the latest in-memory state (otherwise overlapping writeAsString calls
  // can finish out of order and leave the on-disk set stale).
  Future<void> _offlinePersistChain = Future<void>.value();
  static const _offlinePinnedIdsFilename = 'offline_pinned_route_ids.json';
  File get _offlinePinnedIdsFile =>
      File('${_dir!.path}/$_offlinePinnedIdsFilename');

  /// Device-local map of route id → the ACCOUNT that saved it into this
  /// store ('' = saved while signed out). Distinct from `Route.userId`,
  /// which names the route's CREATOR — a bookmarked community route
  /// carries someone else's userId but belongs to whoever bookmarked it.
  /// This is the routes counterpart of the §67 run tag
  /// (`metadata.created_by_user_id`): the store is deliberately NOT wiped
  /// on sign-out (an unsynced route built offline must survive, like an
  /// unsynced run), so the tag is what keeps user A's local library from
  /// rendering for — or sync-pushing under — user B on a shared device
  /// (issue #229). Untagged rows (pre-upgrade files, signed-out saves)
  /// stay visible to every account and are adopted on push, mirroring
  /// the §67 null-owner policy.
  final Map<String, String> _ownerTags = {};
  static const _ownerTagsFilename = 'route_owner_tags.json';
  File get _ownerTagsFile => File('${_dir!.path}/$_ownerTagsFilename');

  /// Session provider, same idiom as `LocalRunStore.currentUserIdProvider`
  /// (§67): wired once in main.dart to `() => api?.userId`, read at each
  /// save (stamp) and each getter (filter). Null / unset = signed out —
  /// only untagged rows are visible.
  String? Function()? currentUserIdProvider;

  String? get _activeOwner {
    final uid = currentUserIdProvider?.call();
    return (uid == null || uid.isEmpty) ? null : uid;
  }

  bool _visibleToActiveOwner(String routeId) {
    final tag = _ownerTags[routeId] ?? '';
    if (tag.isEmpty) return true;
    // An UNWIRED provider (tests, pre-bootstrap) means no filtering; a
    // wired provider returning null means signed out — tagged rows hide.
    if (currentUserIdProvider == null) return true;
    return tag == _activeOwner;
  }

  void _stampOwner(String routeId) {
    final active = _activeOwner;
    if (active != null) {
      // Last-account-to-save wins: a route two accounts both bookmark is
      // re-tagged by whichever account hydrates it, and self-heals on the
      // other account's next server hydrate.
      _ownerTags[routeId] = active;
    } else {
      _ownerTags.putIfAbsent(routeId, () => '');
    }
    _ownerTagsTouched.add(routeId);
  }

  List<Route> get routes => List.unmodifiable(
        _routes.where((r) => _visibleToActiveOwner(r.id)),
      );

  /// Routes that need to be pushed to the cloud on the next sync
  /// trigger. Empty when the user is fully synced. Owner-filtered like
  /// [routes]: another account's unsynced routes must never drain into
  /// the active account (the display-side twin of §67's push filter).
  List<Route> get unsyncedRoutes => _routes
      .where((r) =>
          !_syncedIds.contains(r.id) && _visibleToActiveOwner(r.id))
      .toList();

  int get unsyncedCount => unsyncedRoutes.length;

  /// True when [routeId] is present locally and has NOT been confirmed
  /// pushed to the cloud — i.e. it carries a pending local edit. Used by
  /// [saveBatch] to keep a server ingest from clobbering an unsynced edit.
  bool _hasUnsyncedLocalEdit(String routeId) =>
      _routes.any((r) => r.id == routeId) && !_syncedIds.contains(routeId);

  /// Unmodifiable snapshot of every route the user has pinned for
  /// offline access. Order matches `_routes` (newest-first).
  List<Route> get offlinePinnedRoutes => List.unmodifiable(
        _routes.where((r) =>
            _offlinePinnedIds.contains(r.id) && _visibleToActiveOwner(r.id)),
      );

  bool isOfflinePinned(String routeId) => _offlinePinnedIds.contains(routeId);

  Set<String> get offlinePinnedIds => Set.unmodifiable(_offlinePinnedIds);

  /// Test-only seed that populates the in-memory list directly,
  /// bypassing `init()` + `_loadAll()`. Mirrors `LocalRunStore.debugSeed`
  /// — same flutter_test fake-async hazard. Production code never
  /// touches it.
  @visibleForTesting
  void debugSeed(Iterable<Route> routes, {Directory? dir, bool markSynced = true}) {
    if (dir != null) _dir = dir;
    _routes = List<Route>.from(routes);
    if (markSynced) {
      _syncedIds
        ..clear()
        ..addAll(_routes.map((r) => r.id));
    }
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
    await _loadSyncedIds();
    await _loadOfflinePinnedIds();
    await _loadOwnerTags();
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

  /// Persist [route] to disk. By default marks it **unsynced** so the
  /// next [SyncService] cycle pushes it to the cloud — the canonical
  /// path for user-created routes from the in-app builder.
  ///
  /// Pass [markSynced]: true when the route is already known to exist
  /// in the cloud (e.g. a server-pulled route landing in the store
  /// via `saveBatch` after a remote fetch). Without that override
  /// every refresh would re-push every route the next sync cycle.
  /// The on-disk record for a route: the route JSON plus the schema-version
  /// stamp. The stamp is a flat key — `Route.fromJson` ignores unrecognised
  /// keys, so legacy bare-route files still parse and stamped files lose
  /// nothing.
  Map<String, dynamic> _routeRecord(Route route) => {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        ...route.toJson(),
      };

  Future<void> save(Route route, {bool markSynced = false}) async {
    final dir = await _ensureDir();
    final file = File('${dir.path}/${route.id}.json');
    await writeJsonAtomic(file, _routeRecord(route));
    _routes.removeWhere((r) => r.id == route.id);
    _routes.insert(0, route);
    if (markSynced) {
      _syncedIds.add(route.id);
      _syncedIdsCleared.remove(route.id);
    } else {
      // User-created route — clear the synced flag if it was set
      // previously (rare, but a future "edit + re-save" path should
      // re-queue the cloud push).
      _syncedIds.remove(route.id);
      _syncedIdsCleared.add(route.id);
    }
    // Always persist so a cold-start can distinguish "tracking is
    // active but nothing's synced yet" (sidecar exists, empty list)
    // from "no sidecar yet, upgrade path" (sidecar absent). Without
    // this, the first unsynced save would never write the sidecar
    // and the cold-start would falsely promote the new route to
    // synced via the upgrade-safety default.
    await _persistSyncedIds();
    _stampOwner(route.id);
    await _persistOwnerTags();
    notifyListeners();
  }

  /// Bulk variant of [save] — writes every file in parallel and only
  /// notifies once. Used by the routes screen's remote-sync path so a
  /// 100-route pull doesn't fire 100 listener callbacks (each rebuilding
  /// the list). Server-pulled routes are already in the cloud, so the
  /// default here is [markSynced]=true (opposite of [save] — keeps the
  /// remote-pull path from re-pushing routes on the next sync).
  Future<void> saveBatch(
    Iterable<Route> routes, {
    bool markSynced = true,
  }) async {
    if (routes.isEmpty) return;
    // Server-ingest path (markSynced): never clobber a route that has
    // unsynced local edits. Overwriting it with the server's (possibly
    // older) copy AND flagging it synced would silently drop the pending
    // push and revert the edit — the route-store equivalent of the
    // newer-wins guard the per-row stores apply. Routes carry no per-row
    // modification clock, so the sidecar sync-state is the conflict
    // signal: an unsynced local route is the pending side and wins; a
    // clean copy (synced, or not present locally) takes the server
    // version. The non-markSynced path is a local save and is unaffected.
    final list = markSynced
        ? routes.where((r) => !_hasUnsyncedLocalEdit(r.id)).toList()
        : routes.toList();
    if (list.isEmpty) return;
    final dir = await _ensureDir();
    await Future.wait(list.map((route) {
      final file = File('${dir.path}/${route.id}.json');
      return writeJsonAtomic(file, _routeRecord(route));
    }));
    for (final route in list) {
      _routes.removeWhere((r) => r.id == route.id);
      _routes.insert(0, route);
    }
    if (markSynced) {
      _syncedIds.addAll(list.map((r) => r.id));
      _syncedIdsCleared.removeAll(list.map((r) => r.id));
    } else {
      _syncedIds.removeAll(list.map((r) => r.id));
      _syncedIdsCleared.addAll(list.map((r) => r.id));
    }
    await _persistSyncedIds();
    for (final route in list) {
      _stampOwner(route.id);
    }
    await _persistOwnerTags();
    notifyListeners();
  }

  /// Mark a route as confirmed-pushed to the cloud. Called by
  /// [SyncService] after a successful `api.saveRoute(...)`.
  Future<void> markRouteSynced(String routeId) async {
    if (_syncedIds.add(routeId)) {
      _syncedIdsCleared.remove(routeId);
      await _persistSyncedIds();
      notifyListeners();
    }
  }

  /// Bulk variant for the drain loop — one sidecar write per batch.
  Future<void> markManyRoutesSynced(Iterable<String> routeIds) async {
    final added = <String>[];
    for (final id in routeIds) {
      if (_syncedIds.add(id)) added.add(id);
    }
    if (added.isEmpty) return;
    _syncedIdsCleared.removeAll(added);
    await _persistSyncedIds();
    notifyListeners();
  }

  /// Adoption stamp for the drain loop: after `api.saveRoute` lands an
  /// untagged (signed-out-built) route in [owner]'s account, tag it so
  /// it stops being visible to every other account on the device.
  /// Mirrors §67's push-time adoption of null-owner runs.
  Future<void> tagRoutesOwner(Iterable<String> routeIds, String owner) async {
    if (owner.isEmpty) return;
    var touched = false;
    for (final id in routeIds) {
      if (_ownerTags[id] != owner) {
        _ownerTags[id] = owner;
        _ownerTagsTouched.add(id);
        touched = true;
      }
    }
    if (!touched) return;
    await _persistOwnerTags();
    notifyListeners();
  }

  Future<void> delete(String routeId) async {
    final dir = await _ensureDir();
    final file = File('${dir.path}/$routeId.json');
    if (file.existsSync()) await file.delete();
    _routes.removeWhere((r) => r.id == routeId);
    if (_syncedIds.remove(routeId)) {
      _syncedIdsCleared.add(routeId);
      await _persistSyncedIds();
    }
    if (_offlinePinnedIds.remove(routeId)) {
      _offlinePinnedCleared.add(routeId);
      await _persistOfflinePinnedIds();
    }
    if (_ownerTags.remove(routeId) != null) {
      _ownerTagsTouched.add(routeId);
      await _persistOwnerTags();
    }
    notifyListeners();
  }

  /// Bulk-delete a set of routes. Used by the multi-select / bulk-
  /// delete UI on `routes_screen.dart`. Issues a single
  /// `notifyListeners()` call instead of one per row so the list
  /// doesn't flicker through N intermediate states. Idempotent on
  /// already-deleted ids (the per-id file delete is best-effort).
  Future<void> deleteMany(Iterable<String> routeIds) async {
    if (routeIds.isEmpty) return;
    final ids = routeIds.toSet();
    final dir = await _ensureDir();
    for (final id in ids) {
      final file = File('${dir.path}/$id.json');
      if (file.existsSync()) await file.delete();
    }
    _routes.removeWhere((r) => ids.contains(r.id));
    final touchedSynced = _syncedIds.intersection(ids).isNotEmpty;
    final touchedPinned = _offlinePinnedIds.intersection(ids).isNotEmpty;
    final touchedTags = ids.any(_ownerTags.containsKey);
    _syncedIds.removeAll(ids);
    _offlinePinnedIds.removeAll(ids);
    _ownerTags.removeWhere((id, _) => ids.contains(id));
    _syncedIdsCleared.addAll(ids);
    _offlinePinnedCleared.addAll(ids);
    _ownerTagsTouched.addAll(ids);
    if (touchedSynced) await _persistSyncedIds();
    if (touchedPinned) await _persistOfflinePinnedIds();
    if (touchedTags) await _persistOwnerTags();
    notifyListeners();
  }

  /// Mark a route as kept-on-device. The pin is local-only — never
  /// pushed to Supabase. Idempotent (re-pinning is a no-op).
  Future<void> pinOffline(String routeId) async {
    if (!_offlinePinnedIds.add(routeId)) return;
    _offlinePinnedCleared.remove(routeId);
    await _persistOfflinePinnedIds();
    notifyListeners();
  }

  Future<void> unpinOffline(String routeId) async {
    if (!_offlinePinnedIds.remove(routeId)) return;
    _offlinePinnedCleared.add(routeId);
    await _persistOfflinePinnedIds();
    notifyListeners();
  }

  Future<void> _loadAll() async {
    _routes = [];
    _syncedIdsCleared.clear();
    _offlinePinnedCleared.clear();
    _ownerTagsTouched.clear();
    final dir = _dir;
    if (dir == null) return; // init() not yet completed — nothing to load.
    sweepAtomicWriteOrphans(dir,
        onError: (m) => debugPrint('local_route_store: $m'));
    // listSync is intentional — see LocalRunStore._loadAll for the
    // explanation (async _dir.list() deadlocks under `testWidgets`).
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .where((f) => !f.path.endsWith(_syncedIdsFilename))
        .where((f) => !f.path.endsWith(_offlinePinnedIdsFilename))
        .where((f) => !f.path.endsWith(_ownerTagsFilename))
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
      // Forward-migration hook: v1 stamps `_v` as a flat key alongside the
      // route fields; legacy (v0) files are a bare Route.toJson(). Both
      // parse — Route.fromJson ignores the `_v` key — so the read is a
      // pass-through today. A future incompatible change bumps
      // kLocalStoreSchemaVersion and branches on this version.
      final version = localStoreRecordVersion(data);
      if (version > kLocalStoreSchemaVersion) {
        debugPrint(
            'local_route_store: ${file.path} has _v=$version (> $kLocalStoreSchemaVersion); reading known fields only');
      }
      return Route.fromJson(data);
    } catch (e) {
      debugPrint('Failed to load route file ${file.path}: $e');
      return null;
    }
  }

  /// On cold-start, restore the synced-ids sidecar. When the sidecar
  /// is absent (first run, or upgrading from a pre-sync-tracking
  /// build), default every existing route to synced — the routes were
  /// already on disk before sync tracking existed, so they're
  /// presumed-pushed. Without this, the first sync after upgrade
  /// would re-push the user's entire route library.
  Future<void> _loadSyncedIds() async {
    final dir = _dir;
    if (dir == null) return;
    _syncedIds.clear();
    final file = _syncedIdsFile;
    if (!file.existsSync()) {
      // Pre-existing routes count as synced for the upgrade path.
      _syncedIds.addAll(_routes.map((r) => r.id));
      return;
    }
    final parsed = await _readSyncedIdsFromDisk();
    if (parsed != null) {
      _syncedIds.addAll(parsed);
      return;
    }
    // Fail CLOSED to the same presumed-synced default the absent-file branch
    // uses. An empty set means "every route is unsynced", which makes
    // drainUnsyncedRoutes push the entire library and then tagRoutesOwner stamp
    // every pushed route as the CURRENT user — so on a shared device whose
    // routes are still untagged, an unreadable sidecar silently copies user A's
    // whole route library into user B's cloud account and drops it out of A's
    // local view. A re-push we skipped is recoverable; a cross-account transfer
    // is not.
    _syncedIds
      ..clear()
      ..addAll(_routes.map((r) => r.id));
  }

  /// Parse half of [_loadSyncedIds]: the ids the sidecar actually records, or
  /// null when the file is absent / unreadable / malformed. Deliberately
  /// WITHOUT the presumed-synced fallback, which belongs only on cold load —
  /// a merge that inherited it would mark every local route synced.
  Future<Set<String>?> _readSyncedIdsFromDisk() async {
    final file = _syncedIdsFile;
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data['ids'] is List) {
        return {
          for (final id in data['ids'] as List)
            if (id is String) id,
        };
      }
      debugPrint('Synced route ids sidecar has an unexpected shape');
    } catch (e) {
      debugPrint('Failed to load synced route ids sidecar: $e');
    }
    return null;
  }

  Future<Map<String, String>?> _readOwnerTagsFromDisk() async {
    final file = _ownerTagsFile;
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data['tags'] is Map) {
        final out = <String, String>{};
        (data['tags'] as Map).forEach((id, owner) {
          if (id is String && owner is String) out[id] = owner;
        });
        return out;
      }
    } catch (e) {
      debugPrint('Failed to load route owner tags sidecar: $e');
    }
    return null;
  }

  Future<Set<String>?> _readOfflinePinnedFromDisk() async {
    final file = _offlinePinnedIdsFile;
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data['ids'] is List) {
        return {
          for (final id in data['ids'] as List)
            if (id is String) id,
        };
      }
    } catch (e) {
      debugPrint('Failed to load offline pinned route ids sidecar: $e');
    }
    return null;
  }

  /// Hold an exclusive cross-process advisory lock on [name] for the duration
  /// of [action]. Ported verbatim from `LocalRunStore._withSidecarLock`:
  /// `background_sync.dart` builds a second [LocalRouteStore] over this same
  /// directory in the WorkManager isolate, so a read-modify-write of any
  /// sidecar needs the lock or two interleaved merges still drop the later
  /// writer's work. Best effort — if the lock can't be taken the action still
  /// runs, because a merged write without a lock beats no write at all.
  Future<void> _withSidecarLock(
      String name, Future<void> Function() action) async {
    final dir = await _ensureDir();
    RandomAccessFile? handle;
    try {
      handle = await File('${dir.path}/$name.lock').open(mode: FileMode.write);
      await handle.lock(FileLock.blockingExclusive);
    } catch (e) {
      debugPrint('local_route_store: sidecar lock unavailable for $name: $e');
      try {
        await handle?.close();
      } catch (_) {/* best-effort */}
      handle = null;
    }
    try {
      await action();
    } finally {
      if (handle != null) {
        try {
          await handle.unlock();
        } catch (e) {
          debugPrint('local_route_store: sidecar unlock failed for $name: $e');
        }
        try {
          await handle.close();
        } catch (_) {/* best-effort */}
      }
    }
  }

  /// Merge-write one id-set sidecar under its lock. [live] is this process's
  /// current set, [cleared] the ids it has deliberately dropped since the last
  /// successful write.
  ///
  /// Additions always win and removals travel by the explicit ledger, because
  /// absence on disk equally means "the other isolate hasn't heard of it yet".
  /// That asymmetry is the one the route store already chose on cold load
  /// (`_loadSyncedIds` fails closed to presumed-synced): a re-push we skipped
  /// is recoverable, a route pushed into the wrong cloud account is not.
  ///
  /// [pruneMissing] bounds sidecar growth the way
  /// `LocalRunStore._persistSyncedIds` does — an id for a route this process
  /// no longer holds AND whose file is gone is dropped. Off for the offline
  /// pins, which are a forward-looking intent set: pinning an id before its
  /// route lands is supported.
  Future<void> _persistIdSetSidecar({
    required String filename,
    required File file,
    required Set<String> live,
    required Set<String> cleared,
    required Future<Set<String>?> Function() readDisk,
    required bool pruneMissing,
  }) async {
    final dir = await _ensureDir();
    final known = _routes.map((r) => r.id).toSet();
    if (pruneMissing) live.retainWhere(known.contains);
    await _withSidecarLock(filename, () async {
      final merged = <String>{...live};
      for (final id in await readDisk() ?? const <String>{}) {
        if (cleared.contains(id)) continue;
        // An id this process has never heard of is the other isolate's newer
        // view; the route FILE is the process-independent liveness test.
        if (!pruneMissing ||
            known.contains(id) ||
            File('${dir.path}/$id.json').existsSync()) {
          merged.add(id);
        }
      }
      try {
        await writeJsonAtomic(file, {
          kLocalStoreVersionKey: kLocalStoreSchemaVersion,
          'ids': merged.toList(),
        });
        cleared.clear();
      } catch (e) {
        // Not fatal — the in-memory set is still correct for this
        // session; the next sync attempt will write it again.
        debugPrint('local_route_store: failed to persist $filename: $e');
      }
    });
  }

  Future<void> _persistSyncedIds() => _persistIdSetSidecar(
        filename: _syncedIdsFilename,
        file: _syncedIdsFile,
        live: _syncedIds,
        cleared: _syncedIdsCleared,
        readDisk: _readSyncedIdsFromDisk,
        pruneMissing: true,
      );

  Future<void> _loadOfflinePinnedIds() async {
    final dir = _dir;
    if (dir == null) return;
    _offlinePinnedIds.clear();
    final file = _offlinePinnedIdsFile;
    if (!file.existsSync()) return;
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw);
      if (data is Map && data['ids'] is List) {
        for (final id in data['ids'] as List) {
          if (id is String) _offlinePinnedIds.add(id);
        }
      }
    } catch (e) {
      debugPrint('Failed to load offline pinned route ids sidecar: $e');
    }
  }

  Future<void> _persistOfflinePinnedIds() {
    // Chain onto the previous write so concurrent calls serialise in-process;
    // the sidecar lock inside handles the cross-isolate half.
    _offlinePersistChain = _offlinePersistChain.then((_) => _persistIdSetSidecar(
          filename: _offlinePinnedIdsFilename,
          file: _offlinePinnedIdsFile,
          live: _offlinePinnedIds,
          cleared: _offlinePinnedCleared,
          readDisk: _readOfflinePinnedFromDisk,
          pruneMissing: false,
        ));
    return _offlinePersistChain;
  }

  /// Absent sidecar (first run, pre-tag upgrade) leaves the map empty:
  /// every existing route reads as untagged → visible to any account,
  /// the same presumed-shared default the §67 run tag chose.
  Future<void> _loadOwnerTags() async {
    final dir = _dir;
    if (dir == null) return;
    _ownerTags
      ..clear()
      ..addAll(await _readOwnerTagsFromDisk() ?? const <String, String>{});
  }

  /// Merge-write the §67 owner tags under the sidecar lock.
  ///
  /// A map can't carry removals in absence either, so only the keys this
  /// process actually touched override the on-disk map — otherwise a
  /// foreground `save()` from a snapshot taken before the WorkManager
  /// isolate's `tagRoutesOwner` reverts that route to untagged, and an
  /// untagged route is visible to (and drainable by) every account on a
  /// shared device. That is the unrecoverable direction: the next account's
  /// drain copies the other user's route into their cloud account.
  Future<void> _persistOwnerTags() async {
    final dir = await _ensureDir();
    await _withSidecarLock(_ownerTagsFilename, () async {
      final merged = <String, String>{
        ...?await _readOwnerTagsFromDisk(),
      };
      for (final id in _ownerTagsTouched) {
        final tag = _ownerTags[id];
        if (tag == null) {
          merged.remove(id);
        } else {
          merged[id] = tag;
        }
      }
      final known = _routes.map((r) => r.id).toSet();
      merged.removeWhere((id, _) =>
          !known.contains(id) && !File('${dir.path}/$id.json').existsSync());
      try {
        await writeJsonAtomic(_ownerTagsFile, {
          kLocalStoreVersionKey: kLocalStoreSchemaVersion,
          'tags': merged,
        });
        _ownerTagsTouched.clear();
      } catch (e) {
        // Not fatal — the in-memory map is still correct for this session.
        debugPrint('Failed to persist route owner tags sidecar: $e');
      }
    });
  }
}
