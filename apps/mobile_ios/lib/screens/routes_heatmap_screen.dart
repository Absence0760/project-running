import 'dart:async';
import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../geocoding.dart';
import '../tile_cache.dart';
import '../widgets/live_run_map.dart' show currentTileUrl;
import '../widgets/top_banner.dart';
import 'public_route_screen.dart';

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
  /// Test seam — lets widget tests boot the screen above the routes-
  /// overlay zoom threshold (default 12) without needing to drive the
  /// MapController manually. Production callers leave null and get
  /// the city-scale default of 11.
  final double? initialZoom;

  const RoutesHeatmapScreen({
    super.key,
    required this.api,
    this.geocodingFetcher,
    this.locateFn,
    this.initialZoom,
  });

  @override
  State<RoutesHeatmapScreen> createState() => _RoutesHeatmapScreenState();
}

class _RoutesHeatmapScreenState extends State<RoutesHeatmapScreen> {
  final _mapController = MapController();
  final _searchCtl = TextEditingController();
  List<cm.HeatmapPoint> _points = const [];
  /// Public routes that intersect (or are near) the current viewport.
  /// Rendered as tappable polylines once the user zooms in past the
  /// density-only stage. Mirrors the web RouteHeatmap's clickable
  /// routes layer — tap a line → /routes/[id]. Empty when zoom is
  /// below threshold so the heatmap stays the dominant signal.
  List<cm.Route> _nearbyRoutes = const [];
  bool _loading = false;
  Timer? _debounce;
  Timer? _searchDebounce;
  bool _mapReady = false;

  /// Minimum zoom to overlay individual public routes. Below this the
  /// heatmap density is the honest signal — too many lines at city /
  /// region scale is noise. Mirrors ROUTES_OVERLAY_MIN_ZOOM on web.
  static const double _routesOverlayMinZoom = 12.0;

  /// Pixel-radius for tap-on-polyline hit testing. A finger covers
  /// roughly 24-32 px; 28 keeps clicks responsive on small screens
  /// while still requiring the user to land near a line.
  static const double _tapHitRadiusPx = 28.0;

  List<PlaceResult> _searchResults = const [];
  bool _searchOpen = false;

  /// Last known user position, rendered as a blue dot + accuracy halo
  /// on the map. Populated on mount (best-effort, silent on permission
  /// denial) and refreshed on every Locate FAB tap. Mirrors the
  /// `GeolocateControl` MapLibre primitive used by the web heatmap.
  LatLng? _userLatLng;

  String get _maptilerKey => dotenv.env['MAPTILER_KEY'] ?? '';

