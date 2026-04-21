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
/// duration at the moment the user tapped the lap button.
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

  Map<String, dynamic> toJson() => {
        'number': number,
        'timestamp': timestamp.toIso8601String(),
        'cumulative_distance_m': cumulativeDistanceMetres,
        'cumulative_duration_s': cumulativeDuration.inSeconds,
      };
}

/// Manages a live GPS recording session: opens the position stream, filters
/// noise, accumulates distance, and emits [RunSnapshot]s to the UI. Survives
/// a missing/revoked GPS signal — [prepare] flips [prepared] even when the
/// stream can't open, and a retry loop reopens the stream when services
/// come back.
class RunRecorder {
  static const _uuid = Uuid();

  /// How often [prepare] retries opening the position stream when it is
  /// currently absent (services/permission denied at start, or the stream
  /// errored mid-run). Short enough that re-enabling Location in Settings
  /// feels immediate; long enough to avoid thrash.
  static const _gpsRetryInterval = Duration(seconds: 3);

  final _controller = StreamController<RunSnapshot>.broadcast();
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  Timer? _gpsRetryTimer;
  final List<LapSplit> _laps = [];

  /// All lap splits recorded so far.
  List<LapSplit> get laps => List.unmodifiable(_laps);

  DateTime? _startTime;
  /// Monotonic clock for elapsed time. Unlike `DateTime.now()`, [Stopwatch]
  /// is unaffected by wall-clock jumps (NTP sync, manual time change,
  /// timezone change) — the run duration stays correct.
  final Stopwatch _stopwatch = Stopwatch();
  double _distanceMetres = 0;
  final List<Waypoint> _track = [];
  // Single read-only view handed out on every snapshot. `UnmodifiableListView`
  // wraps `_track` by reference — appending to `_track` is still visible
  // through the view, and there's no new wrapper allocated per emission
  // (which used to fire 1×/second minimum + once per GPS fix).
  late final UnmodifiableListView<Waypoint> _trackView =
      UnmodifiableListView(_track);
  /// Latest raw GPS fix — drives the blue dot on the live map and updates
  /// on every fix, independent of the track-append threshold.
  Waypoint? _currentWaypoint;
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
  DateTime? _lastTrackedPositionAt;
  bool _recording = false;
  bool _paused = false;
  Route? _route;
  double _trackThresholdMetres = 3;
  double _maxSpeedMps = 10;
  double _accuracyGateMetres = 20;
  // Remembered so the retry loop can re-open the position stream with the
  // same accuracy setting the caller passed to [prepare].
  LocationAccuracy _locationAccuracy = LocationAccuracy.high;

  /// Emits a [RunSnapshot] on every GPS fix once [prepare] has run, and once
  /// per second after [begin] starts recording time.
  Stream<RunSnapshot> get snapshots => _controller.stream;

  /// Whether [prepare] has completed. True even when GPS is unavailable —
  /// the recorder accepts [begin] and emits time-only snapshots until a
  /// fix arrives (or the retry loop re-opens the stream).
  bool get prepared => _prepared;
  bool _prepared = false;

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
  /// permission prompt. Both errors leave [prepared] == true; the recorder
  /// is still usable as a time-only session and the retry loop will re-open
  /// the stream automatically when services / permission come back.
  Future<void> prepare({
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
    double maxSpeedMps = 10,
    LocationAccuracy accuracy = LocationAccuracy.high,
    double accuracyGateMetres = 20,
  }) async {
    // Reset state first and flip _prepared = true unconditionally. If GPS
    // setup below throws, the recorder is still usable for a time-only
    // (indoor / treadmill) run — begin() will start the stopwatch, the
    // 1-second timer emits snapshots with a null currentPosition, and the
    // live map falls back to its "Waiting for GPS..." placeholder. If GPS
    // later becomes available the caller can call prepare() again.
    _startTime = null;
    _stopwatch
      ..stop()
      ..reset();
    _distanceMetres = 0;
    _track.clear();
    _laps.clear();
    _currentWaypoint = null;
    _lastTrackedPosition = null;
    _lastTrackedPositionAt = null;
    _lastRouteCalcFor = null;
    _cachedOffRoute = null;
    _cachedRouteRemaining = null;
    _recording = false;
    _paused = false;
    _route = route;
    _trackThresholdMetres =
        max(distanceFilterMetres.toDouble(), minMovementMetres);
    _maxSpeedMps = maxSpeedMps;
    _accuracyGateMetres = accuracyGateMetres;
    _locationAccuracy = accuracy;
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
    if (permission == LocationPermission.deniedForever) {
      throw LocationPermissionDeniedError(forever: true);
    }
    if (permission == LocationPermission.denied) {
      throw LocationPermissionDeniedError();
    }

    _openPositionStream();
  }

