import 'dart:async';
import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import 'run_snapshot.dart';

/// Manages a live GPS recording session.
///
/// Streams position updates, calculates pace, and accumulates distance.
/// A single lap recorded mid-run.
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

class RunRecorder {
  static const _uuid = Uuid();

  final _controller = StreamController<RunSnapshot>.broadcast();
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  final List<LapSplit> _laps = [];

  /// All lap splits recorded so far.
  List<LapSplit> get laps => List.unmodifiable(_laps);

  DateTime? _startTime;
  double _distanceMetres = 0;
  final List<Waypoint> _track = [];
  Position? _lastPosition;
  bool _recording = false;
  bool _paused = false;
  Duration _pausedTotal = Duration.zero;
  DateTime? _pausedSince;
  Route? _route;
  double _minMovementMetres = 2;

  /// Emits a [RunSnapshot] every second during recording.
  Stream<RunSnapshot> get snapshots => _controller.stream;

  /// Begin recording a run, optionally following a [route].
  ///
  /// [distanceFilterMetres] tunes the GPS update frequency — larger values
  /// produce fewer updates and ignore more noise (good for cycling).
  /// [minMovementMetres] is the smallest delta that counts toward distance —
  /// anything smaller is treated as GPS jitter.
  Future<void> start({
    Route? route,
    int distanceFilterMetres = 3,
    double minMovementMetres = 2,
  }) async {
    // Ensure location permission
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      throw Exception('Location permission denied');
    }

    _startTime = DateTime.now();
    _distanceMetres = 0;
    _track.clear();
    _laps.clear();
    _lastPosition = null;
    _recording = true;
    _paused = false;
    _pausedTotal = Duration.zero;
    _pausedSince = null;
    _route = route;
    _minMovementMetres = minMovementMetres;

    // GPS position stream with Android foreground service config
    // so recording continues when the app is backgrounded or screen is off.
    _positionSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMetres,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Run in progress',
          notificationText: 'Recording your run',
          enableWakeLock: true,
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        ),
      ),
    ).listen(_onPosition);

    // 1-second timer for elapsed time updates
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_recording || _track.isEmpty) return;
      _emitSnapshot();
    });
  }

  /// Pause the timer and stop accumulating distance until [resume] is called.
  void pause() {
    if (!_recording || _paused) return;
    _paused = true;
    _pausedSince = DateTime.now();
  }

  /// Resume after a [pause]. Adds the paused interval to the total.
  void resume() {
    if (!_recording || !_paused) return;
    if (_pausedSince != null) {
      _pausedTotal += DateTime.now().difference(_pausedSince!);
    }
    _paused = false;
    _pausedSince = null;
    _lastPosition = null; // avoid a big jump after resume
  }

  void _onPosition(Position pos) {
    if (!_recording || _paused) return;

    // Filter inaccurate readings
    if (pos.accuracy > 30) return;

    if (_lastPosition != null) {
      final delta = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );
      // Ignore GPS jitter and implausible jumps (>100m)
      if (delta > _minMovementMetres && delta < 100) {
        _distanceMetres += delta;
      }
    }

    _lastPosition = pos;
    _track.add(Waypoint(
      lat: pos.latitude,
      lng: pos.longitude,
      elevationMetres: pos.altitude != 0 ? pos.altitude : null,
      timestamp: DateTime.now(),
    ));

    _emitSnapshot();
  }

  void _emitSnapshot() {
    if (_startTime == null || _track.isEmpty) return;

    var elapsed = DateTime.now().difference(_startTime!) - _pausedTotal;
    if (_paused && _pausedSince != null) {
      elapsed -= DateTime.now().difference(_pausedSince!);
    }
    if (elapsed.isNegative) elapsed = Duration.zero;
    final pace = _calculatePace();
    final offRoute = _offRouteDistance();
    final remaining = _routeRemaining();

    _controller.add(RunSnapshot(
      elapsed: elapsed,
      distanceMetres: _distanceMetres,
      currentPaceSecondsPerKm: pace,
      currentPosition: _track.last,
      track: List.unmodifiable(_track),
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
  double? _routeRemaining() {
    final route = _route;
    if (route == null || route.waypoints.length < 2) return null;
    final pos = _track.last;

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
  double? _offRouteDistance() {
    final route = _route;
    if (route == null || route.waypoints.length < 2) return null;
    final pos = _track.last;

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

  Duration _currentElapsed() {
    if (_startTime == null) return Duration.zero;
    var elapsed = DateTime.now().difference(_startTime!) - _pausedTotal;
    if (_paused && _pausedSince != null) {
      elapsed -= DateTime.now().difference(_pausedSince!);
    }
    if (elapsed.isNegative) elapsed = Duration.zero;
    return elapsed;
  }

  /// Stop recording and return the completed [Run].
  Future<Run> stop() async {
    _recording = false;
    _timer?.cancel();
    _timer = null;
    await _positionSub?.cancel();
    _positionSub = null;

    final startedAt = _startTime ?? DateTime.now();
    var elapsed = DateTime.now().difference(startedAt) - _pausedTotal;
    if (_paused && _pausedSince != null) {
      elapsed -= DateTime.now().difference(_pausedSince!);
    }
    if (elapsed.isNegative) elapsed = Duration.zero;

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
    _positionSub?.cancel();
    _controller.close();
  }
}

class _ProjectionResult {
  final double distance;
  final double t;
  const _ProjectionResult(this.distance, this.t);
}
