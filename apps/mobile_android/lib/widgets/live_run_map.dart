import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:latlong2/latlong.dart';

import '../tile_cache.dart';

/// Live map shown during a run, displaying the GPS track and current position.
///
/// Inspired by Nike Run Club: dark map, bright route line, pulsing blue dot.
class LiveRunMap extends StatefulWidget {
  /// The GPS track recorded so far.
  final List<Waypoint> track;

  /// Latest raw GPS fix. When present, drives the blue dot so it can refresh
  /// faster than the track-append threshold. Falls back to the last track
  /// point when null.
  final Waypoint? currentPosition;

  /// Optional planned route to show underneath the live track.
  final List<Waypoint>? plannedRoute;

  /// Whether to auto-follow the runner's position.
  final bool followRunner;

  /// Logical pixels at the bottom of the widget that are covered by an
  /// overlay (e.g. the run stats panel). The follow-cam shifts the dot up by
  /// half of this so it sits in the visible area above the overlay instead
  /// of behind it.
  final double bottomPadding;

  const LiveRunMap({
    super.key,
    required this.track,
    this.currentPosition,
    this.plannedRoute,
    this.followRunner = true,
    this.bottomPadding = 0,
  });

  @override
  State<LiveRunMap> createState() => _LiveRunMapState();
}

