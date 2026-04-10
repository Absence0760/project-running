import 'package:core_models/core_models.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:latlong2/latlong.dart';

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

  // Shared in-memory tile cache. Survives map rebuilds and tab switches
  // within the same session.
  static final _tileCacheStore = MemCacheStore(maxSize: 200 * 1024 * 1024);
  static final _tileDio = Dio()
    ..interceptors.add(DioCacheInterceptor(
      options: CacheOptions(
        store: _tileCacheStore,
        maxStale: const Duration(days: 30),
        policy: CachePolicy.forceCache,
      ),
    ));
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
    final trackLatLngs = widget.track
        .map((w) => LatLng(w.lat, w.lng))
        .toList();
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

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 19,
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
            // Dark map tiles with HTTP cache
            TileLayer(
              urlTemplate: _tileUrl,
              userAgentPackageName: 'com.example.mobile_android',
              maxZoom: 19,
              tileProvider: CachedTileProvider(
                store: _tileCacheStore,
                maxStale: const Duration(days: 30),
                dio: _tileDio,
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

            // Recorded track (on top)
            if (trackLatLngs.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: trackLatLngs,
                    strokeWidth: 4.5,
                    color: const Color(0xFF818CF8), // Indigo
                  ),
                ],
              ),

            // Current position marker — drawn from the raw latest fix so it
            // refreshes between track-append events.
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
