import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Live map shown during a run, displaying the GPS track and current position.
///
/// Inspired by Nike Run Club: dark map, bright route line, pulsing blue dot.
class LiveRunMap extends StatefulWidget {
  /// The GPS track recorded so far.
  final List<Waypoint> track;

  /// Optional planned route to show underneath the live track.
  final List<Waypoint>? plannedRoute;

  /// Whether to auto-follow the runner's position.
  final bool followRunner;

  const LiveRunMap({
    super.key,
    required this.track,
    this.plannedRoute,
    this.followRunner = true,
  });

  @override
  State<LiveRunMap> createState() => _LiveRunMapState();
}

class _LiveRunMapState extends State<LiveRunMap> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _userPanned = false;
  bool _mapReady = false;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LiveRunMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_mapReady && widget.track.isNotEmpty && widget.followRunner && !_userPanned) {
      final pos = widget.track.last;
      final zoom = _mapController.camera.zoom < 17 ? 19.0 : _mapController.camera.zoom;
      _mapController.move(LatLng(pos.lat, pos.lng), zoom);
    }
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

    // No track yet and no planned route — wait for GPS
    if (trackLatLngs.isEmpty && plannedLatLngs.isEmpty) {
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

    final center = trackLatLngs.isNotEmpty
        ? trackLatLngs.last
        : plannedLatLngs.first;

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
            onMapReady: () => _mapReady = true,
            onPositionChanged: (pos, hasGesture) {
              if (hasGesture) _userPanned = true;
            },
          ),
          children: [
            // Dark map tiles
            TileLayer(
              urlTemplate: _tileUrl,
              userAgentPackageName: 'com.example.mobile_android',
              maxZoom: 19,
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

            // Current position marker
            if (trackLatLngs.isNotEmpty)
              MarkerLayer(
                markers: [
                  Marker(
                    point: trackLatLngs.last,
                    width: 48,
                    height: 48,
                    child: _PulsingDot(animation: _pulseAnimation),
                  ),
                ],
              ),
          ],
        ),

        // Re-center button (appears after user pans)
        if (_userPanned && widget.track.isNotEmpty)
          Positioned(
            right: 12,
            bottom: 12,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: () {
                setState(() => _userPanned = false);
                final pos = widget.track.last;
                _mapController.move(
                  LatLng(pos.lat, pos.lng),
                  _mapController.camera.zoom,
                );
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