class _LiveRunMapState extends State<LiveRunMap> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _userPanned = false;
  bool _mapReady = false;

  // Shared disk-backed tile cache (via [TileCache.init] at app startup).
  // Survives app restarts — a previously-loaded area renders offline.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Position interpolation — tweens the dot from the previous GPS fix to the
  // next one over [_positionTweenDuration] so it glides instead of hopping.
  // The camera (when following) rides the interpolated position too.
  static const _positionTweenDuration = Duration(milliseconds: 900);
  late final AnimationController _positionController;
  LatLng? _animatedLatLng;
  LatLng? _tweenStart;
  LatLng? _tweenEnd;

  // Cached smoothed track polyline. The tween controller drives ~1 Hz
  // rebuilds of LiveRunMap and each previously re-ran two O(n) smoothing
  // passes over the full track. Recompute only when the length changes —
  // the recorder only appends to the track, so a matching length means
  // the points are identical and the smoothed view is still valid.
  List<LatLng>? _cachedSmoothedTrack;
  int _cachedSmoothedForLength = -1;

  String get _tileUrl {
    final key = dotenv.env['MAPTILER_KEY'] ?? '';
    return 'https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}@2x.png?key=$key';
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.4, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _positionController = AnimationController(
      vsync: this,
      duration: _positionTweenDuration,
    )..addListener(_onPositionTick);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _positionController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onPositionTick() {
    final start = _tweenStart;
    final end = _tweenEnd;
    if (start == null || end == null) return;
    final t = Curves.linear.transform(_positionController.value);
    final next = LatLng(
      start.latitude + (end.latitude - start.latitude) * t,
      start.longitude + (end.longitude - start.longitude) * t,
    );
    setState(() => _animatedLatLng = next);

    if (widget.followRunner && !_userPanned) {
      _moveCamera(next);
    }
  }

  Waypoint? get _latestPosition =>
      widget.currentPosition ??
      (widget.track.isNotEmpty ? widget.track.last : null);

  /// Smoothed polyline for [widget.track], cached by length. The recorder
  /// only appends, so equal lengths imply identical points — returning the
  /// cached list saves two O(n) smoothing passes + the raw LatLng
  /// conversion on every rebuild (~1 Hz from the position tween, higher
  /// during a hold-to-stop).
  List<LatLng> _smoothedTrackFor(List<Waypoint> track) {
    if (_cachedSmoothedTrack != null &&
        _cachedSmoothedForLength == track.length) {
      return _cachedSmoothedTrack!;
    }
    final raw = track.map((w) => LatLng(w.lat, w.lng)).toList();
    final smoothed = _smoothTrack(_smoothTrack(raw));
    _cachedSmoothedTrack = smoothed;
    _cachedSmoothedForLength = track.length;
    return smoothed;
  }

  /// Apply a 1-2-3-2-1 weighted moving average to the track so GPS jitter
  /// shows as a smoother line instead of a visible zig-zag. The first two
  /// and last two points are preserved unchanged. Display-only — the stored
  /// run keeps the raw waypoints.
  ///
  /// This reduces noise but cannot correct systematic offset from the road
  /// (i.e. when GPS reports you 5 m off the centreline). The real fix is
  /// backend map matching — see docs/roadmap.md.
  static List<LatLng> _smoothTrack(List<LatLng> points) {
    if (points.length < 5) return points;
    final out = List<LatLng>.from(points);
    for (int i = 2; i < points.length - 2; i++) {
      final a = points[i - 2];
      final b = points[i - 1];
      final c = points[i];
      final d = points[i + 1];
      final e = points[i + 2];
      out[i] = LatLng(
        (a.latitude + b.latitude * 2 + c.latitude * 3 + d.latitude * 2 + e.latitude) / 9,
        (a.longitude + b.longitude * 2 + c.longitude * 3 + d.longitude * 2 + e.longitude) / 9,
      );
    }
    return out;
  }

  /// Offset (in logical pixels) to shift the camera by so the dot sits in the
  /// centre of the visible area above [LiveRunMap.bottomPadding]. flutter_map's
  /// positive dy moves the [center] down the screen, so we pass a negative
  /// value to lift the dot above the overlay.
  Offset get _cameraOffset => Offset(0, -widget.bottomPadding / 2);

  void _moveCamera(LatLng target, {double? zoom}) {
    if (!_mapReady) return;
    final z = zoom ??
        (_mapController.camera.zoom < 17 ? 19.0 : _mapController.camera.zoom);
    _mapController.move(target, z, offset: _cameraOffset);
  }

  @override
  void didUpdateWidget(covariant LiveRunMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Detect a run reset: when the parent clears its track and current
    // position (discard / finish → new run), wipe the interpolated dot,
    // the tween endpoints, and the user-panned flag. Without this, the
    // next run's first fix would tween from the previous run's location
    // and the camera would stay parked where the last run ended.
    final resetDetected = oldWidget.track.isNotEmpty &&
        widget.track.isEmpty &&
        widget.currentPosition == null;
    if (resetDetected) {
      _positionController.stop();
      _animatedLatLng = null;
      _tweenStart = null;
      _tweenEnd = null;
      _userPanned = false;
      _cachedSmoothedTrack = null;
      _cachedSmoothedForLength = -1;
    }

    final pos = _latestPosition;
    if (pos == null) return;
    final target = LatLng(pos.lat, pos.lng);

    // First fix — snap, don't animate. Subsequent fixes tween from the
    // current interpolated position to the new target.
    if (_animatedLatLng == null) {
      _animatedLatLng = target;
      _tweenStart = target;
      _tweenEnd = target;
      if (widget.followRunner && !_userPanned) {
        _moveCamera(target);
      }
      return;
    }

    final prevEnd = _tweenEnd;
    if (prevEnd != null &&
        prevEnd.latitude == target.latitude &&
        prevEnd.longitude == target.longitude) {
      return; // same target, nothing to animate
    }

    _tweenStart = _animatedLatLng;
    _tweenEnd = target;
    _positionController
      ..stop()
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final trackLatLngs = _smoothedTrackFor(widget.track);
    final plannedLatLngs = widget.plannedRoute
            ?.map((w) => LatLng(w.lat, w.lng))
            .toList() ??
        [];
    final latest = _latestPosition;
    // Prefer the interpolated position when available so the dot glides
    // between GPS fixes instead of hopping.
    final currentLatLng = _animatedLatLng ??
        (latest != null ? LatLng(latest.lat, latest.lng) : null);

    // No GPS fix yet and no planned route — wait for GPS
    if (currentLatLng == null && plannedLatLngs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 12),
            Text('Waiting for GPS...'),
          ],
        ),
      );
    }

    final center = currentLatLng ?? plannedLatLngs.first;

    // When not following the runner (detail screen), fit the camera to the
    // full track so the user sees the whole run at a glance.
    final allPoints = trackLatLngs.isNotEmpty ? trackLatLngs : plannedLatLngs;
    final fitBounds = !widget.followRunner &&
        allPoints.length >= 2;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: fitBounds ? allPoints.first : center,
            initialZoom: fitBounds ? 14 : 19,
            // Cap gesture zoom to what the tile layer can actually cover
            // (with up-sampling above 19). Without this, users on the
            // finished-run screen pinch past the tile layer's display
            // ceiling and see only the polyline on a white background.
            minZoom: 3,
            maxZoom: 22,
            initialCameraFit: fitBounds
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(allPoints),
                    padding: const EdgeInsets.all(32),
                  )
                : null,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            onMapReady: () {
              _mapReady = true;
              // Apply the bottom-padding offset once we know the viewport.
              final pos = _animatedLatLng;
              if (pos != null && widget.followRunner && !_userPanned) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _moveCamera(pos));
              }
            },
            onPositionChanged: (pos, hasGesture) {
              if (hasGesture) setState(() => _userPanned = true);
            },
          ),
          children: [
            // Dark map tiles with HTTP cache. `maxNativeZoom` caps tile
            // fetches at 19 (MapTiler's ceiling for this style) while
            // `maxZoom` lets flutter_map keep displaying the layer at
            // gesture-zoom 20–22 by up-sampling the z=19 tiles. Without
            // the split the layer goes blank past 19 and the user sees
            // the polyline floating on a white background.
            TileLayer(
              urlTemplate: _tileUrl,
              userAgentPackageName: 'com.example.mobile_android',
              maxNativeZoom: 19,
              maxZoom: 22,
              tileProvider: CachedTileProvider(
                store: TileCache.store,
                maxStale: const Duration(days: 30),
                dio: TileCache.dio,
              ),
            ),

            // Planned route (underneath) — dashed-looking with lighter color
            if (plannedLatLngs.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: plannedLatLngs,
                    strokeWidth: 6,
                    color: const Color(0x80A78BFA), // Translucent violet
                  ),
                ],
              ),

            // Recorded track — Nike-Run-Club-style glowing line.
            // Three stacked layers give the line depth against the dark
            // map: a soft halo, a thin dark underline for contrast, and a
            // bright indigo gradient on top that fades from dim (oldest
            // point) to almost white at the current position.
            if (trackLatLngs.length >= 2) ...[
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: trackLatLngs,
                    strokeWidth: 18,
                    color: const Color(0xFF818CF8).withValues(alpha: 0.18),
                  ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: trackLatLngs,
                    strokeWidth: 10,
                    color: const Color(0xFF818CF8).withValues(alpha: 0.35),
                  ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: trackLatLngs,
                    strokeWidth: 6,
                    gradientColors: const [
                      Color(0xFF4F46E5),
                      Color(0xFF818CF8),
                      Color(0xFFC7D2FE),
                    ],
                    borderStrokeWidth: 2,
                    borderColor: const Color(0xFF1E1B4B),
                  ),
                ],
              ),
            ],

            // Current position marker — drawn from the interpolated tween
            // position so the dot glides smoothly between GPS fixes, with
            // the raw latest fix as a fallback on the very first frame.
            if (currentLatLng != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: currentLatLng,
                    width: 48,
                    height: 48,
                    child: _PulsingDot(animation: _pulseAnimation),
                  ),
                ],
              ),
          ],
        ),

        // Re-center button (appears after user pans)
        if (_userPanned && currentLatLng != null)
          Positioned(
            right: 12,
            bottom: widget.bottomPadding + 12,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: () {
                setState(() => _userPanned = false);
                _moveCamera(currentLatLng, zoom: _mapController.camera.zoom);
              },
              child: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }
}

/// Pulsing blue dot showing the runner's current position.
class _PulsingDot extends StatelessWidget {
  final Animation<double> animation;
  const _PulsingDot({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse ring
              Container(
                width: 48 * (0.5 + animation.value),
                height: 48 * (0.5 + animation.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF818CF8).withOpacity(animation.value),
                ),
              ),
              // Inner dot
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF818CF8),
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF818CF8).withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
