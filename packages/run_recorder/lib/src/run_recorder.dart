import 'dart:async';
import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:geolocator/geolocator.dart';

import 'run_snapshot.dart';

/// Manages a live GPS recording session.
///
/// Streams position updates, calculates pace, and accumulates distance.
class RunRecorder {
  final _controller = StreamController<RunSnapshot>.broadcast();
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;

  DateTime? _startTime;
  double _distanceMetres = 0;
  final List<Waypoint> _track = [];
  Position? _lastPosition;
  bool _recording = false;

  /// Emits a [RunSnapshot] every second during recording.
  Stream<RunSnapshot> get snapshots => _controller.stream;

  /// Begin recording a run, optionally following a [route].
  Future<void> start({Route? route}) async {
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
    _lastPosition = null;
    _recording = true;

    // GPS position stream
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // metres between updates
      ),
    ).listen(_onPosition);

    // 1-second timer for elapsed time updates
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_recording || _track.isEmpty) return;
      _emitSnapshot();
    });
  }

  void _onPosition(Position pos) {
    if (!_recording) return;

    // Filter inaccurate readings
    if (pos.accuracy > 30) return;

    if (_lastPosition != null) {
      final delta = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );
      // Ignore GPS jitter (<2m) and implausible jumps (>100m)
      if (delta > 2 && delta < 100) {
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

    final elapsed = DateTime.now().difference(_startTime!);
    final pace = _calculatePace();

    _controller.add(RunSnapshot(
      elapsed: elapsed,
      distanceMetres: _distanceMetres,
      currentPaceSecondsPerKm: pace,
      currentPosition: _track.last,
      track: List.unmodifiable(_track),
    ));
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

  /// Stop recording and return the completed [Run].
  Future<Run> stop() async {
    _recording = false;
    _timer?.cancel();
    _timer = null;
    await _positionSub?.cancel();
    _positionSub = null;

    final startedAt = _startTime ?? DateTime.now();
    final elapsed = DateTime.now().difference(startedAt);

    return Run(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startedAt: startedAt,
      duration: elapsed,
      distanceMetres: _distanceMetres,
      track: List.unmodifiable(_track),
      source: RunSource.app,
    );
  }

  /// Clean up resources.
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    _controller.close();
  }
}
