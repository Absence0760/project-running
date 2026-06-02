import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../distance_bands.dart';
import '../geocoding.dart';
import '../heatmap_clustering.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart' show formatDistanceForPref;
import '../tile_cache.dart';
import '../widgets/live_run_map.dart' show currentTileUrl;
import '../widgets/top_banner.dart';
import 'public_route_screen.dart';

/// Route-discovery browser. Mobile mirror of the web RouteHeatmap.svelte
/// surface (web keeps its desktop sidebar — this is a deliberate
/// mobile-only layout): a heat-density background plus discoverable
/// route pins (clustered) you can filter by lens + race distance. The
/// map stays full-bleed; a floating "N routes" pill opens the results
/// list as a dismissible modal sheet, and tapping a pin or a list row
/// draws just that route's line + shows a compact card (the touch-device
/// equivalent of web's hover preview). Nothing permanently covers the
/// map. Backed by `heatmap_points_in_bbox`, `discoverable_routes_in_bbox`,
/// and `clubs_in_bbox`.
///
/// Navigation:
///   * AppBar search field — MapTiler geocoding place search.
///   * AppBar Filters button — lens (popular/friends/featured/hidden
///     gems) + multi-select race-distance bands (5K/10K/Half/Marathon/
///     Ultra), with an active-filter badge.
///   * Locate-me FAB — Geolocator current-position fix at zoom 14. The
///     map also auto-centres on the user's location once on open (until
///     they pan), rather than sitting at the neutral London default.
class RoutesHeatmapScreen extends StatefulWidget {
  final ApiClient api;

  /// Test seam — replays canned MapTiler responses without hitting
  /// the network. Production callers leave null.
  final GeocodingFetcher? geocodingFetcher;

  /// Test seam — stubs the platform-channel `Geolocator` call so the
  /// Locate FAB can be exercised in unit tests.
  final Future<Position> Function()? locateFn;

  /// Test seam — supplies the one-shot startup location fix so the
  /// auto-centre-on-open path can be exercised without the platform
  /// Geolocator. Production callers leave null.
  final Future<Position?> Function()? backgroundLocateFn;

  /// Test seam — boots the screen at a specific zoom without driving the
  /// MapController. Production callers leave null (city-scale default).
  final double? initialZoom;

  const RoutesHeatmapScreen({
    super.key,
    required this.api,
    this.geocodingFetcher,
    this.locateFn,
    this.backgroundLocateFn,
    this.initialZoom,
  });

  @override
  State<RoutesHeatmapScreen> createState() => _RoutesHeatmapScreenState();
}

class _RoutesHeatmapScreenState extends State<RoutesHeatmapScreen> {
  final _mapController = MapController();
  final _searchCtl = TextEditingController();

  List<cm.HeatmapPoint> _points = const [];
  List<cm.DiscoverableRoutePin> _pins = const [];
  List<cm.ClubPin> _clubs = const [];

  /// Discovery lens: 'popular' (default) | 'friends' | 'featured' |
  /// 'hidden_gems'. Mirrors the web DiscoverFilter union.
  String _filter = 'popular';

  /// Selected race-distance band keys (multi-select). Empty = no filter.
  final Set<String> _bands = <String>{};

  /// The density heat layer is OFF by default: it traces each route's
  /// path and reads as "the route is already shown", fighting the
  /// tap-to-preview model. Opt in from the Filters sheet.
  bool _showHeat = false;

  /// The route currently previewed (tapped from its pin or its list row).
  /// Its line is drawn on the map; the bottom sheet shows its card.
  String? _selectedRouteId;
  cm.DiscoverableRoutePin? _selectedPin;
  List<LatLng>? _selectedLine;

  /// id → polyline cache so re-selecting a route never refetches.
  final Map<String, List<LatLng>> _geomCache = <String, List<LatLng>>{};

  /// Routes the user has pinned ("keep on map") — their lines stay drawn
  /// (in violet) across pan / filter changes until unpinned. Only pinned
  /// routes are fetched (reusing _geomCache), so this stays cheap.
  final Set<String> _pinnedIds = <String>{};

