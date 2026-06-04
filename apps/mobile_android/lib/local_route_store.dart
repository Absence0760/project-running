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

  List<Route> get routes => List.unmodifiable(_routes);

  /// Routes that need to be pushed to the cloud on the next sync
  /// trigger. Empty when the user is fully synced.
  List<Route> get unsyncedRoutes =>
      _routes.where((r) => !_syncedIds.contains(r.id)).toList();

  int get unsyncedCount => unsyncedRoutes.length;

  /// True when [routeId] is present locally and has NOT been confirmed
  /// pushed to the cloud — i.e. it carries a pending local edit. Used by
  /// [saveBatch] to keep a server ingest from clobbering an unsynced edit.
  bool _hasUnsyncedLocalEdit(String routeId) =>
      _routes.any((r) => r.id == routeId) && !_syncedIds.contains(routeId);

  /// Unmodifiable snapshot of every route the user has pinned for
  /// offline access. Order matches `_routes` (newest-first).
  List<Route> get offlinePinnedRoutes => List.unmodifiable(
        _routes.where((r) => _offlinePinnedIds.contains(r.id)),
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
    } else {
      // User-created route — clear the synced flag if it was set
      // previously (rare, but a future "edit + re-save" path should
      // re-queue the cloud push).
      _syncedIds.remove(route.id);
    }
    // Always persist so a cold-start can distinguish "tracking is
    // active but nothing's synced yet" (sidecar exists, empty list)
    // from "no sidecar yet, upgrade path" (sidecar absent). Without
    // this, the first unsynced save would never write the sidecar
    // and the cold-start would falsely promote the new route to
    // synced via the upgrade-safety default.
    await _persistSyncedIds();
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
    } else {
      _syncedIds.removeAll(list.map((r) => r.id));
    }
    await _persistSyncedIds();
    notifyListeners();
  }

  /// Mark a route as confirmed-pushed to the cloud. Called by
  /// [SyncService] after a successful `api.saveRoute(...)`.
  Future<void> markRouteSynced(String routeId) async {
    if (_syncedIds.add(routeId)) {
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
    await _persistSyncedIds();
    notifyListeners();
  }

  Future<void> delete(String routeId) async {
    final dir = await _ensureDir();
    final file = File('${dir.path}/$routeId.json');
    if (file.existsSync()) await file.delete();
    _routes.removeWhere((r) => r.id == routeId);
    if (_syncedIds.remove(routeId)) {
      await _persistSyncedIds();
    }
    if (_offlinePinnedIds.remove(routeId)) {
      await _persistOfflinePinnedIds();
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
    _syncedIds.removeAll(ids);
    _offlinePinnedIds.removeAll(ids);
    if (touchedSynced) await _persistSyncedIds();
    if (touchedPinned) await _persistOfflinePinnedIds();
    notifyListeners();
  }

  /// Mark a route as kept-on-device. The pin is local-only — never
  /// pushed to Supabase. Idempotent (re-pinning is a no-op).
  Future<void> pinOffline(String routeId) async {
    if (!_offlinePinnedIds.add(routeId)) return;
    await _persistOfflinePinnedIds();
    notifyListeners();
  }

  Future<void> unpinOffline(String routeId) async {
    if (!_offlinePinnedIds.remove(routeId)) return;
    await _persistOfflinePinnedIds();
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
        .where((f) => !f.path.endsWith(_syncedIdsFilename))
        .where((f) => !f.path.endsWith(_offlinePinnedIdsFilename))
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
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw);
      if (data is Map && data['ids'] is List) {
        for (final id in data['ids'] as List) {
          if (id is String) _syncedIds.add(id);
        }
      }
    } catch (e) {
      debugPrint('Failed to load synced route ids sidecar: $e');
    }
  }

  Future<void> _persistSyncedIds() async {
    try {
      await writeJsonAtomic(_syncedIdsFile, {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'ids': _syncedIds.toList(),
      });
    } catch (e) {
      // Not fatal — the in-memory set is still correct for this
      // session; the next sync attempt will write it again.
      debugPrint('Failed to persist synced route ids sidecar: $e');
    }
  }

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
    // Chain onto the previous write so concurrent calls serialise. Each
    // write snapshots the set at execution time, so once the in-memory
    // mutations have settled the final write matches the final state.
    _offlinePersistChain = _offlinePersistChain.then((_) async {
      try {
        await writeJsonAtomic(_offlinePinnedIdsFile, {
          kLocalStoreVersionKey: kLocalStoreSchemaVersion,
          'ids': _offlinePinnedIds.toList(),
        });
      } catch (e) {
        debugPrint('Failed to persist offline pinned route ids sidecar: $e');
      }
    });
    return _offlinePersistChain;
  }
}
