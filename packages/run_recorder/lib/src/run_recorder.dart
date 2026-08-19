import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import 'run_snapshot.dart';

/// Thrown by [RunRecorder.prepare] when device location services are turned
/// off (system-level, distinct from app permission). The user must enable
/// them in Settings before a run can start.
class LocationServiceDisabledError extends Error {
  @override
  String toString() => 'Location services are disabled on this device';
}

/// Thrown by [RunRecorder.prepare] when the user denied the location
/// permission prompt (or has previously set it to deniedForever).
class LocationPermissionDeniedError extends Error {
  final bool forever;
  LocationPermissionDeniedError({this.forever = false});
  @override
  String toString() => forever
      ? 'Location permission is permanently denied'
      : 'Location permission was denied';
}

/// A single lap split marked mid-run. Captures the cumulative distance and
/// duration at the moment the user tapped the lap button. Cumulative values
/// are convenient for the recorder loop (no previous-lap bookkeeping); the
/// canonical wire shape (per-lap deltas) is computed at serialisation time
/// by [lapsToCanonicalJson].
class LapSplit {
  final int number;
  final DateTime timestamp;
  final double cumulativeDistanceMetres;
  final Duration cumulativeDuration;

  const LapSplit({
    required this.number,
    required this.timestamp,
    required this.cumulativeDistanceMetres,
    required this.cumulativeDuration,
  });
}

/// Serialise a list of in-memory [LapSplit]s into the canonical JSON shape
/// documented in `docs/backend/metadata.md` § laps:
/// `[{ index: int, start_offset_s: int, distance_m: double, duration_s: int }]`.
///
/// `start_offset_s` is the cumulative duration **up to the start of this
/// lap** (i.e. the previous lap's cumulative duration, 0 for the first
/// lap). `distance_m` and `duration_s` are this lap's deltas, not the
/// cumulative totals — pure per-lap values, matching the Wear OS sender
/// at `apps/watch_wear/.../RunViewModel.kt`. Negative deltas (which can
/// only result from a clock skew between laps) are clamped to 0.
List<Map<String, dynamic>> lapsToCanonicalJson(List<LapSplit> laps) {
  final out = <Map<String, dynamic>>[];
  var prevDist = 0.0;
  var prevDuration = Duration.zero;
  for (final lap in laps) {
    final distM =
        (lap.cumulativeDistanceMetres - prevDist).clamp(0.0, double.infinity);
    final durDelta = lap.cumulativeDuration - prevDuration;
    final durS =
        durDelta.inSeconds < 0 ? 0 : durDelta.inSeconds;
    out.add(<String, dynamic>{
      'index': lap.number,
      'start_offset_s': prevDuration.inSeconds,
      'distance_m': distM,
      'duration_s': durS,
    });
    prevDist = lap.cumulativeDistanceMetres;
    prevDuration = lap.cumulativeDuration;
  }
  return out;
}

/// Inverse of [lapsToCanonicalJson]: reconstruct in-memory cumulative
/// [LapSplit]s from the canonical per-lap-delta JSON persisted in
/// `metadata.laps`. Used by the resume path so a process-killed run keeps its
/// mid-run lap / aid-station marks — numbering and cumulative totals continue
/// unbroken when the recorder is re-hydrated. Timestamps aren't part of the
/// canonical shape (only `start_offset_s` / `distance_m` / `duration_s`), so
/// each split's timestamp is reconstructed as [startedAt] + its cumulative
/// duration; it isn't re-serialised ([lapsToCanonicalJson] ignores timestamp).
List<LapSplit> lapsFromCanonicalJson(List<dynamic> json, {DateTime? startedAt}) {
  final anchor = startedAt ?? DateTime.now();
  final out = <LapSplit>[];
  var cumDist = 0.0;
  var cumDur = Duration.zero;
  for (final entry in json) {
    if (entry is! Map) continue;
    final distM = (entry['distance_m'] as num?)?.toDouble() ?? 0.0;
    final durS = (entry['duration_s'] as num?)?.toInt() ?? 0;
    final index = (entry['index'] as num?)?.toInt() ?? (out.length + 1);
    cumDist += distM;
    cumDur += Duration(seconds: durS);
    out.add(LapSplit(
      number: index,
      timestamp: anchor.add(cumDur),
      cumulativeDistanceMetres: cumDist,
      cumulativeDuration: cumDur,
    ));
  }
  return out;
}

/// Manages a live GPS recording session: opens the position stream, filters
/// noise, accumulates distance, and emits [RunSnapshot]s to the UI. Survives
/// a missing/revoked GPS signal — [prepare] flips [prepared] even when the
/// stream can't open, and a retry loop reopens the stream when services
/// come back.
class RunRecorder {
  /// [clock] exists so tests can drive the monotonic gap the re-anchor escape
  /// in [_onPosition] gates on without waiting out real seconds. Production
  /// always takes the default.
  RunRecorder({Stopwatch? clock}) : _stopwatch = clock ?? Stopwatch();

  static const _uuid = Uuid();

  /// How often [prepare] retries opening the position stream when it is
  /// currently absent (services/permission denied at start, or the stream
  /// errored mid-run). Short enough that re-enabling Location in Settings
  /// feels immediate; long enough to avoid thrash.
  static const _gpsRetryInterval = Duration(seconds: 3);

  final _controller = StreamController<RunSnapshot>.broadcast();
  // Set by [dispose] and never cleared. The GPS retry callback awaits its
  // service/permission precheck, so one already in flight when the recorder is
  // disposed resumes afterwards and would re-open the position stream — a
  // subscription nothing is left to cancel, holding the GPS radio and the
  // foreground service for the life of the process while every fix raises on
  // the closed snapshot sink.
  bool _disposed = false;
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  Timer? _gpsRetryTimer;
  final List<LapSplit> _laps = [];

  /// All lap splits recorded so far.
  List<LapSplit> get laps => List.unmodifiable(_laps);

  DateTime? _startTime;
  /// Elapsed time already accumulated by a PRIOR session that this recorder
  /// resumed (see [resumeSession]). Added to the live [_stopwatch] everywhere elapsed
  /// is reported so a process-killed-then-resumed run reports continuous total
  /// elapsed instead of restarting from zero. Zero for a normal fresh run. Only
  /// the time the recorder was actually running is counted — the (unknown-
  /// length) dead-process gap is deliberately not added, keeping the monotonic-
  /// clock honesty the [_stopwatch] design buys.
  Duration _elapsedOffset = Duration.zero;
  /// Monotonic clock for elapsed time. Unlike `DateTime.now()`, [Stopwatch]
  /// is unaffected by wall-clock jumps (NTP sync, manual time change,
  /// timezone change) — the run duration stays correct.
  final Stopwatch _stopwatch;
  double _distanceMetres = 0;
  final List<Waypoint> _track = [];
  // Single read-only view handed out on every snapshot. `UnmodifiableListView`
  // wraps `_track` by reference — appending to `_track` is still visible
  // through the view, and there's no new wrapper allocated per emission
  // (which used to fire 1×/second minimum + once per GPS fix).
  late final UnmodifiableListView<Waypoint> _trackView =
      UnmodifiableListView(_track);
  // Lowest `_track` index [_calculatePace] may walk back to. Bumped to the
  // current track length on every resume so the rolling-pace window never
  // straddles a pause (or a dead-process gap), whose wall-clock duration would
  // otherwise be charged to the post-resume distance.
  int _paceFloorIdx = 0;
  /// Latest raw GPS fix — drives the blue dot on the live map and updates
  /// on every fix, independent of the track-append threshold.
  Waypoint? _currentWaypoint;
  /// Wall-clock time [_currentWaypoint] was accepted from the sensor. The
  /// 1-second timer re-emits the same fix forever, so this — not the
  /// snapshot's arrival — is the only honest measure of GPS liveness.
  DateTime? _currentWaypointAt;
  /// Last position that was appended to [_track]. Used to gate the next
  /// track append + distance accumulation on real movement.
  Position? _lastTrackedPosition;

