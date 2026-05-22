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

  /// How long the bridge waits after a [LocalRouteStore] notification
  /// before actually firing the push. Coalesces rapid bursts — when
  /// the user stars 10 routes in a row, this turns 10 individual
  /// pushes into 1. The diff cache catches identical re-payloads
  /// inside the window too.
  ///
  /// 250 ms is empirical: fast enough to feel real-time on the
  /// watch (a star tap → routes update in a quarter-second feels
  /// instant), slow enough to coalesce a tap storm or a bulk
  /// import landing routes one at a time.
  ///
  /// Set to zero for tests that need immediate-fire semantics.
  @visibleForTesting
  static Duration kPushDebounceWindow = const Duration(milliseconds: 250);

  LocalRouteStore? _store;
  VoidCallback? _listener;

  /// Pending debounced push. Cancelled on each new notification so
  /// the timer restarts; cancelled on [detach] so an in-flight push
  /// doesn't fire after the bridge stops.
  Timer? _pendingPush;

  /// Last encoded `routes_json` payload that the channel actually
  /// shipped. Used by the diff gate in [_push]: if the next
  /// computed payload matches byte-for-byte, the push is skipped.
  ///
  /// Why this matters: `LocalRouteStore.save()` fires for any
  /// route mutation — toggling `is_public`, adding a tag, editing
  /// description, etc. None of those change the watch-visible
  /// subset (starred id + name + distance + waypoints). Without
  /// the diff, every such edit shipped an identical-bytes push +
  /// woke the watch's DataClient listener for nothing. The cache
  /// turns those into local-only operations.
  ///
  /// Reset on [detach] so a re-attach pushes once for the new
  /// subscriber's benefit even if the subset is the same as
  /// before the detach.
  String? _lastPushedRoutesJson;

  /// Subscribe to the local route store and push the starred subset on
  /// every change. Idempotent — a second `attach` (e.g. after a hot
  /// restart) replaces the prior subscription rather than leaking it.
  ///
  /// The first push fires IMMEDIATELY (no debounce) so a freshly
  /// attached watch picker sees the current state without a
  /// quarter-second delay. Subsequent pushes go through the
  /// debounce window — see [kPushDebounceWindow].
  void attach(LocalRouteStore store) {
    detach();
    _store = store;
    _listener = () => _scheduleDebouncedPush(store);
    store.addListener(_listener!);
    _push(store);
  }

  void detach() {
    final s = _store;
    final l = _listener;
    if (s != null && l != null) s.removeListener(l);
    _store = null;
    _listener = null;
    // Cancel any pending debounced push so the bridge stops firing
    // immediately. Without this, a detach + immediate re-attach
    // could double-push (the old debounce fires AFTER the new
    // attach's initial push lands).
    _pendingPush?.cancel();
    _pendingPush = null;
    // Drop the diff cache so a fresh `attach` always pushes once,
    // even when the new subscription's starred set happens to
    // match what the previous one shipped. The bridge has no idea
    // whether the watch's view is still in sync after the detach
    // (e.g., a process restart could've happened on either side).
    _lastPushedRoutesJson = null;
  }

  /// Cancel any pending debounced push and schedule a fresh one
  /// [kPushDebounceWindow] from now. Each new notification restarts
  /// the timer, so rapid bursts (10 saves in 100 ms) coalesce into
  /// one push. When the window is `Duration.zero` (tests / future
  /// configuration), fires inline.
  void _scheduleDebouncedPush(LocalRouteStore store) {
    _pendingPush?.cancel();
    if (kPushDebounceWindow == Duration.zero) {
      // Test-only path — fires synchronously.
      _push(store);
      return;
    }
    _pendingPush = Timer(kPushDebounceWindow, () {
      _pendingPush = null;
      _push(store);
    });
  }

  Future<void> _push(LocalRouteStore store) async {
    final selected =
        pickRoutesForWatchPush(store.routes, maxRoutes: kMaxRoutesPerPush);
    final payload = encodeRoutesForWatch(selected);
    final routesJson = jsonEncode(payload);

    // Diff gate: skip when the payload is byte-equivalent to the
    // last one we shipped. `LocalRouteStore.save` notifies on
    // every route mutation; this drops the spurious wake-ups
    // (e.g. editing a route's description fires the listener but
    // doesn't change the starred subset). The watch's stale-push
    // gate would discard the redundant DataItem anyway, but
    // skipping at source saves the DataLayer hop + a watch CPU
    // wake. See [_lastPushedRoutesJson] for the lifecycle.
    if (routesJson == _lastPushedRoutesJson) return;

    try {
      await _channel.invokeMethod<void>('push', {
        'routes_json': routesJson,
        // Stamped so the watch can decide whether a freshly-received
        // push is newer than its current cache without comparing the
        // payload byte-for-byte. Wearable DataLayer dedups identical
        // DataMaps server-side, but the timestamp lets the watch
        // ignore stale pushes that arrive out of order — see
        // `RoutesBridge.events` on the watch side.
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
      // Only mark sent on success — a swallowed exception means the
      // channel never delivered the payload; the next save attempt
      // should fire again so the watch has a chance to catch up.
      _lastPushedRoutesJson = routesJson;
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
