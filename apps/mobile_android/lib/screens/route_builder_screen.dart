import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../local_route_store.dart';
import '../routing.dart';
import '../run_stats.dart' show haversineMetres;
import '../tile_cache.dart';
import '../widgets/top_banner.dart';

/// MVP click-to-place route builder (decisions roadmap Phase 3
/// "In-app route builder (free)" / followups #8).
///
/// What's wired:
/// - tap the map → append a waypoint, OSRM-snap it (foot or car), and
///   fetch the road-snapped polyline through every placed point
/// - mode toggle: foot (trail) / car (road) / straight (no OSRM)
/// - undo last waypoint
/// - clear all
/// - distance accumulator from OSRM (or great-circle in straight mode)
/// - save dialog: name + public toggle → ApiClient.saveRoute +
///   LocalRouteStore.save, then pops with the new route
///
/// Deferred (followups #8 remaining bullets — see docs/followups.md):
/// - draggable marker reshape
/// - elevation profile preview while drawing
/// - snap-to-start pulsing marker to close loops
/// - place-name search via MapTiler geocoding
/// - overlap detection (purple out-and-back sections)
/// - geolocate auto-center
///
/// Pure-logic helpers (`routing.dart`) are unit-tested separately.
/// This screen is the integration glue.
class RouteBuilderScreen extends StatefulWidget {
  final ApiClient apiClient;
  final LocalRouteStore routeStore;
  final LatLng? initialCenter;

  /// Test-only OSRM fetcher seam — pass a stubbed [OsrmFetcher] in
  /// widget tests so the screen doesn't hit the network. Production
  /// passes null and the routing module uses its dart:io default.
  final OsrmFetcher? osrmFetcher;

  /// Test-only seam for the cloud save call. Defaults to
  /// `apiClient.saveRoute`. Widget tests pass a no-op or recorder.
  final Future<void> Function(cm.Route route)? saveRouteFn;

  const RouteBuilderScreen({
    super.key,
    required this.apiClient,
    required this.routeStore,
    this.initialCenter,
    this.osrmFetcher,
    this.saveRouteFn,
  });

  @override
  State<RouteBuilderScreen> createState() => _RouteBuilderScreenState();
}

class _RouteBuilderScreenState extends State<RouteBuilderScreen> {
  static const _kDefaultCenter = LatLng(51.5074, -0.1278); // London
  final MapController _map = MapController();

  /// User-placed waypoints (OSRM-snapped). Drives marker layer + the
  /// next OSRM call.
  final List<cm.Waypoint> _waypoints = [];

  /// Fully-resolved polyline between waypoints, from OSRM in road /
  /// trail mode or interpolated straight in straight mode.
  List<cm.Waypoint> _polyline = const [];

