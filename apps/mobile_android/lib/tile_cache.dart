import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent on-disk cache for MapTiler tiles shared by every live map
/// instance in the app. Tiles survive across app launches — so the second
/// run in your neighbourhood renders the basemap with no network and the
/// first run's pre-cached tiles are still available even if the device is
/// offline when you start.
///
/// The store is initialised once from `main.dart` before `runApp`. Before
/// init (tests, hot reload from a cold start) the getters fall back to an
/// in-memory store so the widget still renders without crashing.
class TileCache {
  static CacheStore? _store;
  static Dio? _dio;

  /// Shared cache store. Falls back to an in-memory store with a modest
  /// budget when [init] hasn't run yet — used by widget tests and during
  /// the first frame before `main` finishes plumbing.
  static CacheStore get store =>
      _store ?? MemCacheStore(maxSize: 50 * 1024 * 1024);

  /// Dio instance wired to the current [store]. Reused across map
  /// instances so every tile request goes through the same cache.
  static Dio get dio => _dio ?? _buildDio(store);

  /// Initialise the disk-backed tile cache. Call from `main()` before
  /// `runApp`. Idempotent — subsequent calls are no-ops.
  static Future<void> init() async {
    if (_store != null) return;
    try {
      final cacheRoot = await getApplicationCacheDirectory();
      final tilesDir = Directory('${cacheRoot.path}/map_tiles');
      if (!tilesDir.existsSync()) {
        tilesDir.createSync(recursive: true);
      }
      _store = FileCacheStore(tilesDir.path);
      _dio = _buildDio(_store!);
    } catch (e) {
      // Fall back to in-memory on any platform issue (corrupt dir, plugin
      // channel failure during early startup). Map still works, just
      // loses persistence across launches.
      debugPrint('TileCache: disk init failed, using in-memory store: $e');
      _store = MemCacheStore(maxSize: 100 * 1024 * 1024);
      _dio = _buildDio(_store!);
    }
  }

  static Dio _buildDio(CacheStore store) {
    return Dio()
      ..interceptors.add(
        DioCacheInterceptor(
          options: CacheOptions(
            store: store,
            maxStale: const Duration(days: 30),
            policy: CachePolicy.forceCache,
          ),
        ),
      );
  }
}