  bool _loading = false;
  Timer? _debounce;
  Timer? _searchDebounce;
  bool _mapReady = false;

  /// True once the user has panned/zoomed by hand. Suppresses the
  /// one-shot auto-centre on the first location fix so we never yank the
  /// camera out from under them.
  bool _userMovedMap = false;

  /// Pixel radius for merging pins into a cluster at the current zoom.
  static const double _clusterRadiusPx = 50.0;

  /// Pixel radius for tap-on-pin hit testing.
  static const double _tapHitRadiusPx = 34.0;

  static const List<String> _lenses = [
    'popular',
    'friends',
    'featured',
    'hidden_gems',
  ];

  String _lensLabel(String key) {
    final l10n = AppLocalizations.of(context);
    switch (key) {
      case 'friends':
        return l10n.heatmapLensFriends;
      case 'featured':
        return l10n.heatmapLensFeatured;
      case 'hidden_gems':
        return l10n.heatmapLensHiddenGems;
      case 'popular':
      default:
        return l10n.heatmapLensPopular;
    }
  }

  List<PlaceResult> _searchResults = const [];
  bool _searchOpen = false;

  LatLng? _userLatLng;

  String get _maptilerKey => dotenv.env['MAPTILER_KEY'] ?? '';

  int get _activeFilterCount =>
      (_filter != 'popular' ? 1 : 0) + _bands.length;

  String get _filterLabel => _lensLabel(_filter);