  double _distanceM = 0;
  RouteBuilderMode _mode = RouteBuilderMode.trail;
  bool _routing = false;
  bool _saving = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  String get _tileUrl {
    final key = dotenv.env['MAPTILER_KEY'] ?? '';
    if (key.isEmpty) {
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    return 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$key';
  }

  Future<void> _onMapTap(TapPosition _, LatLng latLng) async {
    if (_routing || _saving) return;
    final next = cm.Waypoint(lat: latLng.latitude, lng: latLng.longitude);

    // Straight mode skips OSRM — just append + interpolate.
    if (_mode == RouteBuilderMode.straight) {
      setState(() {
        _waypoints.add(next);
        _polyline = List<cm.Waypoint>.from(_waypoints);
        _distanceM = straightLineDistance(_waypoints);
      });
      return;
    }

    setState(() => _routing = true);
    final profile =
        _mode == RouteBuilderMode.road ? OsrmProfile.car : OsrmProfile.foot;
    try {
      final snapped = await snapToRoad(
        next,
        profile: profile,
        fetcher: widget.osrmFetcher,
      );
      final newWaypoints = [..._waypoints, snapped];
      if (newWaypoints.length < 2) {
        if (mounted) {
          setState(() {
            _waypoints
              ..clear()
              ..addAll(newWaypoints);
            _polyline = const [];
            _distanceM = 0;
            _routing = false;
          });
        }
        return;
      }
      final routed = await fetchRouteThrough(
        newWaypoints,
        profile: profile,
        fetcher: widget.osrmFetcher,
      );
      if (!mounted) return;
      setState(() {
        _waypoints
          ..clear()
          ..addAll(newWaypoints);
        _polyline = routed.coordinates;
        _distanceM = routed.distanceMetres;
        _routing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _routing = false);
      showTopBanner(context, 'Routing failed: $e');
    }
  }

  Future<void> _undo() async {
    if (_routing || _saving || _waypoints.isEmpty) return;
    final next = _waypoints.sublist(0, _waypoints.length - 1);
    if (next.length < 2 || _mode == RouteBuilderMode.straight) {
      setState(() {
        _waypoints
          ..clear()
          ..addAll(next);
        _polyline = _mode == RouteBuilderMode.straight
            ? List<cm.Waypoint>.from(next)
            : const [];
        _distanceM = _mode == RouteBuilderMode.straight
            ? straightLineDistance(next)
            : 0;
      });
      return;
    }
    setState(() => _routing = true);
    final profile =
        _mode == RouteBuilderMode.road ? OsrmProfile.car : OsrmProfile.foot;
    try {
      final routed = await fetchRouteThrough(
        next,
        profile: profile,
        fetcher: widget.osrmFetcher,
      );
      if (!mounted) return;
      setState(() {
        _waypoints
          ..clear()
          ..addAll(next);
        _polyline = routed.coordinates;
        _distanceM = routed.distanceMetres;
        _routing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _routing = false);
      showTopBanner(context, 'Undo failed: $e');
    }
  }

  void _clear() {
    if (_routing || _saving) return;
    setState(() {
      _waypoints.clear();
      _polyline = const [];
      _distanceM = 0;
    });
  }

  Future<void> _save() async {
    if (_polyline.length < 2) {
      showTopBanner(context, 'Place at least two waypoints first.');
      return;
    }
    final result = await showDialog<_SaveDialogResult>(
      context: context,
      builder: (_) => const _SaveRouteDialog(),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    final route = cm.Route(
      id: const Uuid().v4(),
      name: result.name,
      waypoints: _polyline,
      distanceMetres: _distanceM,
      isPublic: result.isPublic,
      surface: _surfaceFor(_mode),
    );
    try {
      await (widget.saveRouteFn ?? widget.apiClient.saveRoute)(route);
      await widget.routeStore.save(route);
      if (!mounted) return;
      Navigator.of(context).pop<cm.Route>(route);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTopBanner(context, 'Save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waypointLatLngs = [
      for (final w in _waypoints) LatLng(w.lat, w.lng),
    ];
    final polylineLatLngs = [
      for (final w in _polyline) LatLng(w.lat, w.lng),
    ];
    final center = widget.initialCenter ?? _kDefaultCenter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New route'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            onPressed: _waypoints.isEmpty || _routing || _saving
                ? null
                : _undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: _waypoints.isEmpty || _routing || _saving
                ? null
                : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
          TextButton(
            onPressed: _polyline.length < 2 || _routing || _saving
                ? null
                : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14,
              minZoom: 3,
              maxZoom: 22,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: _tileUrl,
                userAgentPackageName: 'com.runonward.app',
                maxNativeZoom: 19,
                maxZoom: 22,
                tileProvider: CachedTileProvider(
                  store: TileCache.store,
                  maxStale: const Duration(days: 30),
                  dio: TileCache.dio,
                ),
              ),
              if (polylineLatLngs.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: polylineLatLngs,
                      strokeWidth: 5,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              if (waypointLatLngs.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < waypointLatLngs.length; i++)
                      Marker(
                        point: waypointLatLngs[i],
                        width: 24,
                        height: 24,
                        child: _WaypointPin(
                          index: i,
                          isStart: i == 0,
                          isEnd: i == waypointLatLngs.length - 1 && i > 0,
                        ),
                      ),
                  ],
                ),
            ],
          ),
          // Top status pill — distance + routing/saving spinner.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _StatusPill(
              distanceM: _distanceM,
              routing: _routing,
              saving: _saving,
              waypointCount: _waypoints.length,
            ),
          ),
          // Bottom mode toggle.
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _ModeToggle(
              mode: _mode,
              onChanged: _routing || _saving
                  ? null
                  : (m) => setState(() => _mode = m),
            ),
          ),
        ],
      ),
    );
  }
}

