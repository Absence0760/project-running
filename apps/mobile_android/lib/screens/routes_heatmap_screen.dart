import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../geocoding.dart';
import '../widgets/top_banner.dart';

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
///
/// Navigation:
///   * AppBar search field — MapTiler geocoding, mirrors the route
///     builder's place search (debounce + dropdown).
///   * Locate-me FAB — Geolocator current-position fix; bounces the
///     map to the user's location at zoom 11 (city scale, matching
///     the heatmap's stride).
class RoutesHeatmapScreen extends StatefulWidget {
  final ApiClient api;
  /// Test seam — replays canned MapTiler responses without hitting
  /// the network. Production callers leave null.
  final GeocodingFetcher? geocodingFetcher;
  /// Test seam — stubs the platform-channel `Geolocator` call so the
  /// Locate FAB can be exercised in unit tests.
  final Future<Position> Function()? locateFn;

  const RoutesHeatmapScreen({
    super.key,
    required this.api,
    this.geocodingFetcher,
    this.locateFn,
  });

  @override
  State<RoutesHeatmapScreen> createState() => _RoutesHeatmapScreenState();
}

class _RoutesHeatmapScreenState extends State<RoutesHeatmapScreen> {
  final _mapController = MapController();
  final _searchCtl = TextEditingController();
  List<HeatmapPoint> _points = const [];
  bool _loading = false;
  Timer? _debounce;
  Timer? _searchDebounce;
  bool _mapReady = false;

  List<PlaceResult> _searchResults = const [];
  bool _searchOpen = false;

  String get _maptilerKey => dotenv.env['MAPTILER_KEY'] ?? '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtl.dispose();
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
      setState(() => _points = pts);
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

  Future<void> _locate() async {
    try {
      final pos = widget.locateFn != null
          ? await widget.locateFn!()
          : await _platformLocate();
      if (!mounted) return;
      _mapController.move(LatLng(pos.latitude, pos.longitude), 11);
      // Move doesn't fire `onPositionChanged` with `hasGesture: true`
      // (it's a programmatic move), so the heatmap doesn't auto-
      // refresh. Schedule one explicitly so the user's location
      // populates with their nearby routes.
      _scheduleRefresh();
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Location unavailable: $e');
    }
  }

  // Default locate path — kept separate so widget.locateFn can stub
  // the whole platform-channel call in tests.
  Future<Position> _platformLocate() async {
    if (kIsWeb) {
      throw UnsupportedError('Locate unavailable on web');
    }
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      final asked = await Geolocator.requestPermission();
      if (asked == LocationPermission.denied ||
          asked == LocationPermission.deniedForever) {
        throw StateError('Location permission denied');
      }
    } else if (perm == LocationPermission.deniedForever) {
      throw StateError('Location permission denied forever');
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _onSearchChanged(String query) async {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = const [];
        _searchOpen = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await searchPlaces(
        query,
        apiKey: _maptilerKey,
        fetcher: widget.geocodingFetcher,
      );
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searchOpen = results.isNotEmpty;
      });
    });
  }

  void _onSearchResultTap(PlaceResult result) {
    _mapController.move(LatLng(result.lat, result.lng), 12);
    FocusManager.instance.primaryFocus?.unfocus();
    _searchCtl.clear();
    setState(() {
      _searchResults = const [];
      _searchOpen = false;
    });
    // Programmatic move — same rationale as `_locate`.
    _scheduleRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtl,
          onChanged: _onSearchChanged,
          decoration: const InputDecoration(
            hintText: 'Search places…',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, size: 20),
          ),
          style: theme.textTheme.bodyLarge,
        ),
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'routes_heatmap_locate_fab',
        tooltip: 'Locate me',
        onPressed: _locate,
        child: const Icon(Icons.my_location),
      ),
      // No footer chrome — the search field + Locate FAB make the
      // affordances obvious, and the "Updated 12:34" timestamp was
      // redundant against the inline AppBar spinner.
      body: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    // London default — same as web; user can search
                    // or hit Locate-me to recentre.
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
                            // overlap (a coarse approximation of a
                            // real heatmap kernel, but fine for UX).
                            color: Colors.red.withValues(alpha: 0.18),
                            borderStrokeWidth: 0,
                          ),
                      ],
                    ),
                  ],
                ),
                // Search-results dropdown — stacked over the map so
                // it overlays without pushing the map content down.
                // Mirrors the route_builder pattern.
                if (_searchOpen && _searchResults.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Material(
                      elevation: 4,
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final r in _searchResults)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.place),
                              title: Text(
                                r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _onSearchResultTap(r),
                            ),
                        ],
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}
