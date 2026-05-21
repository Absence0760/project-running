import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';

import '../elevation.dart';
import '../geocoding.dart';
import '../local_route_store.dart';
import '../preferences.dart';
import '../rate_limit_errors.dart';
import '../route_loop.dart';
import '../route_overlap.dart';
import '../routing.dart';
import '../run_stats.dart' show haversineMetres;
import '../tile_cache.dart';
import '../widgets/snap_to_start.dart';
import '../widgets/top_banner.dart';

/// Full-screen in-app route builder. Phase 3 "In-app route builder
/// (free)" — the mobile counterpart of `apps/web/src/lib/components/
/// RouteBuilder.svelte`.
///
/// Shipped features:
/// - tap-to-place waypoints, OSRM-snapped (foot / car) or straight
/// - long-press a waypoint to drag-reshape — pan to move, release to
///   commit + re-fetch the snapped polyline
/// - tap near the start (when 3+ waypoints placed) snaps the loop closed
///   and shows a pulsing halo on the start marker as the affordance
/// - "Locate me" FAB centers on the user's current GPS position
/// - place-name search in the AppBar — debounced MapTiler geocoding,
///   tap a result to fly the camera there
/// - elevation gain in the status pill, sampled at up to 100 points per
///   re-route via Open-Meteo
/// - out-and-back overlap is rendered as a purple over-stroke on the
///   retraced sections
/// - undo / clear / save (name + public toggle → ApiClient.saveRoute
///   + LocalRouteStore.save, then pops with the new route)
///
/// Pure helpers (`routing.dart`, `elevation.dart`, `geocoding.dart`,
/// `route_overlap.dart`, `widgets/snap_to_start.dart`) are unit-tested
/// in isolation; this screen is the integration glue.
class RouteBuilderScreen extends StatefulWidget {
  final ApiClient apiClient;
  final LocalRouteStore routeStore;
  final LatLng? initialCenter;

  /// Test seams — production passes null and each helper uses its
  /// dart:io fetcher / OS geolocator default.
  final OsrmFetcher? osrmFetcher;
  final ElevationFetcher? elevationFetcher;
  final GeocodingFetcher? geocodingFetcher;
  final Future<void> Function(cm.Route route)? saveRouteFn;
  final Future<Position> Function()? locateFn;

  const RouteBuilderScreen({
    super.key,
    required this.apiClient,
    required this.routeStore,
    this.initialCenter,
    this.osrmFetcher,
    this.elevationFetcher,
    this.geocodingFetcher,
    this.saveRouteFn,
    this.locateFn,
  });

  @override
  State<RouteBuilderScreen> createState() => _RouteBuilderScreenState();
}

class _RouteBuilderScreenState extends State<RouteBuilderScreen> {
  static const _kDefaultCenter = LatLng(51.5074, -0.1278); // London
  final MapController _map = MapController();

  // Waypoint + polyline state.
  final List<cm.Waypoint> _waypoints = [];
  List<cm.Waypoint> _polyline = const [];
  double _distanceM = 0;
  double _elevationGainM = 0;
  List<OverlapSpan> _overlapSpans = const [];

  // Mode toggle + in-flight flags.
  RouteBuilderMode _mode = RouteBuilderMode.trail;
  bool _routing = false;
  bool _saving = false;

  // Drag state. When the user long-presses a marker, we enter drag
  // mode; subsequent map taps move that waypoint until the user taps
  // the marker again or hits the cancel chip.
  int? _dragIndex;