/// Available routing profiles surfaced to the user. Maps to
/// [OsrmProfile] for road/trail and bypasses OSRM for straight.
enum RouteBuilderMode { trail, road, straight }

String _surfaceFor(RouteBuilderMode mode) {
  return switch (mode) {
    RouteBuilderMode.trail => 'trail',
    RouteBuilderMode.road => 'road',
    RouteBuilderMode.straight => 'mixed',
  };
}

/// Great-circle distance summation between consecutive waypoints. Used
/// in straight-line mode (OSRM bypass). Re-exported from `run_stats`
/// so the math lives in one place.
@visibleForTesting
double straightLineDistance(List<cm.Waypoint> points) {
  if (points.length < 2) return 0;
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += haversineMetres(
      points[i - 1].lat,
      points[i - 1].lng,
      points[i].lat,
      points[i].lng,
    );
  }
  return total;
}

// Smaller pill widget showing distance + state.
class _StatusPill extends StatelessWidget {
  final double distanceM;
  final bool routing;
  final bool saving;
  final int waypointCount;

  const _StatusPill({
    required this.distanceM,
    required this.routing,
    required this.saving,
    required this.waypointCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = waypointCount == 0
        ? 'Tap the map to place waypoints'
        : '${(distanceM / 1000).toStringAsFixed(2)} km · '
            '$waypointCount ${waypointCount == 1 ? "point" : "points"}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          if (routing || saving) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final RouteBuilderMode mode;
  final ValueChanged<RouteBuilderMode>? onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor),
      ),
      child: SegmentedButton<RouteBuilderMode>(
        segments: const [
          ButtonSegment(
            value: RouteBuilderMode.trail,
            label: Text('Trail'),
            icon: Icon(Icons.terrain),
          ),
          ButtonSegment(
            value: RouteBuilderMode.road,
            label: Text('Road'),
            icon: Icon(Icons.directions_car),
          ),
          ButtonSegment(
            value: RouteBuilderMode.straight,
            label: Text('Straight'),
            icon: Icon(Icons.straighten),
          ),
        ],
        selected: {mode},
        onSelectionChanged:
            onChanged == null ? null : (s) => onChanged!(s.first),
      ),
    );
  }
}

class _WaypointPin extends StatelessWidget {
  final int index;
  final bool isStart;
  final bool isEnd;

  const _WaypointPin({
    required this.index,
    required this.isStart,
    required this.isEnd,
  });

  @override
  Widget build(BuildContext context) {
    final color = isStart
        ? Colors.green
        : isEnd
            ? Colors.red
            : Colors.blueGrey;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '${index + 1}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _SaveDialogResult {
  final String name;
  final bool isPublic;
  const _SaveDialogResult({required this.name, required this.isPublic});
}

class _SaveRouteDialog extends StatefulWidget {
  const _SaveRouteDialog();
  @override
  State<_SaveRouteDialog> createState() => _SaveRouteDialogState();
}

class _SaveRouteDialogState extends State<_SaveRouteDialog> {
  final _name = TextEditingController();
  bool _isPublic = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save route'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. River loop',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Make public'),
            subtitle: const Text('Others can find it on Explore'),
            value: _isPublic,
            onChanged: (v) => setState(() => _isPublic = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final trimmed = _name.text.trim();
            if (trimmed.isEmpty) return;
            Navigator.of(context).pop(_SaveDialogResult(
              name: trimmed,
              isPublic: _isPublic,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
