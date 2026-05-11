import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';

import 'live_hub_client.dart';

/// Pushes live spectator pings while a recording is in progress.
/// Throttled to one push every [_pingInterval], swallows network /
/// auth errors via `debugPrint` so the recorder's L0/L1 stays
/// untouched (see `docs/conventions.md § Layered resilience`).
///
/// Activated by the run screen when the user taps "Share live link";
/// inactive otherwise so a private run doesn't write to the
/// spectator table at all. The throttle window is intentionally
/// looser than the recorder's GPS cadence (1 s) — the spectator UI
/// is a glanceable surface, not a bit-for-bit replay.
///
/// Transport:
/// - When [hubClient] is non-null and [LiveHubClient.isConfigured]
///   is true (deploy sets `LIVE_HUB_URL` in `dotenv.env`), pings
///   POST to the Go live hub via the hub client. The hub fans out
///   to subscribed spectators in real-time and stores the last
///   known position for late joiners. No Postgres / Realtime
///   involved.
/// - Otherwise the broadcaster falls back to the legacy path —
///   `ApiClient.insertLivePing` writes a row to `live_run_pings`
///   and Supabase Realtime fans out to the web spectator page.
///
/// The fallback keeps the feature usable on every build pre-deploy
/// and during a Fly.io outage. See `docs/followups.md § #13` for
/// the migration plan.
class LiveBroadcaster {
  LiveBroadcaster(this._api, {this.hubClient});

  final ApiClient _api;
  final LiveHubClient? hubClient;

  String? _runId;
  bool _active = false;
  DateTime _lastPingAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _pingInterval = Duration(seconds: 5);

  bool get isActive => _active;
  String? get runId => _runId;

  /// Mark the broadcaster as live for [runId]. Caller must have
  /// already pre-created the parent `runs` row via
  /// [ApiClient.beginLiveBroadcast] — this method does not retry
  /// the stub creation.
  void attach(String runId) {
    _runId = runId;
    _active = true;
    _lastPingAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Stop publishing. The run screen calls this after the final
  /// save + endLiveBroadcast on stop. After detach, [pushPing] is a
  /// no-op even if a stale snapshot arrives mid-tear-down.
  void detach() {
    _runId = null;
    _active = false;
  }

  /// Fire one ping. Called from the recorder's per-snapshot handler
  /// so it must be cheap on the no-op path: when inactive, when no
  /// GPS fix has landed yet, or when the throttle window hasn't
  /// elapsed since the last successful insert.
  Future<void> pushPing({
    required double lat,
    required double lng,
    double? distanceM,
    int? elapsedS,
    int? bpm,
    double? ele,
  }) async {
    final id = _runId;
    if (!_active || id == null) return;
    final now = DateTime.now();
    if (now.difference(_lastPingAt) < _pingInterval) return;
    _lastPingAt = now;
    final hub = hubClient;
    try {
      if (hub != null && hub.isConfigured) {
        await hub.pushPing(
          runId: id,
          lat: lat,
          lng: lng,
          distanceM: distanceM,
          elapsedS: elapsedS,
          bpm: bpm,
          ele: ele,
        );
      } else {
        await _api.insertLivePing(
          runId: id,
          lat: lat,
          lng: lng,
          distanceM: distanceM,
          elapsedS: elapsedS,
          bpm: bpm,
          ele: ele,
        );
      }
    } catch (e) {
      debugPrint('[LiveBroadcaster.pushPing] $e');
    }
  }
}