  // Place search.
  final TextEditingController _searchCtl = TextEditingController();
  List<PlaceResult> _searchResults = const [];
  Timer? _searchDebounce;
  bool _searchOpen = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _map.dispose();
    super.dispose();
  }

  String get _maptilerKey => dotenv.env['MAPTILER_KEY'] ?? '';

  String get _tileUrl {
    if (_maptilerKey.isEmpty) {
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    return 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$_maptilerKey';
  }

  OsrmProfile get _osrmProfile =>
      _mode == RouteBuilderMode.road ? OsrmProfile.car : OsrmProfile.foot;

  /// Run OSRM through every waypoint + update derived fields
  /// (polyline / distance / elevation / overlap). Pure side-effect
  /// helper called from every mutator (_onMapTap, _undo, drag commit,
  /// snap-to-start close).
  Future<void> _rerouteThrough(List<cm.Waypoint> waypoints) async {
    if (_mode == RouteBuilderMode.straight) {
      setState(() {
        _waypoints
          ..clear()
          ..addAll(waypoints);
        _polyline = List<cm.Waypoint>.from(waypoints);
        _distanceM = straightLineDistance(waypoints);
        _overlapSpans = const [];
      });
      unawaited(_refreshElevation());
      return;
    }
    if (waypoints.length < 2) {
      setState(() {
        _waypoints
          ..clear()
          ..addAll(waypoints);
        _polyline = const [];
        _distanceM = 0;
        _elevationGainM = 0;
        _overlapSpans = const [];
      });
      return;
    }
    setState(() => _routing = true);
    try {
      final routed = await fetchRouteThrough(
        waypoints,
        profile: _osrmProfile,
        fetcher: widget.osrmFetcher,
      );
      if (!mounted) return;
      setState(() {
        _waypoints
          ..clear()
          ..addAll(waypoints);
        _polyline = routed.coordinates;
        _distanceM = routed.distanceMetres;
        _overlapSpans = detectOverlapSpans(routed.coordinates);
        _routing = false;
      });
      unawaited(_refreshElevation());
    } catch (e) {
      if (!mounted) return;
      setState(() => _routing = false);
      showTopBanner(context, 'Routing failed: $e');
    }
  }

  /// Sample the current polyline and look up open-meteo elevations.
  /// Fire-and-forget — runs after the polyline updates so the user
  /// sees the line + distance immediately and elevation fills in on
  /// the network round-trip (~300 ms). L4 best-effort: a failure just
  /// leaves the gain reading at 0.
  Future<void> _refreshElevation() async {
    if (_polyline.length < 2) {
      if (mounted) setState(() => _elevationGainM = 0);
      return;
    }
    final sample = sampleCoordinates(_polyline);
    try {
      final elevations = await fetchElevations(
        sample,
        fetcher: widget.elevationFetcher,
      );
      final gain = calculateElevationGain(elevations);
      if (!mounted) return;
      setState(() => _elevationGainM = gain);
    } catch (e) {
      debugPrint('elevation fetch failed: $e');
    }
  }

  Future<void> _onMapTap(TapPosition _, LatLng latLng) async {
    if (_routing || _saving) return;
    final tapWaypoint =
        cm.Waypoint(lat: latLng.latitude, lng: latLng.longitude);

    // Drag-to-reshape: a marker is currently selected, this tap moves
    // it to the tap point + re-routes.
    if (_dragIndex != null) {
      final idx = _dragIndex!;
      _dragIndex = null;
      final moved = _mode == RouteBuilderMode.straight
          ? tapWaypoint
          : await snapToRoad(
              tapWaypoint,
              profile: _osrmProfile,
              fetcher: widget.osrmFetcher,
            );
      final next = List<cm.Waypoint>.from(_waypoints);
      next[idx] = moved;
      await _rerouteThrough(next);
      return;
    }

    // Snap-to-start: close the loop instead of placing a stub-end
    // waypoint right next to the start marker.
    if (shouldSnapToStart(
      tap: tapWaypoint,
      existingWaypoints: _waypoints,
    )) {
      final next = [..._waypoints, _waypoints.first];
      await _rerouteThrough(next);
      return;
    }

    final next = _mode == RouteBuilderMode.straight
        ? tapWaypoint
        : await snapToRoad(
            tapWaypoint,
            profile: _osrmProfile,
            fetcher: widget.osrmFetcher,
          );
    await _rerouteThrough([..._waypoints, next]);
  }

  Future<void> _undo() async {
    if (_routing || _saving || _waypoints.isEmpty) return;
    final next = _waypoints.sublist(0, _waypoints.length - 1);
    await _rerouteThrough(next);
  }

  /// Generate a loop by target distance. Mirrors web `/routes/new`
  /// "Generate loop" CTA — opens a sheet asking for a target km/mi
  /// value, then uses `generateLoopWaypoints` to produce radial
  /// scaffolding around the current map centre and hands it off to
  /// the existing OSRM rerouting pipe via `_rerouteThrough`.
  ///
  /// Single-shot for v1 (no bisect-and-retry loop yet — that's a
  /// follow-up). The result is usually within ±15% of the target
  /// thanks to `kDefaultScaleFactor`'s empirical tuning; users can
  /// nudge the radius via undo + retry if they want it tighter.
  Future<void> _generateLoop() async {
    if (_routing || _saving) return;
    final centre = _map.camera.center;
    final unit = activeDistanceUnit;
    final picked = await _pickLoopDistance(unit);
    if (picked == null || !mounted) return;
    if (!isValidTargetDistance(picked)) {
      showTopBanner(context, 'Enter a target distance up to 1000 km.');
      return;
    }
    final waypoints = generateLoopWaypoints(
      start: centre,
      targetDistanceMetres: picked,
      // Random seed so consecutive Generate taps emit different
      // candidate loops — gives the user a free re-roll.
      radialSeedRad: DateTime.now().millisecondsSinceEpoch / 1000 % 6.28,
    );
    final next = waypoints
        .map((p) => cm.Waypoint(lat: p.latitude, lng: p.longitude))
        .toList();
    await _rerouteThrough(next);
  }

  /// Prompt the user for a target distance. Returns metres, or null
  /// if cancelled. The unit picker renders in the user's preferred
  /// unit (km / mi) and converts to metres on confirm.
  Future<double?> _pickLoopDistance(DistanceUnit unit) async {
    final ctl = TextEditingController(
      text: unit == DistanceUnit.mi ? '3' : '5',
    );
    final label = unit == DistanceUnit.mi ? 'mi' : 'km';
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Generate loop'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Target distance — we\'ll build a radial loop around '
                'the current map centre.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(suffixText: label),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(ctl.text.trim());
                if (v == null || v <= 0) {
                  Navigator.pop(ctx);
                  return;
                }
                // Convert unit value → metres.
                final metres = unit == DistanceUnit.mi
                    ? v * 1609.344
                    : v * 1000;
                Navigator.pop(ctx, metres);
              },
              child: const Text('Generate'),
            ),
          ],
        );
      },
    );
    ctl.dispose();
    return result;
  }

  void _clear() {
    if (_routing || _saving) return;
    setState(() {
      _waypoints.clear();
      _polyline = const [];
      _distanceM = 0;
      _elevationGainM = 0;
      _overlapSpans = const [];
      _dragIndex = null;
    });
  }

  Future<void> _save() async {
    if (_polyline.length < 2) {
      showTopBanner(context, 'Place at least two waypoints first.');
      return;
    }
    final result = await showDialog<SaveDialogResult>(
      context: context,
      builder: (_) => const SaveRouteDialog(),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    final route = cm.Route(
      id: const Uuid().v4(),
      name: result.name,
      waypoints: _polyline,
      distanceMetres: _distanceM,
      elevationGainMetres: _elevationGainM,
      isPublic: result.isPublic,
      surface: _surfaceFor(_mode),
      description: result.description,
    );
    try {
      await (widget.saveRouteFn ?? widget.apiClient.saveRoute)(route);
      await widget.routeStore.save(route);
      if (!mounted) return;
      Navigator.of(context).pop<cm.Route>(route);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTopBanner(context, formatSaveRouteError(e));
    }
  }

  Future<void> _locate() async {
    if (_routing || _saving) return;
    try {
      final pos = widget.locateFn != null
          ? await widget.locateFn!()
          : await _platformLocate();
      if (!mounted) return;
      _map.move(LatLng(pos.latitude, pos.longitude), 15);
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
    // Permission gate matches the recorder's own pattern.
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
    _map.move(LatLng(result.lat, result.lng), 15);
    FocusManager.instance.primaryFocus?.unfocus();
    _searchCtl.clear();
    setState(() {
      _searchResults = const [];
      _searchOpen = false;
    });
  }

  void _toggleDragOn(int index) {
    if (_routing || _saving) return;
    setState(() => _dragIndex = _dragIndex == index ? null : index);
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
    final overlapLatLngs = _polyline.length >= 2
        ? overlapLatLngsFor(_polyline, _overlapSpans)
        : const <List<LatLng>>[];
    final center = widget.initialCenter ?? _kDefaultCenter;

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
          IconButton(
            tooltip: 'Generate loop',
            onPressed: _routing || _saving ? null : _generateLoop,
            icon: const Icon(Icons.refresh_outlined),
          ),
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
                userAgentPackageName: 'com.threkir.app',
                maxNativeZoom: 19,
                maxZoom: 22,
                tileProvider: CachedTileProvider(
                  store: TileCache.store,
                  maxStale: const Duration(days: 30),
                  dio: TileCache.dio,
                ),
              ),
              // Base polyline.
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
              // Overlap (out-and-back) over-stroke — purple, matches
              // the web spec.
              if (overlapLatLngs.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (final span in overlapLatLngs)
                      if (span.length >= 2)
                        Polyline(
                          points: span,
                          strokeWidth: 6,
                          color: const Color(0xCCB084EE),
                        ),
                  ],
                ),
              // Waypoint pins. Long-press toggles drag mode for that
              // waypoint; the next map tap moves it.
              if (waypointLatLngs.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < waypointLatLngs.length; i++)
                      Marker(
                        point: waypointLatLngs[i],
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onLongPress: () => _toggleDragOn(i),
                          onTap: _dragIndex == null
                              ? null
                              : () => _toggleDragOn(i),
                          child: _WaypointPin(
                            index: i,
                            isStart: i == 0,
                            isEnd: i == waypointLatLngs.length - 1 && i > 0,
                            isDragging: _dragIndex == i,
                            pulseStart: i == 0 &&
                                _waypoints.length >= 3 &&
                                _dragIndex == null,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          // Top status pill — distance + elevation gain + spinner.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _StatusPill(
              distanceM: _distanceM,
              elevationGainM: _elevationGainM,
              routing: _routing,
              saving: _saving,
              waypointCount: _waypoints.length,
              mode: _mode,
              dragIndex: _dragIndex,
              onCancelDrag: () => setState(() => _dragIndex = null),
            ),
          ),
          // Search-results dropdown (under the AppBar).
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
          // Bottom mode toggle. Right edge clears the FAB column so
          // taps on the Straight segment land on the toggle rather
          // than the Locate FAB — the FAB is in the Scaffold's
          // floatingActionButton slot (always on top of body Stack
          // children) and previously overlapped the rightmost
          // segment's hit area.
          Positioned(
            bottom: 88,
            left: 16,
            right: 16 + 56 + 12,
            child: _ModeToggle(
              mode: _mode,
              onChanged: _routing || _saving
                  ? null
                  : (m) {
                      setState(() => _mode = m);
                      // Re-route through existing waypoints when the
                      // mode changes — the polyline shape depends on
                      // the OSRM profile.
                      if (_waypoints.length >= 2) {
                        unawaited(
                            _rerouteThrough(List.of(_waypoints)));
                      }
                    },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'route_builder_locate_fab',
        tooltip: 'Locate me',
        onPressed: _routing || _saving ? null : _locate,
        child: const Icon(Icons.my_location),
      ),
    );
  }
}