  @override
  void initState() {
    super.initState();
    // Fire-and-forget so the user sees a blue dot the moment they
    // land on the heatmap (when permission is already granted).
    unawaited(_backgroundLocate());
  }

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
    // Refresh the tappable routes overlay in parallel — separate try
    // block so a heatmap-points failure doesn't blank the polylines
    // and vice versa.
    await _refreshRoutes();
  }

  /// Fetch + render tappable public-route polylines for the current
  /// viewport centre. Mirrors `refreshRoutes()` on RouteHeatmap.svelte:
  /// hidden below `_routesOverlayMinZoom`; uses the existing
  /// `nearby_routes` RPC (no new migration); cap radius at 25 km so a
  /// fully zoomed-out view doesn't fetch everything.
  Future<void> _refreshRoutes() async {
    if (!_mapReady || !mounted) return;
    if (_mapController.camera.zoom < _routesOverlayMinZoom) {
      if (_nearbyRoutes.isNotEmpty) {
        setState(() => _nearbyRoutes = const []);
      }
      return;
    }
    final centre = _mapController.camera.center;
    final bounds = _mapController.camera.visibleBounds;
    final halfDiag = _haversineM(
      bounds.north,
      bounds.west,
      centre.latitude,
      centre.longitude,
    );
    final radiusM = halfDiag.clamp(1000.0, 25000.0);
    try {
      final routes = await widget.api.nearbyPublicRoutes(
        lat: centre.latitude,
        lng: centre.longitude,
        radiusM: radiusM,
        limit: 50,
      );
      if (!mounted) return;
      setState(() => _nearbyRoutes =
          routes.where((r) => r.waypoints.length >= 2).toList());
    } catch (e) {
      debugPrint('heatmap routes refresh failed: $e');
    }
  }

  /// Map-tap handler. When zoomed in enough to show route lines, this
  /// hit-tests the tap against every nearby route's polyline and
  /// navigates to the closest one within `_tapHitRadiusPx`. Outside
  /// the threshold the tap is a no-op (the heatmap underneath has no
  /// click semantics — density isn't clickable).
  void _onMapTap(TapPosition tapPos, LatLng latlng) {
    if (_nearbyRoutes.isEmpty) return;
    final camera = _mapController.camera;
    // Convert tap to screen-space and compare to each waypoint in
    // screen-space — this gives a uniform hit radius regardless of
    // latitude, which haversine alone doesn't (1 m of lat ≠ 1 m of
    // lng at high latitudes).
    final tapPx = camera.latLngToScreenOffset(latlng);
    String? bestId;
    double bestDistPx = _tapHitRadiusPx;
    for (final r in _nearbyRoutes) {
      for (final w in r.waypoints) {
        final px = camera.latLngToScreenOffset(LatLng(w.lat, w.lng));
        final dx = px.dx - tapPx.dx;
        final dy = px.dy - tapPx.dy;
        final dist = (dx * dx + dy * dy).abs();
        // Compare squared distances to skip sqrt in the hot loop.
        final threshold = bestDistPx * bestDistPx;
        if (dist < threshold) {
          bestDistPx = dist <= 0 ? 0 : (dist == 0 ? 0 : dist).clamp(0, double.infinity).toDouble();
          // Track the actual pixel distance for the next comparison.
          bestDistPx = _sqrtSafe(dist);
          bestId = r.id;
        }
      }
    }
    if (bestId != null) {
      final id = bestId;
      // Defer the push so the GestureDetector finishes processing
      // before the screen changes — avoids "setState after dispose"
      // and keeps the tap ripple animation clean.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PublicRouteScreen(api: widget.api, routeId: id),
          ),
        );
      });
    }
  }

  static double _sqrtSafe(double v) => v <= 0 ? 0 : math.sqrt(v);

  static double _haversineM(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371000.0;
    double toRad(double d) => d * math.pi / 180.0;
    final dLat = toRad(lat2 - lat1);
    final dLng = toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
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
      final ll = LatLng(pos.latitude, pos.longitude);
      // Zoom 14 = neighbourhood level (~2 km across) — close enough to
      // see local routes / streets, far enough to keep some context.
      // Pre-fix the FAB landed at zoom 11 (city scale ~30 km) which
      // the user flagged as "doesn\'t zoom in enough".
      _mapController.move(ll, 14);
      setState(() => _userLatLng = ll);
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

  /// Best-effort background fix on mount so the user sees a dot
  /// immediately on first paint (when permission is already granted).
  /// Silent on denial — Locate FAB is the explicit-permission path.
  Future<void> _backgroundLocate() async {
    if (kIsWeb) return;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return; // Don't prompt silently — let the FAB do it.
      }
      final pos = await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() => _userLatLng = LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      // Silent — the FAB is the user-initiated retry.
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
                    initialZoom: widget.initialZoom ?? 11,
                    onMapReady: () {
                      _mapReady = true;
                      _refresh();
                    },
                    onPositionChanged: (pos, hasGesture) {
                      if (hasGesture) _scheduleRefresh();
                    },
                    onTap: _onMapTap,
                  ),
                  children: [
                    TileLayer(
                      // Honours TILE_URL_TEMPLATE → MAPTILER_KEY → OSM
                      // in that order, matching every other map surface
                      // in the app. Pre-May-2026 this was hardcoded to
                      // OSM, which made the heatmap the only mobile map
                      // that worked on a Protomaps-only dev setup but
                      // also burned OSM\'s tile quota for every dev
                      // session in production builds with a configured
                      // MapTiler key.
                      urlTemplate: currentTileUrl(),
                      userAgentPackageName: 'com.threkir.app',
                      // Disk-backed tile cache shared with every other
                      // map surface. Without it, panning the heatmap
                      // re-downloads tiles every session AND flutter_map
                      // logs a "Using fallback freshness age" warning
                      // for every tile (tileserver-gl doesn\'t send
                      // Cache-Control headers, so flutter_map\'s
                      // internal cache layer kicks in with its 7-day
                      // default). 30-day staleness keeps the basemap
                      // around through a normal usage cycle.
                      tileProvider: CachedTileProvider(
                        store: TileCache.store,
                        maxStale: const Duration(days: 30),
                        dio: TileCache.dio,
                      ),
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
                    // Tappable public-route polylines. Visible only
                    // above the overlay zoom threshold; tap → open
                    // the route detail. Two-layer rendering (dark
                    // casing + cyan body) matches the web
                    // RouteHeatmap.svelte styling so the visual
                    // language stays consistent across surfaces.
                    if (_nearbyRoutes.isNotEmpty)
                      PolylineLayer(
                        key: const ValueKey('heatmap-routes'),
                        polylines: [
                          for (final r in _nearbyRoutes)
                            Polyline(
                              points: [
                                for (final w in r.waypoints)
                                  LatLng(w.lat, w.lng),
                              ],
                              strokeWidth: 6,
                              color: const Color(0x661e293b),
                            ),
                          for (final r in _nearbyRoutes)
                            Polyline(
                              points: [
                                for (final w in r.waypoints)
                                  LatLng(w.lat, w.lng),
                              ],
                              strokeWidth: 3,
                              color: const Color(0xFF22d3ee),
                            ),
                        ],
                      ),
                    // User-position dot — blue with a white halo,
                    // mirrors the styling of MapLibre's built-in
                    // `GeolocateControl` on the web heatmap. Drawn
                    // last so it sits above the heatmap + route
                    // overlays. Hidden until the background-locate
                    // (or the Locate FAB) populates `_userLatLng`.
                    if (_userLatLng != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _userLatLng!,
                            width: 22,
                            height: 22,
                            child: const _UserLocationDot(),
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

/// Blue dot with a white halo + outline — the mobile twin of
/// MapLibre's `GeolocateControl` user-position marker. Two
/// concentric Containers via DecoratedBox so the halo reads cleanly
/// on both light and dark basemaps.
class _UserLocationDot extends StatelessWidget {
  const _UserLocationDot();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.6),
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1A73E8),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
