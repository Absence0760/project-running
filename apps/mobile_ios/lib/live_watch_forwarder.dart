import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'live_broadcaster.dart';
import 'live_freshness.dart';
import 'sim_watch_link.dart';

/// Forwards the custom watch's per-second status frames into the same live
/// spectator pipeline a phone-recorded run uses, so a run recorded on the
/// wrist is followable on `/live/[id]`.
///
/// Until this existed the frames terminated at the dev Sim Watch screen:
/// `watch_core::link` notifies one JSON frame per second, `sim_watch_link.dart`
/// decodes it, and the screen rendered it. Nothing carried it to
/// [LiveBroadcaster], so a watch-recorded run had no spectator surface at all.
///
/// Everything reaches the wire through [LiveBroadcaster.pushPing] — never a
/// second path. That is what makes privacy-zone clipping (decisions §33)
/// inherited rather than re-implemented: the broadcaster evaluates the
/// runner's zones on every call and drops in-zone fixes before they leave the
/// device on either transport.
///
/// L4 by construction (`docs/architecture/conventions.md § Layered
/// resilience`). Nothing here can cancel or throw into the frame stream: the
/// per-frame handler is wrapped, a failed forward is reported as
/// [WatchFrameOutcome.failed] and logged, and the run recording on the watch
/// is untouched either way.
///
/// ## Gap and reconnect semantics
///
/// BLE drops. The rule is that a spectator must never be shown a stale
/// position as if it were current, so this refuses frames rather than
/// smoothing over the gap:
///
/// - **Dropout.** No frames means no pings, so the spectator's own
///   `freshnessFor` ages the last known position and flips it stale at
///   [liveStaleAfterMs]. There is no keep-alive ping and no back-fill on
///   reconnect — either would re-date an old position as fresh, which is the
///   exact failure `live_freshness` exists to prevent.
/// - **Stale fix.** The watch keeps reporting its last fix with a growing
///   `age_s` when GNSS is lost. Anything past [kWatchFixMaxAge] is refused,
///   mirroring the recorder's own `positionFresh` gate on the phone path so
///   both live paths go quiet on the same clock.
/// - **Duplicates.** `..e1` is read+notify, so a reconnect can re-deliver the
///   frame already forwarded. Same `uptime_s` as the last admitted frame is
///   dropped.
/// - **Out of order.** A frame older than the last admitted one is dropped
///   rather than rewinding the spectator's marker — unless
///   [kWatchRestartFrames] of them arrive in a row, which is the watch having
///   rebooted and restarted its uptime clock. Counting instead of thresholding
///   the backwards jump means a reboot at any uptime recovers; a fixed
///   "big jump = reboot" cut-off wedges forever when the watch reboots early.
///
/// The status frame carries position, satellites and elevation but no run
/// distance, elapsed or heart rate, so those stay null on the ping rather than
/// being guessed from `uptime_s` (device uptime is not run elapsed). The
/// spectator gets an honest position-only feed.
class WatchLiveForwarder {
  WatchLiveForwarder({
    required ApiClient api,
    required LiveBroadcaster broadcaster,
    this.fixMaxAge = kWatchFixMaxAge,
    DateTime Function() now = DateTime.now,
  })  : _api = api,
        _broadcaster = broadcaster,
        _now = now;

  final ApiClient _api;
  final LiveBroadcaster _broadcaster;
  final DateTime Function() _now;

  /// Fix age past which a frame is refused. Defaults to [kWatchFixMaxAge].
  final Duration fixMaxAge;

  static const _uuid = Uuid();

  String? _runId;
  StreamSubscription<SimWatchStatus>? _subscription;
  int? _lastUptimeS;
  int _backwardsFrames = 0;
  bool _linkUp = false;
  int? _lastAdmittedAtMs;

  /// The run being broadcast, or null before [start] / after [stop]. This is
  /// the id a share link points at.
  String? get runId => _runId;

  /// Whether a frame stream is currently connected. Goes false when the
  /// stream errors or closes.
  ///
  /// Over BLE that means the watch is gone for good, not merely out of range
  /// for a moment: [WatchStatusLink] holds the radio and reconnects behind
  /// this, closing its stream only once it gives up. A transient drop is a
  /// gap, and [linkFreshness] is what tells you about a gap.
  bool get linkUp => _linkUp;