/// Available routing profiles surfaced to the user. Maps to
/// [OsrmProfile] for road/trail and bypasses OSRM for straight.
enum RouteBuilderMode { trail, road, straight }

String _modeLabel(RouteBuilderMode m) => switch (m) {
      RouteBuilderMode.trail => 'Trail',
      RouteBuilderMode.road => 'Road',
      RouteBuilderMode.straight => 'Straight',
    };

/// Format the user-visible message for a saveRoute failure. Pure
/// function — extracted so the catch branch in `_save` stays a
/// one-liner and the rate-limit / generic split is unit-testable
/// without driving the full widget tree.
///
/// Behaviour:
///   - PostgrestException with the rate-limit signature (P0001 +
///     migration 20260907_001 message) becomes the friendly "wait
///     N minutes" wording from `rate_limit_errors.dart`.
///   - LateInitializationError (Supabase SDK's `late client` field
///     read before init) or a StateError carrying the "bootstrap"
///     signature from [ApiClient] surface as the offline-mode
///     message. This catches the case where Supabase init failed
///     silently in `main.dart` and a call slipped past the null-guard
///     on `apiClient` (defence in depth — the primary fix is to
///     leave `api == null` so the user can't reach this path at all).
///   - Anything else falls through to `Save failed: <toString>` so
///     debugging information (RLS denials, FK violations, network
///     errors) isn't hidden by an over-eager translation.
String formatSaveRouteError(Object e) {
  if (e is PostgrestException) {
    final friendly = rateLimitErrorMessage(code: e.code, message: e.message);
    if (friendly != null) return friendly;
  }
  // `LateInitializationError` is not a public type in dart:core — the
  // SDK throws a private subclass of `Error` whose `toString()` begins
  // with the literal `"LateInitializationError:"`. Match on the string
  // signature rather than `is`. Pair with the StateError signature
  // from `ApiClient`'s bootstrap guard so both error sites surface the
  // same friendly copy.
  if ((e is Error && e.toString().startsWith('LateInitializationError')) ||
      (e is StateError &&
          e.message.contains('Supabase.initialize'))) {
    return "Can't reach the server. Sign in or check your connection and try again.";
  }
  return 'Save failed: $e';
}