  /// Subscribe to [Geolocator.getPositionStream] with the accuracy settings
  /// remembered from the last [prepare] call. Any stream error (commonly
  /// thrown when the user toggles Location off mid-run) cancels the
  /// subscription and clears [_positionSub] — the retry loop picks it back
  /// up once services are available again.
  void _openPositionStream() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
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
      ),
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

  /// Periodically check whether GPS is available and (re-)open the
  /// position stream if it's currently down. Idempotent — a healthy
  /// stream is a no-op.
  void _startGpsRetryLoop() {
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer = Timer.periodic(_gpsRetryInterval, (_) async {
      if (!_prepared) return;
      if (_positionSub != null) return;
      try {
        if (!await Geolocator.isLocationServiceEnabled()) return;
        final p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied ||
            p == LocationPermission.deniedForever) return;
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
    _stopwatch
      ..stop()
      ..reset();
    _distanceMetres = 0;
    _track.clear();
    _laps.clear();
    _currentWaypoint = null;
    _lastTrackedPosition = null;
    _lastTrackedPositionAt = null;
    _lastRouteCalcFor = null;
    _cachedOffRoute = null;
    _cachedRouteRemaining = null;
    _recording = false;
    _paused = false;
    _route = route;
    _trackThresholdMetres =
        max(distanceFilterMetres.toDouble(), minMovementMetres);
    _maxSpeedMps = maxSpeedMps;
    _accuracyGateMetres = accuracyGateMetres;
    _prepared = true;
  }

  /// Test-only: push a simulated [Position] through the same filter chain
  /// the live geolocator subscription would use.
  @visibleForTesting
  void debugInjectPosition(Position pos) => _onPosition(pos);

  /// Test-only: read-only view of the track built so far.
  @visibleForTesting
  List<Waypoint> get debugTrack => List.unmodifiable(_track);

  /// Test-only: current accumulated distance.
  @visibleForTesting
  double get debugDistanceMetres => _distanceMetres;

  /// Test-only: elapsed time as seen by the monotonic stopwatch.
  @visibleForTesting
  Duration get debugElapsed => _stopwatch.elapsed;

  /// Test-only: latest raw waypoint (drives the blue dot).
  @visibleForTesting
  Waypoint? get debugCurrentWaypoint => _currentWaypoint;

  /// Pause the timer and stop accumulating distance until [resume] is called.
  void pause() {
    if (!_recording || _paused) return;
    _paused = true;
    _stopwatch.stop();
  }

  /// Resume after a [pause].
  void resume() {
    if (!_recording || !_paused) return;
    _paused = false;
    _stopwatch.start();
    _lastTrackedPosition = null; // avoid a big jump after resume
    _lastTrackedPositionAt = null;
  }

  void _onPosition(Position pos) {
    if (_paused) return;

    if (pos.accuracy > _accuracyGateMetres) return;

    // Always refresh the raw current position so the blue dot updates on
    // every valid fix, independent of the track-append threshold. This
    // happens even before [begin] is called, so the map can show the runner
    // during the countdown.
    _currentWaypoint = Waypoint(
      lat: pos.latitude,
      lng: pos.longitude,
      elevationMetres: pos.altitude != 0 ? pos.altitude : null,
      timestamp: DateTime.now(),
    );

    // Only append to the track and accumulate distance once the run has
    // officially started (post-[begin]).
    if (_recording) {
      final last = _lastTrackedPosition;
      final lastAt = _lastTrackedPositionAt;
      if (last == null || lastAt == null) {
        _lastTrackedPosition = pos;
        _lastTrackedPositionAt = pos.timestamp;
        _track.add(_currentWaypoint!);
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
        final dtSec =
            pos.timestamp.difference(lastAt).inMilliseconds / 1000.0;
        final implausible =
            dtSec > 0 && (delta / dtSec) > _maxSpeedMps;

        // Only grow the track + accumulate distance on real movement. Ignore
        // GPS jitter below the threshold, implausible jumps (>100m in one
        // hop), and anything faster than the activity's max plausible speed.
        if (delta > _trackThresholdMetres && delta < 100 && !implausible) {
          _distanceMetres += delta;
          _lastTrackedPosition = pos;
          _lastTrackedPositionAt = pos.timestamp;
          _track.add(_currentWaypoint!);
        }
      }
    }

    _emitSnapshot();
  }

  void _emitSnapshot() {
    final current = _currentWaypoint;
    final elapsed = _stopwatch.elapsed;
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
      if (identical(current, _lastRouteCalcFor)) {
        offRoute = _cachedOffRoute;
        remaining = _cachedRouteRemaining;
      } else {
        offRoute = _offRouteDistance(current);
        remaining = _routeRemaining(current);
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
      distanceMetres: _distanceMetres,
      currentPaceSecondsPerKm: pace,
      currentPosition: current,
      track: _trackView,
      offRouteDistanceMetres: offRoute,
      routeRemainingMetres: remaining,
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

    // Find the segment closest to the runner.
    int closestSegmentIdx = 0;
    double minDist = double.infinity;
    double tAtClosest = 0;
    for (int i = 1; i < route.waypoints.length; i++) {
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

    double minDist = double.infinity;
    for (int i = 1; i < route.waypoints.length; i++) {
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
    if (_track.length < 5) return null;

    double segmentDistance = 0;
    int segmentStart = _track.length - 1;

    for (int i = _track.length - 2; i >= 0; i--) {
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
      cumulativeDistanceMetres: _distanceMetres,
      cumulativeDuration: _currentElapsed(),
    ));
    return _laps.length;
  }

  Duration _currentElapsed() => _stopwatch.elapsed;

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
    final elapsed = _stopwatch.elapsed;

    return Run(
      id: _uuid.v4(),
      startedAt: startedAt,
      duration: elapsed,
      distanceMetres: _distanceMetres,
      track: List.unmodifiable(_track),
      source: RunSource.app,
      metadata: _laps.isEmpty
          ? null
          : {'laps': _laps.map((l) => l.toJson()).toList()},
    );
  }

  /// Clean up resources.
  void dispose() {
    _timer?.cancel();
    _gpsRetryTimer?.cancel();
    _positionSub?.cancel();
    _controller.close();
  }
}

class _ProjectionResult {
  final double distance;
  final double t;
  const _ProjectionResult(this.distance, this.t);
}