  /// Cache for route-relative calculations in [_emitSnapshot]. When the
  /// 1-second elapsed-time timer fires without a new GPS fix, the
  /// `_currentWaypoint` reference is identical to the last one the route
  /// math ran against — reuse the previous off-route / remaining values
  /// instead of re-walking every segment of the loaded route.
  Waypoint? _lastRouteCalcFor;
  double? _cachedOffRoute;
  double? _cachedRouteRemaining;
  // Lowest route-segment index the closest-segment search is allowed to
  // match. Progress along the route is monotonic: on a loop, out-and-back, or
  // figure-eight the perpendicular-closest segment can be one already passed
  // (the route doubles back near the runner). Without this floor the matched
  // segment jumps backwards and "distance remaining" climbs UP. Clamping the
  // search to start at the last matched index keeps remaining non-increasing.
  int _minMatchedSegmentIdx = 1;
  // Whether [_currentWaypoint] is a fix the L1 distance chain accepted into
  // the track. A fix rejected as an implausible teleport still refreshes the
  // blue dot, but must never drive route progress: the closest-segment search
  // ADVANCES the monotonic [_minMatchedSegmentIdx] floor, and the floor is by
  // design never lowered — so one corrupt fix would pin the search kilometres
  // ahead for the rest of the run, permanently inflating off-route distance
  // (up to a false safety escalation) and understating distance remaining.
  bool _currentWaypointTrusted = true;
  DateTime? _lastTrackedPositionAt;
  /// [_stopwatch] reading when [_lastTrackedPosition] was last set. Always
  /// written and cleared together with it — the tracking block treats a
  /// half-set anchor as no anchor at all, so a divergence re-anchors rather
  /// than freezing.
  Duration? _lastTrackedElapsed;
  bool _recording = false;
  bool _paused = false;
  Route? _route;
  // Suffix sums of route segment lengths, precomputed once when the route is
  // set: `_routeTailAfter[k]` is the total length of all route segments
  // strictly after segment k (segment j connects waypoint j-1 → j). The
  // distance-remaining calc on every GPS fix then adds the tail in O(1)
  // instead of re-summing the whole remaining route — that inline sum was
  // O(R) per fix, i.e. O(R²) over a multi-hour run on a 2000-waypoint route.
  List<double>? _routeTailAfter;
  double _trackThresholdMetres = 3;
  double _maxSpeedMps = 10;
  double _accuracyGateMetres = 20;
  // A hop that fails the <100 m one-hop cap but spans at least this many
  // seconds is treated as a real GPS gap (fixes dropped under cover / in a
  // tunnel / while backgrounded, or a batch), not a corrupt teleport: the
  // anchor is rebased to the new fix without crediting the un-sampled gap
  // distance. ~10 s matches the "GPS lost" mental model and is long enough
  // that a 1 Hz corrupt outlier (dt≈1 s) still fails closed. See #330.
  static const double _gpsReanchorAfterSeconds = 10;
  // Point-onto-segment projections [_reseedRouteFloor] may spend replaying a
  // resumed track. A few milliseconds' worth — the resume path runs on the UI
  // isolate, ahead of the first post-resume fix.
  static const int _resumeFloorProjectionBudget = 200000;
  // Rate-limits the "fix dropped for accuracy" log. An always-bad stream
  // would otherwise spam at ~1 Hz for the entire run.
  DateTime? _lastAccuracyDropLogAt;
  // True while the latest fix was rejected by the accuracy gate, so distance
  // has stalled. Surfaced on every snapshot as [RunSnapshot.weakGps] so the
  // run screen can show a "distance paused" banner instead of looking frozen.
  // Set on a dropped fix, cleared the moment a fix passes the gate.
  bool _weakGps = false;
  // Remembered so the retry loop can re-open the position stream with the
  // same accuracy setting the caller passed to [prepare].
  LocationAccuracy _locationAccuracy = LocationAccuracy.high;

  /// Latest heart-rate sample, in BPM. Stamped onto each new [Waypoint]
  /// when constructed so the saved track carries per-point BPM and the
  /// run-detail HR-zone breakdown lights up for phone-recorded runs.
  ///
  /// Push via [setHeartRate] from whatever HR source the caller wires up
  /// (`BleHeartRate` for the chest strap on mobile, or any other plugin
  /// that yields BPM samples). Leave at `null` while no strap is paired
  /// — Waypoints constructed without a sample carry `bpm: null`, which
  /// matches the pre-strap behaviour.
  int? _currentBpm;

  /// Treadmill (FTMS) distance source — an ADDITIVE, OPT-IN alternate to the
  /// GPS L1 distance path. Off by default: every field here stays untouched
  /// during a normal GPS run, and nothing in this block can run unless the
  /// caller explicitly pushes a sample via [setTreadmillSample]. When active,
  /// [_emitSnapshot] + [stop] report [_treadmillDistanceMetres] in place of
  /// the GPS-accumulated [_distanceMetres]; the GPS `_onPosition` path is
  /// never altered (any incidental fix still builds the track, it just stops
  /// driving the headline distance). This is the same shape as [setHeartRate]
  /// — an external sample fed in from a platform plugin the package doesn't
  /// depend on.
  bool _treadmillMode = false;
  double _treadmillDistanceMetres = 0;
  double? _treadmillBaselineMetres;
  // Last cumulative belt total seen. A total BELOW this one is the console
  // having restarted its own session and zeroed the counter; the baseline
  // alone can't detect that (it is usually 0, so nothing is ever below it).
  double? _treadmillLastTotalMetres;
  double _treadmillLastSpeedMps = 0;
  DateTime? _treadmillLastSampleAt;
  // Armed by [pause] so a cumulative-distance belt advance during the pause is
  // frozen out: a sample landing DURING the pause disarms it (the _paused
  // branch rebases the baseline), otherwise the first post-resume sample
  // re-anchors. See [pause] / [resume] / [setTreadmillSample].
  bool _treadmillNeedsRebaseline = false;

  /// Plausibility ceiling for a treadmill belt speed (m/s) ≈ 43 km/h —
  /// faster than any human belt speed, so a reading at/above it is a sensor
  /// glitch. Used BOTH to gate distance accumulation AND to gate carrying
  /// the speed forward as the next interval's integrand; the two MUST agree
  /// or a rejected reading still poisons the next interval (phantom distance).
  static const double _maxTreadmillSpeedMps = 12;

  /// Whether the recorder is currently sourcing distance from a treadmill
  /// rather than GPS.
  bool get treadmillMode => _treadmillMode;

  /// Emits a [RunSnapshot] on every GPS fix once [prepare] has run, and once
  /// per second after [begin] starts recording time.
  Stream<RunSnapshot> get snapshots => _controller.stream;

  /// Whether [prepare] has completed. True even when GPS is unavailable —
  /// the recorder accepts [begin] and emits time-only snapshots until a
  /// fix arrives (or the retry loop re-opens the stream).
  bool get prepared => _prepared;
  bool _prepared = false;

  /// Whether this run records under a permission that only covers the
  /// foreground. True on Android when the grant is "While using the app":
  /// fixes flow normally while the run screen is up, but Android can stop
  /// delivering them once another app takes focus, so distance freezes the
  /// instant the runner opens the camera or locks the screen. Uninterrupted
  /// background recording needs "Allow all the time"
  /// (`ACCESS_BACKGROUND_LOCATION`).
  ///
  /// A limitation, not a failure — the recorder still opens the stream and
  /// records. Callers disclose it; they must NOT treat it as a reason to
  /// skip GPS, which is what left a "while in use" runner staring at an
  /// empty map for the whole run. Always false on iOS, where "While Using
  /// the App" plus the `UIBackgroundModes:location` capability keeps
  /// CoreLocation feeding fixes for the whole session. Resolved by
  /// [prepare]; a mid-run upgrade to "Allow all the time" is picked up by
  /// the next [prepare], not here.
  bool get backgroundLocationLimited => _backgroundLocationLimited;
  bool _backgroundLocationLimited = false;

  /// Whether [begin] has been called and time/distance are accumulating.
  bool get recording => _recording;

