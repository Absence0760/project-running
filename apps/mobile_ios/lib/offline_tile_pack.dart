import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

import 'tile_pack.dart';

/// Status of a route's offline tile pack.
enum OfflinePackStatus { absent, downloading, ready, partial, tooLarge }

/// Immutable snapshot of a pack's progress, surfaced to the UI.
class OfflinePackProgress {
  const OfflinePackProgress({
    required this.status,
    this.done = 0,
    this.total = 0,
    this.bytes = 0,
  });

  final OfflinePackStatus status;
  final int done;
  final int total;
  final int bytes;

  static const absent = OfflinePackProgress(status: OfflinePackStatus.absent);
}

/// Signature of the per-tile fetcher. Returns the raw tile bytes, or null when
/// the fetch failed (a 404, a network drop). Injected so tests can drive the
/// downloader without real HTTP. Production uses [_dioFetch] over the shared
/// tile-cache Dio.
typedef TileBytesFetcher = Future<Uint8List?> Function(String url);

/// Downloads + manages on-disk offline map-tile packs for saved routes.
///
/// A pack is the set of `{z}/{x}/{y}` raster tiles covering a route's bounding
/// box across the live map's zoom band, written to a directory that is a
/// **sibling** of the general LRU tile cache (`map_tiles`), so a pinned pack
/// is never LRU-evicted out from under a runner heading offline (decisions
/// §167). The live map checks this dir first for a followed route, then falls
/// through to the network/LRU cache (a read-through pack).
///
/// Layered resilience (L4): the downloader is an auxiliary effect. Every tile
/// fetch is wrapped in its own try/catch — a failed tile is skipped and the
/// pack completes partially (status `partial`, surfaced as "N of M cached,
/// retry") rather than aborting the whole pack or the pin toggle that
/// triggered it. A failed/partial pack never breaks the online map path.
class OfflineTilePackStore extends ChangeNotifier {
  OfflineTilePackStore({
    required this.tileUrlTemplate,
    TileBytesFetcher? fetcher,
  }) : _fetcher = fetcher ?? _dioFetch;

  /// The raster-tile URL template (`.../{z}/{x}/{y}...`) — resolve once at
  /// construction from the same source the live map uses so a pack matches
  /// the tiles the runner will actually render.
  final String tileUrlTemplate;
  final TileBytesFetcher _fetcher;

  Directory? _root;
  final Map<String, OfflinePackProgress> _packs = {};

  OfflinePackProgress progressFor(String routeId) =>
      _packs[routeId] ?? OfflinePackProgress.absent;

