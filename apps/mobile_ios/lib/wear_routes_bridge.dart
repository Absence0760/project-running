import 'dart:async';
import 'dart:convert';

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
    final starred = store.routes.where((r) => r.isStarred).toList();
    final payload = starred.map((r) {
      return {
        'id': r.id,
        'name': r.name,
        'distance_m': r.distanceMetres,
        'waypoints': r.waypoints
            .map((w) => {'lat': w.lat, 'lng': w.lng})
            .toList(),
      };
    }).toList();
    try {
      await _channel.invokeMethod<void>('push', {
        'routes_json': jsonEncode(payload),
        // Stamped so the watch can decide whether a freshly-received
        // push is newer than its current cache without comparing the
        // payload byte-for-byte. Wearable DataLayer dedups identical
        // DataMaps server-side, but the timestamp lets the watch log
        // sync staleness if needed.
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
}