String _surfaceFor(RouteBuilderMode mode) {
  return switch (mode) {
    RouteBuilderMode.trail => 'trail',
    RouteBuilderMode.road => 'road',
    RouteBuilderMode.straight => 'mixed',
  };
}

/// Sum great-circle distances between consecutive waypoints. Re-uses
/// the haversine helper from `run_stats`.
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

/// Slice the polyline into [LatLng] runs by overlap span — used to
/// draw the purple over-stroke on retraced sections. Public so the
/// widget test can assert the slicing without mounting the screen.
List<List<LatLng>> overlapLatLngsFor(
  List<cm.Waypoint> polyline,
  List<OverlapSpan> spans,
) {
  if (spans.isEmpty) return const [];
  final out = <List<LatLng>>[];
  for (final span in spans) {
    if (span.startIndex >= polyline.length) continue;
    final end = span.endIndex.clamp(0, polyline.length - 1);
    final slice = <LatLng>[
      for (var i = span.startIndex; i <= end; i++)
        LatLng(polyline[i].lat, polyline[i].lng),
    ];
    if (slice.length >= 2) out.add(slice);
  }
  return out;
}

class _StatusPill extends StatelessWidget {
  final double distanceM;
  final double elevationGainM;
  final bool routing;
  final bool saving;
  final int waypointCount;
  final RouteBuilderMode mode;
  final int? dragIndex;
  final VoidCallback onCancelDrag;