  /// Prepare the recorder for a run. Resets state, flips [prepared] to true,
  /// starts the self-healing GPS retry loop, and — if services + permission
  /// are available — opens the position stream so fixes can drive the live
  /// map during the countdown before [begin] is called.
  ///
  /// Call [begin] when the countdown ends to flip on recording. Because
  /// [prepared] flips before the GPS checks, [begin] is usable even for
  /// indoor / treadmill runs where GPS is unavailable at the start.
  ///
  /// [distanceFilterMetres] and [minMovementMetres] are combined into a single
  /// software threshold that gates when a GPS fix gets appended to the track
  /// and counted toward distance. The OS-level filter is always 0 so the blue
  /// dot can update at the GPS sensor's native rate, independent of this
  /// threshold.
  ///
  /// Throws [LocationServiceDisabledError] if device location services are
  /// off. Throws [LocationPermissionDeniedError] if the user denies (or has
  /// permanently denied — see [LocationPermissionDeniedError.forever]) the
  /// permission prompt. Both errors leave [prepared] == true; the recorder is
  /// still usable as a time-only session and the retry loop will re-open the
  /// stream automatically when services / permission come back.
  ///
  /// A foreground-only ("While using the app") grant on Android is NOT an
  /// error — it records fine while the app is on screen, and only background
  /// delivery is at risk. It sets [backgroundLocationLimited] so the caller
  /// can disclose the limitation.
  Future<void> prepare({
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
    double maxSpeedMps = 10,
    LocationAccuracy accuracy = LocationAccuracy.high,
    double accuracyGateMetres = 20,
  }) async {
    if (_disposed) {
      throw StateError('RunRecorder.prepare() called after dispose()');
    }
    // Reset state first and flip _prepared = true unconditionally. If GPS
    // setup below throws, the recorder is still usable for a time-only
    // (indoor / treadmill) run — begin() will start the stopwatch, the
    // 1-second timer emits snapshots with a null currentPosition, and the
    // live map falls back to its "Waiting for GPS..." placeholder. If GPS
    // later becomes available the caller can call prepare() again.
    _startTime = null;
    _elapsedOffset = Duration.zero;
    _stopwatch
      ..stop()
      ..reset();
    _distanceMetres = 0;
    _track.clear();
    _laps.clear();
    _currentWaypoint = null;
    _currentWaypointAt = null;
    _lastTrackedPosition = null;
    _lastTrackedPositionAt = null;
    _lastTrackedElapsed = null;
    _lastRouteCalcFor = null;
    _cachedOffRoute = null;
    _cachedRouteRemaining = null;
    _minMatchedSegmentIdx = 1;
    _currentWaypointTrusted = true;
    _paceFloorIdx = 0;
    _recording = false;
    _paused = false;
    _route = route;
    _routeTailAfter = _computeRouteTailAfter(route);
    _trackThresholdMetres =
        max(distanceFilterMetres.toDouble(), minMovementMetres);
    _maxSpeedMps = maxSpeedMps;
    _accuracyGateMetres = accuracyGateMetres;
    _locationAccuracy = accuracy;
    _lastAccuracyDropLogAt = null;
    _backgroundLocationLimited = false;
    _resetTreadmill();
    _prepared = true;

    // Start the self-healing retry loop regardless of whether GPS is
    // available right now. If the user has Location off at the start of
    // the run and flips it on later, or if Android tears the stream down
    // mid-run, the loop re-subscribes within a few seconds.
    _startGpsRetryLoop();

    // Device-level location services must be on before we even try to get a
    // permission or open a position stream — otherwise getPositionStream
    // silently produces nothing and the run never receives a fix.
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationServiceDisabledError();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!_permissionAllowsStream(permission)) {
      throw LocationPermissionDeniedError(
        forever: permission == LocationPermission.deniedForever,
      );
    }
    _backgroundLocationLimited = _foregroundOnlyGrant(permission);

