import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_heart_rate.dart' show bleReconnectDelay;
import 'sim_watch_link.dart';

/// Opens the custom watch's live-status byte stream and hands it back.
///
/// The production implementation is `ReactiveBleWatchFrameSource`
/// (reactive_ble_watch_transport.dart), which subscribes to the firmware's
/// `frame` characteristic (`..e1`, read+notify); tests supply a fake. Splitting
/// the radio off behind this interface is what lets every rule in
/// [WatchStatusLink] — decode, backoff, give-up, teardown — be tested without
/// hardware, the same split [WatchBleTransport] uses for run sync.
///
/// [open] must complete with a stream that **closes when the link drops**. A
/// characteristic subscription that merely goes quiet is indistinguishable
/// from a watch sitting still, so the close is the only honest drop signal.
abstract class WatchFrameSource {
  Future<Stream<List<int>>> open();

  Future<void> close();
}

enum WatchLinkState { idle, connecting, connected, reconnecting, lost }

/// Consecutive failed opens after which the link stops trying, closes its
/// frame stream, and settles on [WatchLinkState.lost] — about 8.5 minutes at
/// [bleReconnectDelay]'s ladder. A watch that is switched off, out of range,
/// or unpaired must cost the phone a bounded amount of radio, not a retry
/// every few seconds for the rest of the day.
const int kWatchLinkMaxReconnectAttempts = 20;

/// Holds a persistent subscription to the watch's per-second status frames and
/// decodes them into the [SimWatchStatus] shape [WatchLiveForwarder] consumes.
///
/// The firmware notifies one newline-terminated `link::status_frame` per second
/// on `..e1` — byte-for-byte the payload the simulator's UART/TCP link carries
/// (`watch_core::link`'s module doc makes that identity the point), so this
/// reuses [simWatchFrames] rather than growing a second decoder. One
/// notification normally carries exactly one frame, but the line-oriented
/// decode also absorbs a frame split across notifications and a notification
/// carrying two, which is what keeps a truncated frame from poisoning the next
/// one.
///
/// **Its own connection, deliberately.** Run sync connects, pulls, and
/// disconnects per operation; status forwarding has to hold the link open for
/// a whole run. Hanging this off `ReactiveBleWatchTransport` would tear the
/// spectator feed down every time a sync finished, so the two own separate
/// connection objects — see `ReactiveBleWatchFrameSource` for the one caveat
/// that split leaves (two simultaneous connections to one watch is unverified
/// on hardware).
///
/// L4 (`docs/architecture/conventions.md § Layered resilience`). [frames]
/// never carries an error: a failed open, a dropped link, a malformed frame
/// and a byte-stream error are all logged and turned into either a retry or
/// silence. Silence is the correct spectator behaviour — [WatchLiveForwarder]
/// pushes nothing, and the spectator's own `freshnessFor` ages the last known
/// position into stale rather than being told a stale fix is current.
///
/// One link, one connection lifetime: after [stop], or after the reconnect
/// ladder is exhausted, [frames] is closed and the object is spent. Re-arming
/// is a new [WatchStatusLink] — which also buys a fresh scan, the thing you
/// actually want after the watch has been off.
class WatchStatusLink {
  WatchStatusLink(
    this._source, {
    this.maxReconnectAttempts = kWatchLinkMaxReconnectAttempts,
    Duration Function(int attempt) backoff = bleReconnectDelay,
  }) : _backoff = backoff;

  final WatchFrameSource _source;

  final int maxReconnectAttempts;

  /// Shared with the chest-strap reader's ladder (2/4/8/16 s, capped at 30 s):
  /// one BLE reconnect schedule for the app, so a fix to either is a fix to
  /// both.
  final Duration Function(int attempt) _backoff;

  final StreamController<SimWatchStatus> _frames =
      StreamController<SimWatchStatus>.broadcast();
  StreamSubscription<SimWatchStatus>? _subscription;
  Timer? _retry;
  int _attempt = 0;
  bool _stopped = false;
  WatchLinkState _state = WatchLinkState.idle;

  /// Decoded status frames. Broadcast, like the notify it stands in for, and
  /// closed exactly once — on [stop] or on giving up.
  Stream<SimWatchStatus> get frames => _frames.stream;

  WatchLinkState get state => _state;

  /// Open the link and keep it open. Returns once the first attempt has been
  /// made, not once it succeeded — a watch that is off still leaves a live
  /// object retrying in the background. Never throws.
  Future<void> start() async {
    if (_stopped || _subscription != null || _retry != null) return;
    await _open();
  }

  /// Tear the link down for good.
  Future<void> stop() async {
    _stopped = true;
    _retry?.cancel();
    _retry = null;
    final sub = _subscription;
    _subscription = null;
    // Close the source BEFORE cancelling, never the other way round.
    // [simWatchFrames] is an `async*` generator suspended on `await for`, and
    // cancelling a generator that is suspended at an await does not complete
    // until that await does — so cancelling a still-live byte stream first
    // hangs here forever. Ending the bytes lets the generator finish, and the
    // cancel then completes immediately.
    await _closeSource();
    await sub?.cancel();
    _state = WatchLinkState.idle;
    if (!_frames.isClosed) await _frames.close();
  }

  Future<void> _open() async {
    _state =
        _attempt == 0 ? WatchLinkState.connecting : WatchLinkState.reconnecting;
    final Stream<List<int>> bytes;
    try {
      bytes = await _source.open();
    } catch (e) {
      debugPrint('[WatchStatusLink] open failed: $e');
      await _closeSource();
      _scheduleRetry();
      return;
    }
    if (_stopped) {
      await _closeSource();
      return;
    }
    _state = WatchLinkState.connected;
    _subscription = simWatchFrames(bytes).listen(
      (status) {
        // Reset on a decoded frame rather than on a successful open: a link
        // that connects and drops before the watch has said anything is
        // flapping, and resetting there would retry it forever at the bottom
        // of the ladder.
        _attempt = 0;
        if (!_frames.isClosed) _frames.add(status);
      },
      onError: (Object e) {
        debugPrint('[WatchStatusLink] frame error: $e');
        _dropped();
      },
      onDone: _dropped,
    );
  }

  void _dropped() {
    final sub = _subscription;
    if (sub == null) return;
    _subscription = null;
    unawaited(sub.cancel());
    unawaited(_closeSource());
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_stopped) return;
    if (_attempt >= maxReconnectAttempts) {
      _state = WatchLinkState.lost;
      // Closing is how a watch that is really gone reaches the forwarder:
      // its `onDone` drops `linkUp`. A transient gap deliberately does not
      // reach it — that one is a gap, and freshness already tells it.
      if (!_frames.isClosed) unawaited(_frames.close());
      return;
    }
    final delay = _backoff(_attempt);
    _attempt++;
    _state = WatchLinkState.reconnecting;
    _retry?.cancel();
    _retry = Timer(delay, () {
      _retry = null;
      if (!_stopped) unawaited(_open());
    });
  }

  Future<void> _closeSource() async {
    try {
      await _source.close();
    } catch (e) {
      debugPrint('[WatchStatusLink] close failed: $e');
    }
  }
}