  const _StatusPill({
    required this.distanceM,
    required this.elevationGainM,
    required this.routing,
    required this.saving,
    required this.waypointCount,
    required this.mode,
    required this.dragIndex,
    required this.onCancelDrag,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String label;
    if (dragIndex != null) {
      label = 'Tap anywhere to move point ${dragIndex! + 1}';
    } else if (waypointCount == 0) {
      // Surface the current routing mode in the empty hint so flipping
      // Trail / Road / Straight gives immediate visual feedback even
      // before the user places two waypoints (otherwise the mode
      // toggle looks dead until there's a polyline to reshape).
      label = 'Tap the map to place waypoints · ${_modeLabel(mode)}';
    } else if (waypointCount == 1) {
      // One waypoint placed — same rationale: show the mode so the
      // user can compose the toggle + next tap with confidence.
      label = 'Place another to draw the line · ${_modeLabel(mode)}';
    } else {
      final km = (distanceM / 1000).toStringAsFixed(2);
      final pointsLabel =
          '$waypointCount ${waypointCount == 1 ? "point" : "points"}';
      label = elevationGainM > 0
          ? '$km km · ${elevationGainM.round()} m ↑ · $pointsLabel'
          : '$km km · $pointsLabel';
    }
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
          if (dragIndex != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Cancel drag',
              onPressed: onCancelDrag,
              visualDensity: VisualDensity.compact,
            )
          else if (routing || saving) ...[
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

/// Waypoint pin. Renders a small numbered circle (green start, red
/// end, blue intermediate). The start pin shows a pulsing halo when
/// the route is long enough to close as a loop — visual cue for
/// snap-to-start. While the user is dragging this waypoint, the pin
/// switches to an amber outline.
class _WaypointPin extends StatefulWidget {
  final int index;
  final bool isStart;
  final bool isEnd;
  final bool isDragging;
  final bool pulseStart;

  const _WaypointPin({
    required this.index,
    required this.isStart,
    required this.isEnd,
    required this.isDragging,
    required this.pulseStart,
  });

  @override
  State<_WaypointPin> createState() => _WaypointPinState();
}

class _WaypointPinState extends State<_WaypointPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isDragging
        ? Colors.amber
        : widget.isStart
            ? Colors.green
            : widget.isEnd
                ? Colors.red
                : Colors.blueGrey;
    final pin = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '${widget.index + 1}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
    if (!widget.pulseStart) return pin;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        final t = _pulse.value;
        final ringScale = 1 + 0.7 * t;
        final ringOpacity = (1 - t).clamp(0.0, 1.0);
        return SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: ringScale,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.withValues(alpha: 0.25 * ringOpacity),
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: pin,
    );
  }
}

/// Result popped by [SaveRouteDialog]. Promoted alongside the dialog so
/// widget tests can pattern-match on the returned shape.
@visibleForTesting
class SaveDialogResult {
  final String name;
  final bool isPublic;
  final String? description;
  const SaveDialogResult({
    required this.name,
    required this.isPublic,
    this.description,
  });
}

/// Save-route modal. Promoted from file-private so the widget test
/// can pump it in isolation rather than mounting the whole builder
/// (which would need a working MapLibre/OSRM/elevation stack).
@visibleForTesting
class SaveRouteDialog extends StatefulWidget {
  const SaveRouteDialog();
  @override
  State<SaveRouteDialog> createState() => _SaveRouteDialogState();
}

class _SaveRouteDialogState extends State<SaveRouteDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _isPublic = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save route'),
      // SingleChildScrollView so the Make public toggle isn't clipped
      // behind the Save / Cancel actions on short screens (or when
      // the keyboard opens). Without it, AlertDialog overflows its
      // content area under the actions strip.
      content: SingleChildScrollView(
        child: Column(
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
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Surface, hills, parking, anything worth noting',
              ),
              maxLines: 3,
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
            final desc = _description.text.trim();
            Navigator.of(context).pop(SaveDialogResult(
              name: trimmed,
              isPublic: _isPublic,
              description: desc.isEmpty ? null : desc,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