  /// Freshness of the WATCH LINK — the age of the last frame admitted as a
  /// current position, read through the same [freshnessFor] the spectator
  /// page uses so a runner checking their phone sees the staleness their
  /// followers see. Null until the first admitted frame.
  ///
  /// It can legitimately read fresher than the spectator's: a frame admitted
  /// here is still dropped by [LiveBroadcaster] when the runner is inside a
  /// privacy zone. Withholding a position while the link is healthy is the
  /// intended behaviour, not drift.
  Freshness? linkFreshness() {
    final at = _lastAdmittedAtMs;
    if (at == null) return null;
    return freshnessFor(at, _now().millisecondsSinceEpoch);
  }

  /// Begin (or resume) forwarding [frames].
  ///
  /// The first call pre-creates the parent `runs` row and attaches the
  /// broadcaster; later calls only re-subscribe, so a reconnect after a BLE
  /// drop resumes the SAME run rather than starting a second one. Sequence
  /// state survives the reconnect on purpose — that is what lets the replayed
  /// frame be recognised as a duplicate.
  ///
  /// Returns the run id, or null when the broadcast could not be started
  /// (anonymous session, backend unreachable). Never throws.
  Future<String?> start(Stream<SimWatchStatus> frames) async {
    if (_runId == null) {
      final id = _uuid.v4();
      try {
        await _api.beginLiveBroadcast(runId: id, startedAt: _now());
      } catch (e) {
        debugPrint('[WatchLiveForwarder.start] $e');
        return null;
      }
      _runId = id;
      _broadcaster.attach(id);
    }
    await _subscription?.cancel();
    _subscription = frames.listen(
      _onFrame,
      onError: (Object e) {
        debugPrint('[WatchLiveForwarder] link error: $e');
        _linkUp = false;
      },
      onDone: () => _linkUp = false,
    );
    _linkUp = true;
    return _runId;
  }

  /// Stop forwarding and conclude the broadcast, so the spectator page shows
  /// a real conclusion instead of a feed that silently goes stale.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _linkUp = false;
    final id = _runId;
    if (id != null) {
      try {
        await _api.concludeLiveBroadcast(id);
      } catch (e) {
        debugPrint('[WatchLiveForwarder.stop] $e');
      }
    }
    _broadcaster.detach();
    _runId = null;
    _lastUptimeS = null;
    _backwardsFrames = 0;
    _lastAdmittedAtMs = null;
  }

  /// Apply the admission policy to one frame and, when it passes, hand it to
  /// the broadcaster. [WatchFrameOutcome.admitted] means the frame reached
  /// [LiveBroadcaster.pushPing], not that a ping reached the wire — the
  /// broadcaster's own throttle and privacy gates decide that.
  Future<WatchFrameOutcome> onFrame(SimWatchStatus status) async {
    if (_runId == null) return WatchFrameOutcome.notStarted;

    final last = _lastUptimeS;
    if (last != null) {
      if (status.uptimeS == last) return WatchFrameOutcome.duplicate;
      if (status.uptimeS < last) {
        _backwardsFrames++;
        if (_backwardsFrames < kWatchRestartFrames) {
          return WatchFrameOutcome.outOfOrder;
        }
      }
    }
    _backwardsFrames = 0;
    _lastUptimeS = status.uptimeS;

    final fix = status.fix;
    if (fix == null) return WatchFrameOutcome.noFix;
    if (fix.ageS > fixMaxAge.inSeconds) return WatchFrameOutcome.staleFix;

    _lastAdmittedAtMs = _now().millisecondsSinceEpoch;
    await _broadcaster.pushPing(
      lat: fix.lat,
      lng: fix.lon,
      ele: status.elev?.altM ?? fix.altM,
    );
    return WatchFrameOutcome.admitted;
  }

  void _onFrame(SimWatchStatus status) {
    unawaited(onFrame(status).catchError((Object e) {
      debugPrint('[WatchLiveForwarder.onFrame] $e');
      return WatchFrameOutcome.failed;
    }));
  }
}

/// Why a frame did or did not reach the broadcaster.
enum WatchFrameOutcome {
  notStarted,
  duplicate,
  outOfOrder,
  noFix,
  staleFix,
  admitted,
  failed,
}

/// Fix age past which a status frame is refused rather than forwarded. The
/// watch re-reports its last fix with a growing `age_s` through a GNSS
/// blackout; mirrors the run recorder's 10 s GPS-lost threshold so the
/// watch-fed and phone-fed live paths fall silent on the same clock.
const Duration kWatchFixMaxAge = Duration(seconds: 10);

/// Consecutive backwards frames that re-baseline the sequence as a watch
/// reboot rather than out-of-order delivery.
const int kWatchRestartFrames = 3;