  @override
  void initState() {
    super.initState();
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
      final ranges = bandsToRanges(_bands.toList());
      // Only pay for heat points when the layer is on (off by default).
      final heat = _showHeat
          ? await widget.api.fetchHeatmapPoints(
              minLng: bounds.west,
              minLat: bounds.south,
              maxLng: bounds.east,
              maxLat: bounds.north,
            )
          : const <cm.HeatmapPoint>[];
      final pins = await widget.api.fetchDiscoverableRoutesInBbox(
        minLng: bounds.west,
        minLat: bounds.south,
        maxLng: bounds.east,
        maxLat: bounds.north,
        filter: _filter,
        distMin: ranges.min,
        distMax: ranges.max,
      );
      final clubs = await widget.api.fetchClubsInBbox(
        minLng: bounds.west,
        minLat: bounds.south,
        maxLng: bounds.east,
        maxLat: bounds.north,
      );
      if (!mounted) return;
      setState(() {
        _points = heat;
        _pins = pins;
        _clubs = clubs;
      });
    } catch (e) {
      // L4 — discovery is not load-bearing. The real ApiClient already
      // swallows + returns empty; belt-and-braces here for tests.
      debugPrint('heatmap refresh failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<PinCluster<cm.DiscoverableRoutePin>> _buildClusters(MapCamera camera) {
    return clusterPins<cm.DiscoverableRoutePin>(
      items: _pins,
      latOf: (p) => p.lat,
      lngOf: (p) => p.lng,
      project: (lat, lng) {
        final o = camera.latLngToScreenOffset(LatLng(lat, lng));
        return (x: o.dx, y: o.dy);
      },
      radiusPx: _clusterRadiusPx,
    );
  }

  /// Map-tap handler. Hit-tests the tap against the rendered clusters:
  /// a cluster zooms in to break apart; a single pin previews its route.
  /// A tap on empty map clears the current preview.
  void _onMapTap(TapPosition tapPos, LatLng latlng) {
    if (!_mapReady) return;
    final camera = _mapController.camera;
    final tapPx = camera.latLngToScreenOffset(latlng);
    PinCluster<cm.DiscoverableRoutePin>? hit;
    var best = _tapHitRadiusPx;
    for (final c in _buildClusters(camera)) {
      final px = camera.latLngToScreenOffset(LatLng(c.lat, c.lng));
      final d = (px - tapPx).distance;
      if (d < best) {
        best = d;
        hit = c;
      }
    }
    if (hit == null) {
      _clearSelection();
      return;
    }
    if (hit.isCluster) {
      // Overlapping pins (routes that share a start can't be zoomed
      // apart) — list them so the user picks, instead of zooming uselessly.
      _showClusterSheet(hit.items);
    } else {
      _selectRoute(hit.first, pan: false);
    }
  }

  Future<void> _showClusterSheet(List<cm.DiscoverableRoutePin> routes) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                AppLocalizations.of(ctx).heatmapRoutesStartHere(routes.length),
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
            ),
            for (final p in routes)
              ListTile(
                dense: true,
                leading: p.featured
                    ? const Icon(Icons.star, color: Color(0xFFFACC15), size: 20)
                    : const Icon(Icons.place_outlined, size: 20),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Row(
                  children: [
                    if (bandForDistance(p.distanceM) != null)
                      _bandBadge(bandForDistance(p.distanceM)!.label),
                    Flexible(
                      child: Text(
                        <String>[
                          formatDistanceForPref(p.distanceM),
                          if (p.surface.isNotEmpty) p.surface,
                          if (p.runCount > 0)
                            '${p.runCount} run${p.runCount == 1 ? '' : 's'}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _selectRoute(p, pan: true);
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _selectRoute(
    cm.DiscoverableRoutePin pin, {
    required bool pan,
  }) async {
    setState(() {
      _selectedRouteId = pin.id;
      _selectedPin = pin;
    });
    if (pan) {
      final z = _mapController.camera.zoom;
      _mapController.move(LatLng(pin.lat, pin.lng), z < 13 ? 13 : z);
    }
    await _drawSelectedLine(pin.id);
  }

  /// Fetch + cache a route's polyline if not already cached. Returns null
  /// when unavailable. Shared by the hover/tap preview and pinning.
  Future<List<LatLng>?> _ensureGeom(String id) async {
    final cached = _geomCache[id];
    if (cached != null) return cached;
    try {
      final res = await widget.api.fetchRouteById(id);
      final route = res.route;
      if (route == null || route.waypoints.length < 2) return null;
      final line = [for (final w in route.waypoints) LatLng(w.lat, w.lng)];
      _geomCache[id] = line;
      return line;
    } catch (e) {
      debugPrint('route geom fetch failed: $e');
      return null;
    }
  }

  Future<void> _drawSelectedLine(String id) async {
    final line = await _ensureGeom(id);
    // The selection may have changed while the fetch was in flight.
    if (line == null || _selectedRouteId != id || !mounted) return;
    setState(() => _selectedLine = line);
  }

  Future<void> _togglePin(cm.DiscoverableRoutePin p) async {
    if (_pinnedIds.contains(p.id)) {
      setState(() => _pinnedIds.remove(p.id));
      return;
    }
    final line = await _ensureGeom(p.id);
    if (line == null || !mounted) return;
    setState(() => _pinnedIds.add(p.id));
  }

  void _clearPinned() {
    if (_pinnedIds.isEmpty) return;
    setState(_pinnedIds.clear);
  }

  void _clearSelection() {
    if (_selectedRouteId == null) return;
    setState(() {
      _selectedRouteId = null;
      _selectedPin = null;
      _selectedLine = null;
    });
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilterGroupLabel(AppLocalizations.of(context).heatmapLensShow),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final l in _lenses)
                        FilterChip(
                          label: Text(_lensLabel(l)),
                          selected: _filter == l,
                          onSelected: (_) {
                            setState(() => _filter = l);
                            setSheet(() {});
                            _refresh();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _FilterGroupLabel(
                      AppLocalizations.of(context).heatmapLensDistance),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in distanceBands)
                        FilterChip(
                          label: Text(b.label),
                          selected: _bands.contains(b.key),
                          onSelected: (_) {
                            setState(() {
                              if (!_bands.add(b.key)) _bands.remove(b.key);
                            });
                            setSheet(() {});
                            _refresh();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _FilterGroupLabel(AppLocalizations.of(context).heatmapLensMap),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: Text(
                            AppLocalizations.of(context).heatmapHeatDensity),
                        selected: _showHeat,
                        onSelected: (_) {
                          setState(() => _showHeat = !_showHeat);
                          setSheet(() {});
                          _refresh();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (_activeFilterCount > 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _filter = 'popular';
                            _bands.clear();
                          });
                          setSheet(() {});
                          _refresh();
                        },
                        child: Text(
                            AppLocalizations.of(context).heatmapResetFilters),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
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
      _mapController.move(ll, 14);
      setState(() => _userLatLng = ll);
      _scheduleRefresh();
    } catch (e) {
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).heatmapLocationUnavailable('$e'));
    }
  }

  /// One-shot location fix on open: centres the map on the user instead
  /// of leaving it at the neutral London default. Sets the location dot
  /// and, if the user hasn't already panned, moves the camera there.
  Future<void> _backgroundLocate() async {
    if (widget.backgroundLocateFn != null) {
      try {
        final pos = await widget.backgroundLocateFn!();
        if (pos == null || !mounted) return;
        setState(() => _userLatLng = LatLng(pos.latitude, pos.longitude));
        _maybeAutoCenter();
      } catch (_) {
        // Silent — the FAB is the user-initiated retry.
      }
      return;
    }
    if (kIsWeb) return;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      // Fast path: a cached fix centres the map instantly so it doesn't
      // open on London and then jump once the fresh fix lands.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() => _userLatLng = LatLng(last.latitude, last.longitude));
        _maybeAutoCenter();
      }
      final pos = await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() => _userLatLng = LatLng(pos.latitude, pos.longitude));
      _maybeAutoCenter();
    } catch (_) {
      // Silent — the FAB is the user-initiated retry.
    }
  }

  /// Centre the map on the known user location (zoom 14, matching the
  /// Locate FAB) and refetch discovery there — but only on open, before
  /// the user has taken control of the camera. Returns whether it moved.
  bool _maybeAutoCenter() {
    if (!_mapReady || _userMovedMap || _userLatLng == null) return false;
    _mapController.move(_userLatLng!, 14);
    _refresh();
    return true;
  }

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
    _scheduleRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtl,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: l10n.heatmapSearchHint,
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search, size: 20),
          ),
          style: theme.textTheme.bodyLarge,
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          Badge(
            isLabelVisible: _activeFilterCount > 0,
            label: Text('$_activeFilterCount'),
            child: IconButton(
              icon: const Icon(Icons.tune),
              tooltip: l10n.heatmapFilters,
              onPressed: _openFilterSheet,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(51.5074, -0.1276),
              initialZoom: widget.initialZoom ?? 11,
              onMapReady: () {
                _mapReady = true;
                // If a fix already arrived, open centred on it; otherwise
                // load the default view until one does.
                if (!_maybeAutoCenter()) _refresh();
              },
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) {
                  _userMovedMap = true;
                  _scheduleRefresh();
                }
              },
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: currentTileUrl(),
                userAgentPackageName: 'com.threkir.app',
                tileProvider: CachedTileProvider(
                  store: TileCache.store,
                  maxStale: const Duration(days: 30),
                  dio: TileCache.dio,
                ),
              ),
              // Heat-density background (stacked low-opacity dots) —
              // opt-in via the Filters sheet.
              if (_showHeat)
                CircleLayer(
                  circles: [
                    for (final p in _points)
                      CircleMarker(
                        point: LatLng(p.lat, p.lng),
                        radius: 4,
                        color: Colors.red.withValues(alpha: 0.18),
                        borderStrokeWidth: 0,
                      ),
                  ],
                ),
              // Pinned ("kept") route lines — violet, distinct from the
              // cyan preview, drawn below it and persistent until unpinned.
              if (_pinnedIds.isNotEmpty)
                PolylineLayer(
                  key: const ValueKey('heatmap-pinned-routes'),
                  polylines: [
                    for (final id in _pinnedIds)
                      if (_geomCache[id] != null) ...[
                        Polyline(
                          points: _geomCache[id]!,
                          strokeWidth: 6,
                          color: const Color(0x731E293B),
                        ),
                        Polyline(
                          points: _geomCache[id]!,
                          strokeWidth: 3.5,
                          color: const Color(0xFF8B5CF6),
                        ),
                      ],
                  ],
                ),
              // The previewed route's line — hidden until a pin / row is
              // tapped. Dark casing + cyan body, matching web.
              if (_selectedLine != null)
                PolylineLayer(
                  key: const ValueKey('heatmap-selected-route'),
                  polylines: [
                    Polyline(
                      points: _selectedLine!,
                      strokeWidth: 7,
                      color: const Color(0x731E293B),
                    ),
                    Polyline(
                      points: _selectedLine!,
                      strokeWidth: 4,
                      color: const Color(0xFF22D3EE),
                    ),
                  ],
                ),
              // Halo ring under the selected route's start dot.
              if (_selectedPin != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(_selectedPin!.lat, _selectedPin!.lng),
                      radius: 16,
                      useRadiusInMeter: false,
                      color: const Color(0x2922D3EE),
                      borderColor: const Color(0xFF22D3EE),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              // Club pins (visual; teal).
              MarkerLayer(
                markers: [
                  for (final club in _clubs)
                    Marker(
                      point: LatLng(club.lat, club.lng),
                      width: 18,
                      height: 18,
                      child: const _ClubPinDot(),
                    ),
                ],
              ),
              // Clustered route pins — rebuilds on every camera change so
              // clusters break apart as you zoom in.
              Builder(
                builder: (ctx) {
                  final camera = MapCamera.of(ctx);
                  return MarkerLayer(
                    markers: [
                      for (final c in _buildClusters(camera))
                        Marker(
                          point: LatLng(c.lat, c.lng),
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          child: c.isCluster
                              ? _ClusterBubble(count: c.count)
                              : _RoutePinDot(
                                  featured: c.first.featured,
                                  selected: c.first.id == _selectedRouteId,
                                ),
                        ),
                    ],
                  );
                },
              ),
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
          // Search-results dropdown — overlays without pushing content.
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
          // Clean map by default: the Locate FAB floats just above a
          // floating "N routes" pill (opens the list as a dismissible
          // modal) or, once a route is picked, a compact dismissible
          // card. Neither permanently covers the map — the user's
          // complaint about the old always-present draggable sheet.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 10),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FloatingActionButton.small(
                        heroTag: 'routes_heatmap_locate_fab',
                        tooltip: l10n.heatmapLocateMe,
                        onPressed: _locate,
                        child: const Icon(Icons.my_location),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _selectedPin != null
                        ? _selectionCard(_selectedPin!)
                        : Center(child: _resultsPill()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom pill showing the in-view route count; tap to open the list.
  Widget _resultsPill() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final count = _pins.length;
    final label =
        count == 0 ? l10n.heatmapNoRoutesHere : l10n.heatmapRouteCount(count);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(999),
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openResultsSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.format_list_bulleted,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.titleSmall),
              if (_pinnedIds.isNotEmpty) ...[
                const SizedBox(width: 10),
                const Icon(Icons.push_pin, size: 14, color: Color(0xFF8B5CF6)),
                const SizedBox(width: 2),
                Text(
                  '${_pinnedIds.length}',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: const Color(0xFF8B5CF6)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openResultsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
              ),
              child: _resultsList(ctx, setSheet),
            );
          },
        );
      },
    );
  }

  Widget _resultsList(BuildContext sheetCtx, StateSetter setSheet) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Text(
                l10n.heatmapRouteCount(_pins.length),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '· $_filterLabel',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_pinnedIds.isNotEmpty)
                TextButton(
                  onPressed: () {
                    _clearPinned();
                    setSheet(() {});
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8B5CF6),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(l10n.heatmapClearKept(_pinnedIds.length)),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_pins.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Text(l10n.heatmapNoRoutesHint),
          )
        else
          for (final p in _pins) _routeRow(sheetCtx, setSheet, p),
      ],
    );
  }

  Widget _routeRow(
    BuildContext sheetCtx,
    StateSetter setSheet,
    cm.DiscoverableRoutePin p,
  ) {
    final band = bandForDistance(p.distanceM);
    final meta = <String>[
      formatDistanceForPref(p.distanceM),
      if (p.surface.isNotEmpty) p.surface,
      if (p.runCount > 0) '${p.runCount} run${p.runCount == 1 ? '' : 's'}',
    ].join(' · ');
    return ListTile(
      dense: true,
      selected: p.id == _selectedRouteId,
      leading: p.featured
          ? const Icon(Icons.star, color: Color(0xFFFACC15), size: 20)
          : const Icon(Icons.place_outlined, size: 20),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          if (band != null) _bandBadge(band.label),
          Flexible(
            child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      trailing: IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(
          _pinnedIds.contains(p.id)
              ? Icons.push_pin
              : Icons.push_pin_outlined,
          size: 20,
          color: _pinnedIds.contains(p.id) ? const Color(0xFF8B5CF6) : null,
        ),
        tooltip: _pinnedIds.contains(p.id)
            ? AppLocalizations.of(context).heatmapUnpinFromMap
            : AppLocalizations.of(context).heatmapKeepOnMap,
        onPressed: () async {
          await _togglePin(p);
          setSheet(() {});
        },
      ),
      onTap: () {
        Navigator.of(sheetCtx).pop();
        _selectRoute(p, pan: true);
      },
    );
  }

  /// Compact, dismissible card for the currently-previewed route. Sits at
  /// the bottom over the map (not a draggable sheet); close returns to the
  /// results pill.
  Widget _selectionCard(cm.DiscoverableRoutePin p) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final band = bandForDistance(p.distanceM);
    final meta = <String>[
      formatDistanceForPref(p.distanceM),
      if (p.elevationM != null && p.elevationM! > 0)
        '${p.elevationM!.round()} m',
      if (p.surface.isNotEmpty) p.surface,
      if (p.runCount > 0) '${p.runCount} run${p.runCount == 1 ? '' : 's'}',
    ].join(' · ');
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.heatmapBackToList,
                  onPressed: _clearSelection,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  if (band != null) _bandBadge(band.label),
                  Flexible(
                    child: Text(
                      meta,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PublicRouteScreen(
                              api: widget.api,
                              routeId: p.id,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(l10n.heatmapViewRoute),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _togglePin(p),
                    icon: Icon(
                      _pinnedIds.contains(p.id)
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      size: 18,
                    ),
                    label: Text(_pinnedIds.contains(p.id)
                        ? l10n.heatmapKept
                        : l10n.heatmapKeep),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF8B5CF6),
                      side: const BorderSide(color: Color(0xFF8B5CF6)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bandBadge(String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _FilterGroupLabel extends StatelessWidget {
  final String text;
  const _FilterGroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Cluster count bubble — brand orange with a dark ring + the pin count.
class _ClusterBubble extends StatelessWidget {
  final int count;
  const _ClusterBubble({required this.count});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xF2F2A07B),
        border: Border.all(color: const Color(0xFF0F172A), width: 2),
      ),
      child: Center(
        child: Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }
}

/// A single route pin — orange, gold ring when featured, enlarged when
/// it's the currently selected route.
class _RoutePinDot extends StatelessWidget {
  final bool featured;
  final bool selected;
  const _RoutePinDot({required this.featured, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: selected ? 18 : 14,
        height: selected ? 18 : 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFF2A07B),
          border: Border.all(
            color: featured ? const Color(0xFFFACC15) : const Color(0xFF0F172A),
            width: featured ? 3 : 2,
          ),
        ),
      ),
    );
  }
}

class _ClubPinDot extends StatelessWidget {
  const _ClubPinDot();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF7FB3C2),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0xFF0F172A), width: 2),
        ),
      ),
    );
  }
}

/// Blue dot with a white halo + outline — the mobile twin of MapLibre's
/// `GeolocateControl` user-position marker.
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