    _openPositionStream();
  }

  /// Whether [permission] covers the foreground but not reliably the
  /// background — Android's "While using the app". Drives
  /// [backgroundLocationLimited]. False on iOS: "While Using the App" plus
  /// the `UIBackgroundModes:location` capability is a supported
  /// background-recording configuration there.
  static bool _foregroundOnlyGrant(LocationPermission permission) =>
      defaultTargetPlatform == TargetPlatform.android &&
      permission == LocationPermission.whileInUse;

  /// Whether [permission] allows opening the live GPS position stream at
  /// all. Shared by [prepare]'s gate and [_startGpsRetryLoop]'s periodic
  /// precheck so the two conditions cannot drift apart (#671).
  ///
  /// False only for [LocationPermission.denied] /
  /// [LocationPermission.deniedForever]. A foreground-only grant DOES open
  /// the stream: refusing it recorded nothing at all — no fixes, an empty
  /// "Waiting for GPS" map, a run saved as indoor — to avoid a background
  /// freeze the runner might never have hit, and Android's first-run dialog
  /// cannot grant more than that anyway. It is disclosed through
  /// [backgroundLocationLimited] instead.
  static bool _permissionAllowsStream(LocationPermission permission) =>
      permission != LocationPermission.denied &&
      permission != LocationPermission.deniedForever;

  /// Subscribe to [Geolocator.getPositionStream] with the accuracy settings
  /// remembered from the last [prepare] call. Any stream error (commonly
  /// thrown when the user toggles Location off mid-run) cancels the
  /// subscription and clears [_positionSub] — the retry loop picks it back
  /// up once services are available again.
  void _openPositionStream() {
    if (_disposed) return;
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _platformLocationSettings(),
    ).listen(
      _onPosition,
      onError: (Object e, StackTrace st) {
        debugPrint('RunRecorder: position stream error — $e');
        _positionSub?.cancel();
        _positionSub = null;
      },
      cancelOnError: true,
    );
  }

  /// Build the per-platform [LocationSettings] for the live position stream.
  ///
  /// iOS gets [AppleSettings] with [ActivityType.fitness] +
  /// `pauseLocationUpdatesAutomatically: false`. CLLocationManager's default
  /// for that flag is `true`, which auto-pauses the GPS the moment iOS
  /// decides the user has stopped moving — including the 30-second pause
  /// taken to photograph something interesting mid-run. That produces the
  /// same silent freeze the Android `whileInUse` path produced (see
  /// [LocationPermissionWhileInUseError]) — fixes stop, distance flat-lines,
  /// the foreground capability stays alive so no error surfaces, and the
  /// user only notices once they look at the finished run. Pinning the flag
  /// here keeps the iOS twin honest. `activityType: fitness` biases the
  /// CoreLocation power-saving heuristics for foot-paced motion.
  ///
  /// Android gets [AndroidSettings] with [ForegroundNotificationConfig] so
  /// the geolocator package can promote its service to a typed foreground
  /// service. `distanceFilter: 0` keeps every fix flowing so software
  /// filtering can drive the blue dot at sensor rate.
  LocationSettings _platformLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: _locationAccuracy,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: false,
        allowBackgroundLocationUpdates: true,
      );
    }
    return AndroidSettings(
      accuracy: _locationAccuracy,
      // Receive every fix from the OS; movement filtering happens in
      // software so the blue dot can refresh without inflating the track.
      distanceFilter: 0,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Run in progress',
        notificationText: 'Recording your run',
        enableWakeLock: true,
        notificationIcon:
            AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      ),
    );
  }

  /// Periodically check whether GPS is available and (re-)open the
  /// position stream if it's currently down. Idempotent — a healthy
  /// stream is a no-op. Gates on [_permissionAllowsStream] — the SAME
  /// predicate [prepare] gates on — so a permission state [prepare] refuses
  /// to open a stream for can never be silently opened by this loop a few
  /// seconds later (#671). A permission granted mid-run (the runner denies
  /// the dialog, then relents from Settings) reopens the stream on the next
  /// tick, since [Geolocator.checkPermission] reflects the new grant.
  void _startGpsRetryLoop() {
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer = Timer.periodic(_gpsRetryInterval, (_) async {
      if (!_prepared) return;
      if (_positionSub != null) return;
      try {
        if (!await Geolocator.isLocationServiceEnabled()) return;
        final p = await Geolocator.checkPermission();
        if (!_permissionAllowsStream(p)) return;
      } catch (e) {
        debugPrint('RunRecorder: GPS retry precheck failed — $e');
        return;
      }
      if (!_prepared || _positionSub != null) return;
      _openPositionStream();
    });
  }

  /// Flip the recorder into recording mode. Must be called after [prepare]
  /// has completed. Starts the elapsed-time clock, clears any track built
  /// before this point, and begins accumulating distance.
  void begin() {
    if (!_prepared) {
      throw StateError('RunRecorder.begin() called before prepare() completed');
    }
    _startTime = DateTime.now();
    _stopwatch
      ..reset()
      ..start();
    _distanceMetres = 0;
    _track.clear();
    _laps.clear();
    _lastTrackedPosition = null;
    _lastTrackedPositionAt = null;
    _lastTrackedElapsed = null;
    _paceFloorIdx = 0;
    _weakGps = false;
    _resetTreadmillAccumulators();
    _recording = true;
    _paused = false;

    // 1-second timer for elapsed time updates. Fires regardless of whether
    // we've received a GPS fix yet — during warmup or an indoor run the
    // stopwatch still ticks; snapshots just carry a null currentPosition
    // and the UI falls back to its "Waiting for GPS..." placeholder.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_recording) return;
      _emitSnapshot();
    });
  }

  /// Convenience: [prepare] + [begin] in one call. Kept for callers that
  /// don't need the preload/countdown split.
  Future<void> start({
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
    double maxSpeedMps = 10,
    LocationAccuracy accuracy = LocationAccuracy.high,
    double accuracyGateMetres = 20,
  }) async {
    await prepare(
      route: route,
      distanceFilterMetres: distanceFilterMetres,
      minMovementMetres: minMovementMetres,
      maxSpeedMps: maxSpeedMps,
      accuracy: accuracy,
      accuracyGateMetres: accuracyGateMetres,
    );
    begin();
  }

  /// Resume a persisted partial recording, continuing the SAME run rather than
  /// starting a new one. Re-hydrates the accumulated [track], [distanceMetres],
  /// prior [elapsed], original [startedAt], and mid-run [laps], opens the GPS
  /// stream (via [prepare]), then flips straight into recording mode — new
  /// fixes extend the existing track and add on to the existing distance /
  /// elapsed / lap sequence.
  ///
  /// This is the process-kill resume path: a multi-day effort whose OS process
  /// was reaped. Without it the only outcomes were finalizing the partial into
  /// a separate finished Run or discarding it — either way splitting one
  /// continuous effort into two disjoint records.
  ///
  /// Unlike [begin], this does NOT clear the seeded track / distance / laps.
  /// The last-tracked position is re-anchored to null so the first post-resume
  /// fix doesn't add a spurious distance delta across the unknown-length gap
  /// while the process was dead.
  ///
  /// GPS-setup errors from [prepare] are rethrown AFTER the state is seeded and
  /// recording has begun, so the caller can surface the "GPS unavailable"
  /// notice while the recorder still resumes as a time-only session (the retry
  /// loop reopens the stream when services return) — mirroring [begin]'s
  /// tolerance of a GPS-less start.
  ///
  /// Named `resumeSession` (not `resume`) to avoid colliding with [resume],
  /// which un-pauses an already-running recorder.
  Future<void> resumeSession({
    required List<Waypoint> track,
    required double distanceMetres,
    required Duration elapsed,
    required DateTime startedAt,
    List<LapSplit> laps = const [],
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
    double maxSpeedMps = 10,
    LocationAccuracy accuracy = LocationAccuracy.high,
    double accuracyGateMetres = 20,
  }) async {
    Object? prepareError;
    try {
      await prepare(
        route: route,
        distanceFilterMetres: distanceFilterMetres,
        minMovementMetres: minMovementMetres,
        maxSpeedMps: maxSpeedMps,
        accuracy: accuracy,
        accuracyGateMetres: accuracyGateMetres,
      );
    } catch (e) {
      // prepare() reset state, flipped _prepared true, and started the retry
      // loop before throwing; seed + begin anyway, then rethrow so the caller
      // can disclose the GPS problem without losing the resumed session.
      prepareError = e;
    }
    _seedResumeState(
      track: track,
      distanceMetres: distanceMetres,
      elapsed: elapsed,
      startedAt: startedAt,
      laps: laps,
    );
    _beginResumed();
    if (prepareError != null) throw prepareError;
  }

  void _seedResumeState({
    required List<Waypoint> track,
    required double distanceMetres,
    required Duration elapsed,
    required DateTime startedAt,
    required List<LapSplit> laps,
  }) {
    _track
      ..clear()
      ..addAll(track);
    _distanceMetres = distanceMetres;
    _elapsedOffset = elapsed;
    _startTime = startedAt;
    _laps
      ..clear()
      ..addAll(laps);
    _reseedRouteFloor();
  }

  /// Rebuild the monotonic route floor from the seeded track.
  ///
  /// [prepare] resets [_minMatchedSegmentIdx] to 1, which hands a resumed run a
  /// route matcher with no memory of the ground already covered: on a loop or
  /// an out-and-back the closest segment to the runner is then one they passed
  /// hours ago, so distance-remaining jumps back up and — the floor being by
  /// design never lowered — never self-corrects. The seeded track holds exactly
  /// the fixes the live run advanced the floor on, so replaying it through the
  /// same closest-segment search restores the floor the killed process had.
  void _reseedRouteFloor() {
    final route = _route;
    if (route == null || route.waypoints.length < 2 || _track.isEmpty) return;
    // Every probe scans the route tail, so replaying a multi-day track against
    // a dense route in one burst is the whole run's route maths at once. Probe
    // an evenly spaced subset within a fixed budget: the floor advances by the
    // ORDER points are matched in, not by how densely they are sampled.
    final probes =
        max(1, _resumeFloorProjectionBudget ~/ (route.waypoints.length - 1));
    final step = max(1, (_track.length / probes).ceil());
    for (var i = 0; i < _track.length; i += step) {
      _routeProgress(_track[i]);
    }
    _routeProgress(_track.last);
  }

  /// [begin]-equivalent for [resumeSession]: starts the clock + 1 s snapshot
  /// timer WITHOUT clearing the seeded track / distance / laps. Re-anchors the
  /// last-tracked position so the first post-resume fix doesn't credit the
  /// dead-process gap as distance.
  void _beginResumed() {
    if (!_prepared) {
      throw StateError('RunRecorder.resumeSession() seeding ran before prepare()');
    }
    _stopwatch
      ..reset()
      ..start();
    _lastTrackedPosition = null;
    _lastTrackedPositionAt = null;
    _lastTrackedElapsed = null;
    _paceFloorIdx = _track.length;
    _weakGps = false;
    _resetTreadmillAccumulators();
    _recording = true;
    _paused = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_recording) return;
      _emitSnapshot();
    });
  }

  /// Test-only: [resumeSession] without the geolocator stream. Seeds the resumed
  /// state on top of [debugPrepareWithoutStream] then begins, so continuity
  /// (elapsed offset, distance, track, laps) can be exercised by feeding
  /// [debugInjectPosition] fixes.
  @visibleForTesting
  void debugResumeWithoutStream({
    required List<Waypoint> track,
    required double distanceMetres,
    required Duration elapsed,
    required DateTime startedAt,
    List<LapSplit> laps = const [],
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
    double maxSpeedMps = 10,
    double accuracyGateMetres = 20,
  }) {
    debugPrepareWithoutStream(
      route: route,
      distanceFilterMetres: distanceFilterMetres,
      minMovementMetres: minMovementMetres,
      maxSpeedMps: maxSpeedMps,
      accuracyGateMetres: accuracyGateMetres,
    );
    _seedResumeState(
      track: track,
      distanceMetres: distanceMetres,
      elapsed: elapsed,
      startedAt: startedAt,
      laps: laps,
    );
    _beginResumed();
  }

  /// Test-only: skip the real geolocator subscription and flip the recorder
  /// into a prepared state with the supplied filter parameters. Tests can
  /// then call [debugInjectPosition] directly to feed simulated GPS fixes
  /// through the same `_onPosition` pipeline the live stream uses.
  @visibleForTesting
  void debugPrepareWithoutStream({
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
    double maxSpeedMps = 10,
    double accuracyGateMetres = 20,
  }) {
    _startTime = null;
    _elapsedOffset = Duration.zero;
    _stopwatch
      ..stop()
      ..reset();
    _distanceMetres = 0;
    _track.clear();
    _laps.clear();
    _currentWaypoint = null;
    _currentWaypointAt = null;
    _lastTrackedPosition = null;
    _lastTrackedPositionAt = null;
    _lastTrackedElapsed = null;
    _lastRouteCalcFor = null;
    _cachedOffRoute = null;
    _cachedRouteRemaining = null;
    _minMatchedSegmentIdx = 1;
    _currentWaypointTrusted = true;
    _paceFloorIdx = 0;
    _recording = false;
    _paused = false;
    _route = route;
    _routeTailAfter = _computeRouteTailAfter(route);
    _trackThresholdMetres =
        max(distanceFilterMetres.toDouble(), minMovementMetres);
    _maxSpeedMps = maxSpeedMps;
    _accuracyGateMetres = accuracyGateMetres;
    _resetTreadmill();
    _prepared = true;
  }

  /// Test-only: push a simulated [Position] through the same filter chain
  /// the live geolocator subscription would use.
  @visibleForTesting
  void debugInjectPosition(Position pos) => _onPosition(pos);

  /// Test-only: read-only view of the track built so far.
  @visibleForTesting
  List<Waypoint> get debugTrack => List.unmodifiable(_track);

  /// Test-only: current GPS-accumulated distance (ignores treadmill mode).
  @visibleForTesting
  double get debugDistanceMetres => _distanceMetres;

  /// Test-only: the headline distance the recorder would report on a snapshot
  /// — belt distance in treadmill mode, GPS distance otherwise.
  @visibleForTesting
  double get debugReportedDistanceMetres => _reportedDistanceMetres;

  /// Test-only: whether treadmill mode is currently active.
  @visibleForTesting
  bool get debugTreadmillMode => _treadmillMode;

  /// Test-only: elapsed time as seen by the monotonic stopwatch.
  @visibleForTesting
  Duration get debugElapsed => _stopwatch.elapsed;

  /// Test-only: latest raw waypoint (drives the blue dot).
  @visibleForTesting
  Waypoint? get debugCurrentWaypoint => _currentWaypoint;

  /// Test-only: whether the latest fix was rejected by the accuracy gate
  /// (drives [RunSnapshot.weakGps] / the "distance paused" banner).
  @visibleForTesting
  bool get debugWeakGps => _weakGps;

  /// Test-only: rolling-pace computed from the trailing ~200 m of track.
  /// Returns null when the track is too short or timestamps are missing —
  /// matches the contract documented on [RunSnapshot.currentPaceSecondsPerKm].
  @visibleForTesting
  double? get debugPaceSecondsPerKm => _calculatePace();

  /// Test-only: distance from [pos] to the end of the loaded route, summed
  /// along the remaining route segments. Null when no route is loaded.
  @visibleForTesting
  double? debugRouteRemaining(Waypoint pos) => _routeRemaining(pos);

  /// Test-only: minimum distance from [pos] to any segment of the loaded
  /// route. Null when no route is loaded.
  @visibleForTesting
  double? debugOffRouteDistance(Waypoint pos) => _offRouteDistance(pos);

  /// Test-only: the single-pass off-route + remaining the snapshot path uses.
  /// Must equal `(debugOffRouteDistance, debugRouteRemaining)`.
  @visibleForTesting
  ({double offRoute, double remaining})? debugRouteProgress(Waypoint pos) =>
      _routeProgress(pos);

  /// Pause the timer and stop accumulating distance until [resume] is called.
  void pause() {
    if (!_recording || _paused) return;
    _paused = true;
    _stopwatch.stop();
    // Arm the cumulative-distance re-anchor. If a belt sample lands DURING the
    // pause it rebases the baseline itself and disarms this; if none does, the
    // first post-resume sample re-anchors instead. Without one or the other,
    // the belt advance during the pause leaks into the distance on resume.
    _treadmillNeedsRebaseline = true;
  }

  /// Resume after a [pause].
  void resume() {
    if (!_recording || !_paused) return;
    _paused = false;
    _stopwatch.start();
    _lastTrackedPosition = null; // avoid a big jump after resume
    _lastTrackedPositionAt = null;
    _lastTrackedElapsed = null;
    _paceFloorIdx = _track.length;
    // Drop the speed-integration anchor too. Without this, the first
    // post-resume belt sample integrates dt back to a timestamp written
    // during/before the pause, crediting the paused gap as distance for any
    // pause shorter than the 30 s dtSec clamp (the GPS path is reset just
    // above for the same reason). Reset both so the next sample is a fresh
    // anchor.
    _treadmillLastSampleAt = null;
    _treadmillLastSpeedMps = 0;
    // The cumulative-distance re-anchor was armed in pause(): if a sample
    // landed during the pause it already disarmed it and rebased; if not, the
    // flag is still set and the first post-resume sample re-anchors.
  }

  /// Update the latest heart-rate reading the recorder stamps onto new
  /// [Waypoint]s. Pass `null` to clear (e.g. strap dropped). No-op
  /// while not recording — early samples before [begin] just get
  /// overwritten by the next one before they'd be applied.
  void setHeartRate(int? bpm) {
    // Drop obviously bogus readings rather than poison the saved track
    // — same bounds the HR-zone reader applies in apps/mobile_android/
    // lib/hr_zones.dart so a single malformed sample doesn't end up
    // visible in the breakdown anyway.
    if (bpm != null && (bpm < 30 || bpm > 230)) return;
    _currentBpm = bpm;
  }

  /// Feed a treadmill (FTMS) sample. The first call flips the recorder into
  /// treadmill mode, after which the headline distance comes from the belt
  /// rather than GPS. [speedMps] is the belt's instantaneous speed in metres
  /// per second; [totalDistanceMetres], when the belt reports it, is the
  /// cumulative session distance and is preferred over speed integration
  /// (rebased to 0 on the first sample so a belt that was already running
  /// doesn't credit pre-run distance).
  ///
  /// Wrapped in its own try/catch per the layered-resilience contract: a
  /// malformed belt sample must never throw into the recorder loop or
  /// degrade the GPS path. A bad sample is dropped and the last good distance
  /// is kept. No-op until [begin] (distance only accumulates while recording).
  void setTreadmillSample(double speedMps, {double? totalDistanceMetres}) {
    try {
      if (!_treadmillMode) {
        _treadmillMode = true;
        // Mid-run is the only way the belt ever engages, so every activation
        // lands on an already-accumulating run: hand the running total to the
        // source taking over instead of restarting it at the belt's own zero,
        // which dropped the GPS kilometres already run and made the next lap
        // split a negative (clamped to 0 m) delta. Arming the re-anchor makes
        // the first cumulative-total sample baseline onto the carried value,
        // the same formula the pause and console-reset re-anchors use.
        _treadmillDistanceMetres = _distanceMetres;
        _treadmillNeedsRebaseline = true;
      }
      if (!_recording) return;
      final now = DateTime.now();
      if (totalDistanceMetres != null) {
        if (_paused) {
          // The belt keeps counting while the user is paused; rebase the
          // baseline so the paused advance is excluded and the accumulated
          // distance freezes (mirrors the GPS path's `if (_paused) return`
          // and the speed branch's `!_paused` gate). This handles the
          // re-anchor itself, so disarm the post-resume one.
          _treadmillBaselineMetres = totalDistanceMetres - _treadmillDistanceMetres;
          _treadmillNeedsRebaseline = false;
        } else {
          if (_treadmillNeedsRebaseline) {
            // First sample after a resume where no sample landed during the
            // pause: re-anchor at the current belt total but PRESERVE the
            // accumulated distance, so the paused advance is dropped and the
            // distance continues from the pre-pause value (same formula as the
            // _paused branch above).
            _treadmillBaselineMetres =
                totalDistanceMetres - _treadmillDistanceMetres;
            _treadmillNeedsRebaseline = false;
          }
          _treadmillBaselineMetres ??= totalDistanceMetres;
          final lastTotal = _treadmillLastTotalMetres;
          if (lastTotal != null && totalDistanceMetres < lastTotal) {
            // The belt's cumulative counter went BACKWARDS. An FTMS console
            // zeroes it whenever its own session restarts (safety key pulled,
            // stop/start mid-run, workout ended on the console) — a permanent
            // step down, not a transient glitch, so the decrease has to be
            // measured against the last total we saw rather than the baseline
            // (which is usually 0 and so never trips). Holding the last good
            // value froze the headline distance for the rest of the run and
            // then dropped it to 0 once the belt climbed past the baseline
            // again. Rebase onto the new counter origin, preserving what has
            // already been accumulated (same formula as the pause and
            // post-resume re-anchors above), so belt distance is monotonic.
            _treadmillBaselineMetres =
                totalDistanceMetres - _treadmillDistanceMetres;
          }
          _treadmillDistanceMetres =
              totalDistanceMetres - _treadmillBaselineMetres!;
        }
        _treadmillLastTotalMetres = totalDistanceMetres;
      } else {
        final last = _treadmillLastSampleAt;
        if (last != null && !_paused) {
          final dtSec = now.difference(last).inMilliseconds / 1000.0;
          if (dtSec > 0 && dtSec < 30 && speedMps >= 0 && speedMps < _maxTreadmillSpeedMps) {
            _treadmillDistanceMetres += _treadmillLastSpeedMps * dtSec;
          }
        }
      }
      // Carry only a plausible speed forward. A bogus reading that just
      // failed the clamp above must NOT become the integrand for the next
      // interval — otherwise the next good sample integrates the glitch
      // (e.g. 999 m/s × 1 s ≈ 999 m of phantom distance). Keep the last
      // good speed instead.
      if (speedMps >= 0 && speedMps < _maxTreadmillSpeedMps) {
        _treadmillLastSpeedMps = speedMps;
      }
      _treadmillLastSampleAt = now;
    } catch (e) {
      debugPrint('RunRecorder: treadmill sample dropped — $e');
    }
  }

  /// Leave treadmill mode and hand the headline distance back to the GPS path.
  /// Called when the user turns treadmill mode off or the belt is forgotten
  /// mid-session.
  ///
  /// The accumulated total moves onto the GPS accumulator, the mirror of the
  /// carry [setTreadmillSample] does on the way in: one continuous run
  /// distance, handed between sources, never two rival accumulators one of
  /// which is discarded at the switch.
  void clearTreadmillMode() {
    if (_treadmillMode) _distanceMetres = _treadmillDistanceMetres;
    _treadmillMode = false;
    _resetTreadmillAccumulators();
  }

  /// Full reset (mode + accumulators) — used by [prepare] so each run starts
  /// on the GPS default until a belt sample flips it back on.
  void _resetTreadmill() {
    _treadmillMode = false;
    _resetTreadmillAccumulators();
  }

  void _resetTreadmillAccumulators() {
    _treadmillDistanceMetres = 0;
    _treadmillBaselineMetres = null;
    _treadmillLastTotalMetres = null;
    _treadmillLastSpeedMps = 0;
    _treadmillLastSampleAt = null;
    _treadmillNeedsRebaseline = false;
  }

  void _onPosition(Position pos) {
    if (_paused) return;

    if (pos.accuracy > _accuracyGateMetres) {
      _weakGps = true;
      final now = DateTime.now();
      final last = _lastAccuracyDropLogAt;
      if (last == null ||
          now.difference(last) >= const Duration(seconds: 5)) {
        _lastAccuracyDropLogAt = now;
        debugPrint(
          'RunRecorder: dropping fix — accuracy '
          '${pos.accuracy.toStringAsFixed(1)}m > gate '
          '${_accuracyGateMetres.toStringAsFixed(0)}m',
        );
      }
      return;
    }
    _weakGps = false;

    // Always refresh the raw current position so the blue dot updates on
    // every valid fix, independent of the track-append threshold. This
    // happens even before [begin] is called, so the map can show the runner
    // during the countdown.
    //
    // Use pos.timestamp (GPS-reported) rather than DateTime.now() so any
    // downstream consumer that subtracts two waypoint timestamps gets the
    // real elapsed time. Wall-clock dt collapsed to zero whenever positions
    // were processed in a tight loop (queued fixes after a CPU stall, or
    // synthetic injection in unit tests), and _calculatePace silently
    // returned null in those cases. Same lesson the speed-clamp learned
    // earlier in this file (see the "GPS-reported time" comment below).
    _currentWaypoint = Waypoint(
      lat: pos.latitude,
      lng: pos.longitude,
      // Keep the altitude whenever the platform reports a real vertical fix.
      // Gating on `altitude != 0` dropped a legitimate sea-level reading; a
      // finite positive altitudeAccuracy is the platform's signal that the
      // vertical component is a measurement rather than the unset default
      // (which reports 0 / non-finite accuracy).
      elevationMetres: (pos.altitudeAccuracy.isFinite &&
              pos.altitudeAccuracy > 0)
          ? pos.altitude
          : null,
      timestamp: pos.timestamp,
      bpm: _currentBpm,
    );
    _currentWaypointAt = DateTime.now();

    // Only append to the track and accumulate distance once the run has
    // officially started (post-[begin]).
    if (_recording) {
      final last = _lastTrackedPosition;
      final lastAt = _lastTrackedPositionAt;
      final lastElapsed = _lastTrackedElapsed;
      if (last == null || lastAt == null || lastElapsed == null) {
        _lastTrackedPosition = pos;
        _lastTrackedPositionAt = pos.timestamp;
        _lastTrackedElapsed = _stopwatch.elapsed;
        _track.add(_currentWaypoint!);
        _currentWaypointTrusted = true;
      } else {
        final delta = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          pos.latitude,
          pos.longitude,
        );
        // Implausible-speed clamp: compare the delta to the GPS-reported
        // time between the two fixes (not wall-clock) so batched/queued
        // positions processed in a tight loop still get clamped correctly.
        // A corrupt GPS fix can easily imply 50+ m/s — dropping those here
        // stops one bad sample from inflating total distance.
        //
        // A non-positive dt (two fixes sharing a timestamp, or a backwards
        // clock — both happen when Android batches queued fixes or after an
        // NTP correction) makes the speed undefined, so treat it as
        // implausible: with `dtSec > 0` guarding the ratio, a same-timestamp
        // teleport would otherwise skip the speed check and slip through on
        // the < 100 m hop filter alone, inflating distance. Rejecting it here
        // is lossless — the next fix with a real timestamp accumulates the
        // delta from this last-good position over the true elapsed time.
        final dtSec =
            pos.timestamp.difference(lastAt).inMilliseconds / 1000.0;
        final implausible =
            dtSec <= 0 || (delta / dtSec) > _maxSpeedMps;

        // Only grow the track + accumulate distance on real movement. Ignore
        // GPS jitter below the threshold, implausible jumps (>100m in one
        // hop), and anything faster than the activity's max plausible speed.
        // The same "has a genuine interval elapsed" question asked of the
        // monotonic clock. dtSec is GPS-reported time, so a device clock that
        // jumps backwards (NTP correction, manual change, a phone that boots
        // with a bad clock and then syncs) leaves lastAt in the future: every
        // later fix computes a non-positive dtSec, which is implausible by the
        // clamp above AND below the re-anchor window, so the anchor could never
        // rebase and distance stayed frozen until real time caught back up past
        // it. A stuck clock (every fix sharing a timestamp) froze it outright.
        // The stopwatch cannot go backwards or stall, so this arm makes the
        // re-anchor fire on real elapsed time no matter what the GPS timestamps
        // do — the escape is now unconditionally self-healing. It cannot weaken
        // the teleport guard: it only fires where GPS time claims a SHORTER gap
        // than the monotonic clock, i.e. exactly where GPS time is untrustworthy.
        final monotonicGapSec =
            (_stopwatch.elapsed - lastElapsed).inMilliseconds / 1000.0;
        if (delta > _trackThresholdMetres && delta < 100 && !implausible) {
          _distanceMetres += delta;
          _lastTrackedPosition = pos;
          _lastTrackedPositionAt = pos.timestamp;
          _lastTrackedElapsed = _stopwatch.elapsed;
          _track.add(_currentWaypoint!);
          _currentWaypointTrusted = true;
        } else if (dtSec >= _gpsReanchorAfterSeconds ||
            monotonicGapSec >= _gpsReanchorAfterSeconds) {
          // Real GPS gap: the hop failed the < 100 m cap (the runner genuinely
          // moved away while fixes were dropped) but a genuine interval has
          // elapsed. Rebase the anchor to this fresh fix WITHOUT crediting the
          // un-sampled gap distance — exactly how resume() nulls the anchor so
          // the first post-resume fix re-anchors. Without this the anchor stays
          // stale, every later delta only grows past 100 m, and distance is
          // frozen for the rest of the run (#330). Both gates must agree the
          // gap is short for a hop to fail closed, so a zero/near-zero-dt
          // duplicate arriving immediately is still rejected as a teleport.
          //
          // Seal the pace window at the same time, exactly as resume() and
          // _beginResumed() do — this branch creates the identical
          // discontinuity. The gap's metres are deliberately NOT credited, so
          // a rolling window spanning it times the un-credited distance
          // against the gap's clock: 5 clean fixes at 200 s/km followed by a
          // 12 s Doze batch 150 m on measured 128 s/km, i.e. the recorder
          // claiming zero extra metres and a sub-world-record pace at once.
          // That value feeds the pace-alert and cut-off catch-up voice cues
          // and live_cutoff_eta's projection, so the error runs in the
          // direction that SUPPRESSES a safety warning.
          _paceFloorIdx = _track.length;
          _lastTrackedPosition = pos;
          _lastTrackedPositionAt = pos.timestamp;
          _lastTrackedElapsed = _stopwatch.elapsed;
          _track.add(_currentWaypoint!);
          _currentWaypointTrusted = true;
        } else {
          _currentWaypointTrusted = false;
        }
      }
    } else {
      _currentWaypointTrusted = true;
    }

    _emitSnapshot();
  }

  /// Headline distance: belt distance in treadmill mode, GPS-accumulated
  /// distance otherwise. Reading this is the only place the treadmill source
  /// influences a normal run — when [_treadmillMode] is false (the default)
  /// it is exactly the GPS value.
  double get _reportedDistanceMetres =>
      _treadmillMode ? _treadmillDistanceMetres : _distanceMetres;

  void _emitSnapshot() {
    final current = _currentWaypoint;
    final elapsed = _stopwatch.elapsed + _elapsedOffset;
    final pace = _calculatePace();

    // Route-relative fields are only meaningful once we have a fix AND a
    // route is loaded. When the 1-second timer fires without a new GPS
    // fix (indoor mode, warmup, stationary runner) the position hasn't
    // moved — the last cached off-route / remaining values are still
    // correct. Skipping the O(R) segment projection over the full route
    // on every tick is a real win on long routes (e.g. a 40 km
    // imported ride with 2000 waypoints).
    double? offRoute;
    double? remaining;
    if (current != null) {
      // Reuse the cached values both when the position hasn't changed and when
      // the current fix is one the distance filter rejected — an untrusted fix
      // must not advance the monotonic route floor (see
      // [_currentWaypointTrusted]). The last trusted fix's values are still
      // the best available answer.
      if (identical(current, _lastRouteCalcFor) || !_currentWaypointTrusted) {
        offRoute = _cachedOffRoute;
        remaining = _cachedRouteRemaining;
      } else {
        // One pass for both — shares the closest-segment search instead of
        // walking every route segment twice (off-route + remaining).
        final progress = _routeProgress(current);
        offRoute = progress?.offRoute;
        remaining = progress?.remaining;
        _lastRouteCalcFor = current;
        _cachedOffRoute = offRoute;
        _cachedRouteRemaining = remaining;
      }
    }

    // Debug-only guard that the shared track view is still the one
    // callers expect. The efficiency contract is that every snapshot
    // carries the SAME `_trackView` reference (wrapping `_track` by
    // reference). If someone reintroduces a per-emit wrapper
    // allocation here, the reference changes per emit and we regress
    // the allocation fix. Stripped in release.
    assert(
      _trackView.length == _track.length,
      'Shared _trackView out of sync with _track.',
    );

    _controller.add(RunSnapshot(
      elapsed: elapsed,
      distanceMetres: _reportedDistanceMetres,
      currentPaceSecondsPerKm: pace,
      currentPosition: current,
      positionFixedAt: _currentWaypointAt,
      positionTrusted: _currentWaypointTrusted,
      track: _trackView,
      offRouteDistanceMetres: offRoute,
      routeRemainingMetres: remaining,
      weakGps: _weakGps,
    ));
  }

  /// Distance from the runner's current position to the end of the route,
  /// measured along the remaining route segments.
  ///
  /// Finds the closest point on the route to the runner, then sums the
  /// distance from there to the final waypoint. Returns null if no route is
  /// selected.
  double? _routeRemaining(Waypoint pos) {
    final route = _route;
    if (route == null || route.waypoints.length < 2) return null;

    // Find the segment closest to the runner, never matching a segment
    // earlier than [_minMatchedSegmentIdx] (monotonic progress — see the
    // field doc). Clamp the floor to the route length in case the route
    // shrank between calls.
    final searchStart = _minMatchedSegmentIdx.clamp(1, route.waypoints.length - 1);
    int closestSegmentIdx = searchStart;
    double minDist = double.infinity;
    double tAtClosest = 0;
    for (int i = searchStart; i < route.waypoints.length; i++) {
      final a = route.waypoints[i - 1];
      final b = route.waypoints[i];
      final result = _projectPointOnSegment(
        pos.lat,
        pos.lng,
        a.lat,
        a.lng,
        b.lat,
        b.lng,
      );
      if (result.distance < minDist) {
        minDist = result.distance;
        closestSegmentIdx = i;
        tAtClosest = result.t;
      }
    }
    _minMatchedSegmentIdx = closestSegmentIdx;

    // Distance from closest projection to end of current segment, then sum
    // the lengths of all subsequent segments.
    final a = route.waypoints[closestSegmentIdx - 1];
    final b = route.waypoints[closestSegmentIdx];
    final segLen = _haversine(a.lat, a.lng, b.lat, b.lng);
    double remaining = segLen * (1 - tAtClosest);

    for (int i = closestSegmentIdx + 1; i < route.waypoints.length; i++) {
      final p = route.waypoints[i - 1];
      final q = route.waypoints[i];
      remaining += _haversine(p.lat, p.lng, q.lat, q.lng);
    }
    return remaining;
  }

  /// Off-route distance + distance-remaining in a SINGLE walk over the route.
  /// [_offRouteDistance] and [_routeRemaining] each scan every segment
  /// projecting [pos] to find the closest one; computing them separately does
  /// that closest-segment search twice. This shares it — the min perpendicular
  /// distance IS the off-route value (`_distanceToSegmentMetres` ==
  /// projection distance), so the result is identical with half the projection
  /// trig. Null when no route is selected (matches both methods' contract).
  ({double offRoute, double remaining})? _routeProgress(Waypoint pos) {
    final route = _route;
    if (route == null || route.waypoints.length < 2) return null;

    final searchStart = _minMatchedSegmentIdx.clamp(1, route.waypoints.length - 1);
    int closestSegmentIdx = searchStart;
    double minDist = double.infinity;
    double tAtClosest = 0;
    for (int i = searchStart; i < route.waypoints.length; i++) {
      final a = route.waypoints[i - 1];
      final b = route.waypoints[i];
      final result = _projectPointOnSegment(pos.lat, pos.lng, a.lat, a.lng, b.lat, b.lng);
      if (result.distance < minDist) {
        minDist = result.distance;
        closestSegmentIdx = i;
        tAtClosest = result.t;
      }
    }
    _minMatchedSegmentIdx = closestSegmentIdx;

    final a = route.waypoints[closestSegmentIdx - 1];
    final b = route.waypoints[closestSegmentIdx];
    final segLen = _haversine(a.lat, a.lng, b.lat, b.lng);
    // Partial current segment + the precomputed length of every segment after
    // it (O(1)) instead of re-summing the route tail on every fix.
    final tail = _routeTailAfter;
    final remaining = segLen * (1 - tAtClosest) +
        (tail != null && closestSegmentIdx < tail.length ? tail[closestSegmentIdx] : 0);
    return (offRoute: minDist, remaining: remaining);
  }

  /// Suffix sums of route segment lengths. `tail[k]` is the summed length of
  /// every segment strictly after segment k (segment j connects waypoint
  /// j-1 → j). Built once per route so [_routeProgress] can resolve the
  /// remaining-route distance in O(1). Null for a route too short to have a
  /// segment.
  static List<double>? _computeRouteTailAfter(Route? route) {
    if (route == null || route.waypoints.length < 2) return null;
    final wps = route.waypoints;
    final n = wps.length;
    final tail = List<double>.filled(n, 0);
    for (int k = n - 2; k >= 0; k--) {
      tail[k] = tail[k + 1] + _haversine(wps[k].lat, wps[k].lng, wps[k + 1].lat, wps[k + 1].lng);
    }
    return tail;
  }

  /// Project a point onto a line segment using equirectangular coordinates.
  /// Returns the perpendicular distance and t (0..1 along segment).
  static _ProjectionResult _projectPointOnSegment(
      double pLat, double pLng, double aLat, double aLng, double bLat, double bLng) {
    const metresPerDegreeLat = 111320.0;
    final metresPerDegreeLng = 111320.0 * cos(_toRad(aLat));

    final px = (pLng - aLng) * metresPerDegreeLng;
    final py = (pLat - aLat) * metresPerDegreeLat;
    final bx = (bLng - aLng) * metresPerDegreeLng;
    final by = (bLat - aLat) * metresPerDegreeLat;

    final lenSq = bx * bx + by * by;
    if (lenSq == 0) {
      return _ProjectionResult(sqrt(px * px + py * py), 0);
    }
    var t = (px * bx + py * by) / lenSq;
    t = t.clamp(0.0, 1.0);
    final cx = bx * t;
    final cy = by * t;
    final dx = px - cx;
    final dy = py - cy;
    return _ProjectionResult(sqrt(dx * dx + dy * dy), t);
  }

  /// Minimum distance (in metres) from the current position to any segment
  /// of the selected [Route]. Returns null if no route is selected.
  double? _offRouteDistance(Waypoint pos) {
    final route = _route;
    if (route == null || route.waypoints.length < 2) return null;

    // Search from the monotonic floor (see [_minMatchedSegmentIdx]) so the
    // off-route distance reflects the same already-passed-segments view as
    // [_routeProgress]; reading the floor without advancing it (this helper
    // measures off-route distance, it doesn't own progress).
    final searchStart = _minMatchedSegmentIdx.clamp(1, route.waypoints.length - 1);
    double minDist = double.infinity;
    for (int i = searchStart; i < route.waypoints.length; i++) {
      final a = route.waypoints[i - 1];
      final b = route.waypoints[i];
      final d = _distanceToSegmentMetres(pos.lat, pos.lng, a.lat, a.lng, b.lat, b.lng);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  /// Shortest distance in metres from point P to segment A-B using equirectangular
  /// projection (accurate enough for short running-route segments).
  static double _distanceToSegmentMetres(
      double pLat, double pLng, double aLat, double aLng, double bLat, double bLng) {
    // Convert to metres using equirectangular projection centered on A
    const metresPerDegreeLat = 111320.0;
    final metresPerDegreeLng = 111320.0 * cos(_toRad(aLat));

    final px = (pLng - aLng) * metresPerDegreeLng;
    final py = (pLat - aLat) * metresPerDegreeLat;
    final bx = (bLng - aLng) * metresPerDegreeLng;
    final by = (bLat - aLat) * metresPerDegreeLat;

    final lenSq = bx * bx + by * by;
    if (lenSq == 0) return sqrt(px * px + py * py);

    var t = (px * bx + py * by) / lenSq;
    t = t.clamp(0.0, 1.0);

    final cx = bx * t;
    final cy = by * t;
    final dx = px - cx;
    final dy = py - cy;
    return sqrt(dx * dx + dy * dy);
  }

  /// Calculate pace from the last ~200m of track.
  double? _calculatePace() {
    // Never walk back across a pause / process-kill boundary. `_track` keeps
    // the pre-pause tail, but its timestamps are separated from the
    // post-resume points by the paused wall-clock gap — which is unbounded
    // (a resumed run may have been dead for up to kResumableWindow). Timing
    // post-resume distance against a pre-pause timestamp reported a pace
    // hundreds of times too slow for the first ~200 m after every resume, and
    // the run screen feeds that number to the pace-alert and cut-off
    // catch-up voice cues.
    final floor = _paceFloorIdx.clamp(0, _track.length);
    if (_track.length - floor < 5) return null;

    double segmentDistance = 0;
    int segmentStart = _track.length - 1;

    for (int i = _track.length - 2; i >= floor; i--) {
      final a = _track[i];
      final b = _track[i + 1];
      segmentDistance += _haversine(a.lat, a.lng, b.lat, b.lng);
      segmentStart = i;
      if (segmentDistance >= 200) break;
    }

    if (segmentDistance < 50) return null;

    final startTs = _track[segmentStart].timestamp;
    final endTs = _track.last.timestamp;
    if (startTs == null || endTs == null) return null;

    final segmentTime = endTs.difference(startTs).inMilliseconds / 1000.0;
    if (segmentTime <= 0) return null;

    return (segmentTime / segmentDistance) * 1000; // seconds per km
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // Earth radius in metres
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * pi / 180;

  /// Mark a lap split at the current position. Returns the lap number.
  int lap() {
    if (!_recording) return 0;
    final now = DateTime.now();
    _laps.add(LapSplit(
      number: _laps.length + 1,
      timestamp: now,
      cumulativeDistanceMetres: _reportedDistanceMetres,
      cumulativeDuration: _currentElapsed(),
    ));
    return _laps.length;
  }

  Duration _currentElapsed() => _stopwatch.elapsed + _elapsedOffset;

  /// Stop recording and return the completed [Run].
  Future<Run> stop() async {
    _recording = false;
    _prepared = false;
    _stopwatch.stop();
    _timer?.cancel();
    _timer = null;
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer = null;
    await _positionSub?.cancel();
    _positionSub = null;

    final startedAt = _startTime ?? DateTime.now();
    final elapsed = _stopwatch.elapsed + _elapsedOffset;

    final metadata = <String, dynamic>{};
    if (_laps.isNotEmpty) metadata['laps'] = lapsToCanonicalJson(_laps);
    if (_treadmillMode) {
      // Belt-measured distance is not GPS-measured, so the same exclusion the
      // pedometer-estimated indoor path uses applies: `indoor: true` keeps it
      // out of the VDOT ceiling, and `indoor_source` records that the belt
      // (not a pedometer estimate) supplied the distance.
      metadata['indoor'] = true;
      metadata['indoor_source'] = 'treadmill';
      metadata['distance_source'] = 'treadmill';
    }

    return Run(
      id: _uuid.v4(),
      startedAt: startedAt,
      duration: elapsed,
      distanceMetres: _reportedDistanceMetres,
      track: List.unmodifiable(_track),
      source: RunSource.app,
      metadata: metadata.isEmpty ? null : metadata,
    );
  }

  /// Clean up resources. Terminal: the recorder cannot record again, and
  /// [prepare] on a disposed recorder throws rather than handing back one that
  /// silently never opens a stream.
  void dispose() {
    _disposed = true;
    _recording = false;
    _prepared = false;
    _timer?.cancel();
    _timer = null;
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _controller.close();
  }
}

class _ProjectionResult {
  final double distance;
  final double t;
  const _ProjectionResult(this.distance, this.t);
}
