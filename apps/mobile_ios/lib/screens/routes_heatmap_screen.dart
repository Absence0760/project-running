import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Geographic heatmap of public route geometry. Mirrors the web
/// `/routes?tab=heatmap` surface (RouteHeatmap.svelte). Backed by the
/// `heatmap_points_in_bbox` PostGIS RPC, capped at 5k points per
/// fetch regardless of bbox size.
///
/// Rendering uses CircleLayer with low-opacity red dots — stacking
/// many points creates the heat-density visual without a full
/// gradient kernel (flutter_map has no native heatmap layer, but
/// MapLibre-style aggregation isn't necessary for this UX). A
/// 250 ms debounce on the move-end event keeps the RPC quiet
/// during pinch / drag.
class RoutesHeatmapScreen extends StatefulWidget {
  final ApiClient api;

  const RoutesHeatmapScreen({super.key, required this.api});

  @override
  State<RoutesHeatmapScreen> createState() => _RoutesHeatmapScreenState();
}

class _RoutesHeatmapScreenState extends State<RoutesHeatmapScreen> {
  final _mapController = MapController();
  List<HeatmapPoint> _points = const [];
  bool _loading = false;
  DateTime? _lastUpdated;
  Timer? _debounce;
  bool _mapReady = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!_mapReady) return;
    final bounds = _mapController.camera.visibleBounds;
    setState(() => _loading = true);
    try {
      final pts = await widget.api.fetchHeatmapPoints(
        minLng: bounds.west,
        minLat: bounds.south,
        maxLng: bounds.east,
        maxLat: bounds.north,
      );
      if (!mounted) return;
      setState(() {
        _points = pts;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      // L4 — the heatmap is a discover surface, not load-bearing.
      // A 5xx / network glitch must not crash the screen. The real
      // ApiClient already swallows + returns empty, but we belt-and-
      // braces here for tests + future contract changes.
      debugPrint('heatmap refresh failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heatmap'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                // London default — same as web; geo-locate is a follow-up.
                initialCenter: const LatLng(51.5074, -0.1276),
                initialZoom: 11,
                onMapReady: () {
                  _mapReady = true;
                  _refresh();
                },
                onPositionChanged: (pos, hasGesture) {
                  if (hasGesture) _scheduleRefresh();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.runonward.app',
                ),
                CircleLayer(
                  circles: [
                    for (final p in _points)
                      CircleMarker(
                        point: LatLng(p.lat, p.lng),
                        radius: 4,
                        // Low-opacity red — stacking creates the
                        // heat-density effect when many points
                        // overlap (a coarse approximation of a real
                        // heatmap kernel, but fine for the UX).
                        color: Colors.red.withValues(alpha: 0.18),
                        borderStrokeWidth: 0,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            color: theme.colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.local_fire_department_outlined,
                  color: theme.colorScheme.error,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Where people run — pan to refresh. ${_lastUpdated == null ? '' : 'Updated ${_fmtTime(_lastUpdated!)}.'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