  /// Init the packs root + reconcile in-memory status with what's on disk so a
  /// cold start reflects already-downloaded packs. Best-effort.
  Future<void> init({Directory? overrideDirectory}) async {
    try {
      final Directory root;
      if (overrideDirectory != null) {
        root = overrideDirectory;
      } else {
        final cacheRoot = await getApplicationCacheDirectory();
        root = Directory('${cacheRoot.path}/offline_packs');
      }
      if (!root.existsSync()) root.createSync(recursive: true);
      _root = root;
      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        final routeId = entity.path.split(Platform.pathSeparator).last;
        final bytes = await _dirBytes(entity);
        final count = await _tileCount(entity);
        if (count > 0) {
          _packs[routeId] = OfflinePackProgress(
            status: OfflinePackStatus.ready,
            done: count,
            total: count,
            bytes: bytes,
          );
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('OfflineTilePackStore.init failed: $e');
    }
  }

  Future<Directory> _ensureRoot() async {
    final existing = _root;
    if (existing != null) return existing;
    final cacheRoot = await getApplicationCacheDirectory();
    final root = Directory('${cacheRoot.path}/offline_packs');
    if (!root.existsSync()) root.createSync(recursive: true);
    _root = root;
    return root;
  }

  Directory _packDir(Directory root, String routeId) =>
      Directory('${root.path}/$routeId');

  /// File path a tile is stored at inside a pack. Public so the live-map
  /// read-through can check the same location.
  File tileFile(Directory packDir, TileCoord t) =>
      File('${packDir.path}/${t.z}/${t.x}/${t.y}.png');

  /// Look up an on-disk tile for a followed route's pack, or null when the
  /// pack or tile is absent. The read-through entry point for the live map.
  Future<File?> cachedTile(String routeId, int z, int x, int y) async {
    final root = _root;
    if (root == null) return null;
    final f = tileFile(_packDir(root, routeId), TileCoord(z, x, y));
    return f.existsSync() ? f : null;
  }

  /// Download (or re-attempt) the tile pack covering [bbox] for [routeId].
  /// Skips tiles already on disk so a retry only fetches the gaps. Updates
  /// progress as it goes; settles on `ready` (every tile cached) or `partial`
  /// (some tile fetches failed). Throws nothing — caller-facing failures are
  /// reflected in the progress status.
  Future<void> downloadPack(
    String routeId,
    TileBbox bbox, {
    int minZoom = kDefaultMinZoom,
    int maxZoom = kDefaultMaxZoom,
  }) async {
    final List<TileCoord> tiles;
    try {
      tiles = tilesForBbox(bbox, minZoom: minZoom, maxZoom: maxZoom);
    } catch (e) {
      // Over the per-pack cap — surface "too large" rather than starting an
      // unbounded download.
      debugPrint('OfflineTilePackStore.downloadPack enumerate failed: $e');
      _packs[routeId] =
          const OfflinePackProgress(status: OfflinePackStatus.tooLarge);
      notifyListeners();
      return;
    }

    final root = await _ensureRoot();
    final dir = _packDir(root, routeId);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final total = tiles.length;
    var done = 0;
    var failed = 0;
    _packs[routeId] = OfflinePackProgress(
        status: OfflinePackStatus.downloading, done: 0, total: total);
    notifyListeners();

    for (final t in tiles) {
      final f = tileFile(dir, t);
      if (f.existsSync()) {
        done++;
        continue;
      }
      // L4: each tile fetch isolated — a failure skips this tile only.
      try {
        final url = _tileUrlFor(t);
        final bytes = await _fetcher(url);
        if (bytes != null && bytes.isNotEmpty) {
          await f.parent.create(recursive: true);
          await f.writeAsBytes(bytes, flush: true);
          done++;
        } else {
          failed++;
        }
      } catch (e) {
        debugPrint('OfflineTilePackStore tile fetch failed (${t.z}/${t.x}/${t.y}): $e');
        failed++;
      }
      // Throttle UI updates to ~every 16 tiles plus the final one.
      if (done % 16 == 0 || done + failed == total) {
        _packs[routeId] = OfflinePackProgress(
          status: OfflinePackStatus.downloading,
          done: done,
          total: total,
        );
        notifyListeners();
      }
    }

    final bytes = await _dirBytes(dir);
    _packs[routeId] = OfflinePackProgress(
      status: failed == 0
          ? OfflinePackStatus.ready
          : OfflinePackStatus.partial,
      done: done,
      total: total,
      bytes: bytes,
    );
    notifyListeners();
  }

  /// Delete a route's pack from disk (called when the offline pin is removed).
  Future<void> deletePack(String routeId) async {
    final root = _root;
    _packs.remove(routeId);
    notifyListeners();
    if (root == null) return;
    final dir = _packDir(root, routeId);
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('OfflineTilePackStore.deletePack failed: $e');
    }
  }

  String _tileUrlFor(TileCoord t) => tileUrlTemplate
      .replaceAll('{z}', '${t.z}')
      .replaceAll('{x}', '${t.x}')
      .replaceAll('{y}', '${t.y}');

  Future<int> _tileCount(Directory dir) async {
    var n = 0;
    try {
      await for (final e in dir.list(recursive: true)) {
        if (e is File && e.path.endsWith('.png')) n++;
      }
    } catch (e) {
      debugPrint('OfflineTilePackStore._tileCount failed: $e');
    }
    return n;
  }

  Future<int> _dirBytes(Directory dir) async {
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    } catch (e) {
      debugPrint('OfflineTilePackStore._dirBytes failed: $e');
    }
    return total;
  }
}

/// Read-through tile provider for a followed route: serves a tile from the
/// route's offline pack on disk when present, else delegates to [fallback]
/// (the normal network/LRU `CachedTileProvider`). A pinned pack thus renders
/// the map with zero connectivity, while an absent tile or an un-pinned route
/// falls through to the online path — fail-closed, never blocks the map.
class OfflinePackTileProvider extends TileProvider {
  OfflinePackTileProvider({
    required this.packDir,
    required this.fallback,
  });

  /// The route's pack directory (`offline_packs/<routeId>`). Tiles are at
  /// `{z}/{x}/{y}.png` inside it.
  final Directory packDir;
  final TileProvider fallback;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final f = File(
        '${packDir.path}/${coordinates.z}/${coordinates.x}/${coordinates.y}.png');
    if (f.existsSync()) {
      return FileImage(f);
    }
    return fallback.getImage(coordinates, options);
  }
}

/// Production tile fetcher over the shared tile-cache Dio. Returns null on any
/// non-200 / failure so the downloader treats it as a skippable miss.
Future<Uint8List?> _dioFetch(String url) async {
  try {
    final res = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    if (res.statusCode == 200 && data != null && data.isNotEmpty) {
      return Uint8List.fromList(data);
    }
    return null;
  } catch (_) {
    return null;
  }
}
