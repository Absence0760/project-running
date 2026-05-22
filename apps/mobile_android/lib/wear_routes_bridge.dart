import 'dart:async';
import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_route_store.dart';

/// Pushes the user's starred routes to the paired Wear OS watch whenever
/// the local route store changes. Mirrors `WearAuthBridge` — same pattern,
/// different path. Without this, the watch picker is online-only at
/// run-start time: it fetches starred routes via Supabase every time the
/// pre-run screen opens, and a watch out of network range falls back to
/// whatever was cached the last time it had connectivity. With this bridge,
/// the phone forwards the freshly-starred set over the Wearable Data Layer
/// the moment the user stars on the phone — the watch's local cache is
/// always at most one phone-DataLayer hop behind.
///
/// Only **starred** routes are pushed — the same filter the watch picker
/// applies server-side (`is_starred=eq.true`). Offline-pinned routes that
/// aren't starred stay phone-only; pin gates "kept on this phone", star
/// gates "shown on the watch".
class WearRoutesBridge {
  static const _channel = MethodChannel('run_app/wear_routes');

  /// Wearable Data Layer caps a single DataItem at ~100 KB. At ~2 KB
  /// per route (id + name + waypoints × 8 bytes for lat + lng each,
  /// plus JSON overhead), 50 routes comfortably fits under that
  /// ceiling with headroom for unusually-long route names. The watch
  /// picker already caps its server-side fetch at 30 starred routes
  /// (`is_starred=eq.true&limit=30`); 50 here gives the phone push a
  /// little more — enough that the bridge isn't the limiting factor
  /// when the picker someday lifts its own cap. Routes beyond the
  /// cap are dropped from the push silently; `LocalRouteStore` still
  /// holds the full set on the phone.
  @visibleForTesting
  static const kMaxRoutesPerPush = 50;

  LocalRouteStore? _store;
  VoidCallback? _listener;

  /// Subscribe to the local route store and push the starred subset on
  /// every change. Idempotent — a second `attach` (e.g. after a hot
  /// restart) replaces the prior subscription rather than leaking it.
  void attach(LocalRouteStore store) {
    detach();
    _store = store;
    _listener = () => _push(store);
    store.addListener(_listener!);
    _push(store);
  }

  void detach() {
    final s = _store;
    final l = _listener;
    if (s != null && l != null) s.removeListener(l);
    _store = null;
    _listener = null;
  }

  Future<void> _push(LocalRouteStore store) async {
    final selected =
        pickRoutesForWatchPush(store.routes, maxRoutes: kMaxRoutesPerPush);
    final payload = encodeRoutesForWatch(selected);
    try {
      await _channel.invokeMethod<void>('push', {
        'routes_json': jsonEncode(payload),
        // Stamped so the watch can decide whether a freshly-received
        // push is newer than its current cache without comparing the
        // payload byte-for-byte. Wearable DataLayer dedups identical
        // DataMaps server-side, but the timestamp lets the watch
        // ignore stale pushes that arrive out of order — see
        // `RoutesBridge.events` on the watch side.
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
    } on PlatformException {
      // Wearable Data Layer unavailable (no Google Play services on the
      // device). Silently ignore — phone-only behaviour is unaffected.
    } on MissingPluginException {
      // Not running on Android, or the native plugin hasn't registered
      // yet. iOS doesn't yet have a paired Wear OS watch surface.
    }
  }

  /// Filter the local route set to the subset the watch picker
  /// surfaces — starred-only — and cap at [maxRoutes]. Power users
  /// with hundreds of starred routes would otherwise overflow the
  /// Wearable DataLayer's ~100 KB per-DataItem ceiling and the
  /// entire push would silently fail. The cap keeps the per-push
  /// payload bounded; routes beyond the cap stay on the phone and
  /// the watch sees the most-recent [maxRoutes].
  ///
  /// Ordering: `LocalRouteStore.routes` is newest-first by insertion
  /// (see `save()` / `saveBatch()` which both `insert(0, route)`),
  /// so taking the first [maxRoutes] starred entries keeps the most
  /// recently-touched routes on the watch — same intent as the
  /// watch picker's `order=updated_at.desc` server query.
  @visibleForTesting
  static List<Route> pickRoutesForWatchPush(
    List<Route> routes, {
    int maxRoutes = kMaxRoutesPerPush,
  }) {
    final starred = routes.where((r) => r.isStarred).toList(growable: false);
    if (starred.length <= maxRoutes) return starred;
    return starred.sublist(0, maxRoutes);
  }

  /// Convert a list of [Route]s into the JSON payload shape the
  /// watch parser (`parseRoutesJson` in `RoutesBridge.kt`) reads.
  /// Schema: `[{id, name, distance_m, waypoints:[{lat, lng}]}]`.
  /// Kept narrow — the watch picker only needs enough to render a
  /// row and feed `RouteMath` during recording; everything else
  /// (elevation, surface, tags) stays on the phone.
  @visibleForTesting
  static List<Map<String, Object>> encodeRoutesForWatch(List<Route> routes) {
    return [
      for (final r in routes)
        {
          'id': r.id,
          'name': r.name,
          'distance_m': r.distanceMetres,
          'waypoints': [
            for (final w in r.waypoints) {'lat': w.lat, 'lng': w.lng},
          ],
        },
    ];
  }
}
