import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';

import '../elevation.dart';
import '../geocoding.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../local_route_store.dart';
import '../preferences.dart';
import '../rate_limit_errors.dart';
import '../route_loop.dart';
import '../route_overlap.dart';
import '../routing.dart';
import '../social_service.dart';
import '../run_stats.dart' show haversineMetres;
import '../tile_cache.dart';
import '../widgets/live_run_map.dart' show currentTileUrl;
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

  /// Optional social service for fetching the user's clubs. When
  /// provided, the SaveRouteDialog renders a "Save to" picker so a
  /// route can be created against a club library directly. Mirrors
  /// web's `?club=<id>` URL parameter on `/routes/new` plus a
  /// dropdown — mobile lacks an equivalent URL surface, so the
  /// picker is the universal entry point regardless of where the
  /// builder was launched from.
  final SocialService? social;

  /// Optional pre-selected club. When non-null, the SaveRouteDialog
  /// opens with this club already chosen in the "Save to" picker —
  /// the equivalent of landing on `/routes/new?club=<id>` on web.
  /// The user can still switch to Personal or a different club from
  /// the picker; nothing is locked.
  final String? initialClubId;

  /// Test seams — production passes null and each helper uses its
  /// dart:io fetcher / OS geolocator default.
  final OsrmFetcher? osrmFetcher;
  final ElevationFetcher? elevationFetcher;
  final GeocodingFetcher? geocodingFetcher;
  final Future<void> Function(cm.Route route)? saveRouteFn;
  final Future<Position> Function()? locateFn;

  /// Test seam — when non-null, [_loadClubs] reads from this instead
  /// of calling into [social]. Lets widget tests drive the dialog's
  /// club picker without booting a real SocialService / Supabase.
  final Future<List<RouteClubChoice>> Function()? clubChoicesLoader;

  const RouteBuilderScreen({
    super.key,
    required this.apiClient,
    required this.routeStore,
    this.initialCenter,
    this.social,
    this.initialClubId,
    this.osrmFetcher,
    this.elevationFetcher,
    this.geocodingFetcher,
    this.saveRouteFn,
    this.locateFn,
    this.clubChoicesLoader,
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

  /// Monotonic counter incremented on every `_rerouteThrough` entry.
  /// Each routing pass captures `_routeGeneration` at start, threads
  /// it into `fetchRouteThrough` as a cancellation gate, and drops
  /// its result if the gate fires (which happens whenever the user
  /// places another pin, drags a marker, or hits clear / undo
  /// before the previous routing pass completes). Mirrors web's
  /// `routeVersion` counter on RouteBuilder.svelte.
  int _routeGeneration = 0;

  /// Reused across re-routes so re-snapping after a new pin only fetches
  /// the one new segment, not every prior one. See [RouteSegmentCache].
  final RouteSegmentCache _segmentCache = RouteSegmentCache();

  // Drag state. When the user long-presses a marker, we enter drag
  // mode; subsequent map taps move that waypoint until the user taps
  // the marker again or hits the cancel chip.
  int? _dragIndex;

  // Place search.
  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<PlaceResult> _searchResults = const [];

  /// True while the search TextField is focused — the keyboard is
  /// up. We hide the bottom mode toggle in this state so it doesn't
  /// overlap the search-results dropdown, and condense the AppBar
  /// actions into an overflow menu so the search field gets the
  /// full title width.
  bool _searchFocused = false;
  Timer? _searchDebounce;
  bool _searchOpen = false;

  // Club picker state for the SaveRouteDialog. Loaded in initState so
  // by the time the user finishes building + taps Save the list is
  // already there. Failure is silent — no clubs simply hides the
  // picker, matching the no-SocialService case.
  List<RouteClubChoice> _clubChoices = const [];

  @override
  void initState() {
    super.initState();
    _loadClubs();
    _searchFocus.addListener(() {
      if (!mounted) return;
      setState(() => _searchFocused = _searchFocus.hasFocus);
    });
  }

  Future<void> _loadClubs() async {
    final loader = widget.clubChoicesLoader ?? _defaultClubsLoader;
    final social = widget.social;
    if (loader == _defaultClubsLoader && social == null) return;
    try {
      final choices = await loader();
      if (!mounted || choices.isEmpty) return;
      setState(() => _clubChoices = choices);
    } catch (e) {
      debugPrint('RouteBuilder._loadClubs failed: $e');
    }
  }

  Future<List<RouteClubChoice>> _defaultClubsLoader() async {
    final social = widget.social;
    if (social == null) return const [];
    final clubs = await social.fetchMyClubs();
    // Only clubs the user is actively a member of can hold routes.
    // Pending memberships and non-member viewers are excluded server-
    // side via RLS, but we filter here too for snappier UX (no
    // dropdown entries that would error on save).
    return [
      for (final c in clubs)
        if (c.isMember && c.viewerStatus == 'active')
          RouteClubChoice(id: c.row.id, name: c.row.name),
    ];
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _searchFocus.dispose();
    _map.dispose();
    super.dispose();
  }

  String get _maptilerKey => dotenv.env['MAPTILER_KEY'] ?? '';

  /// Delegate to the shared `currentTileUrl` helper so the route
  /// builder honours `TILE_URL_TEMPLATE` (local Protomaps dev) the
  /// same way every other mobile map surface does — see
  /// `live_run_map.dart` for the helper, which falls back to OSM
  /// tiles when neither MAPTILER_KEY nor TILE_URL_TEMPLATE is set.
  String get _tileUrl => currentTileUrl();

  OsrmProfile get _osrmProfile =>
      _mode == RouteBuilderMode.road ? OsrmProfile.car : OsrmProfile.foot;

  /// Run OSRM through every waypoint + update derived fields
  /// (polyline / distance / elevation / overlap). Pure side-effect
  /// audit/accessibility — WCAG 4.1.3 (Status Messages). Pin
  /// placement / undo / clear / loop-close mutate the route silently
  /// from a screen-reader's view: the distance + waypoint count live
  /// in a `_StatusPill` that updates via `setState` without focus, so
  /// TalkBack never reads the change. `SemanticsService.announce`
  /// pushes a one-shot live-region message. Best-effort: a platform
  /// throw must not break the builder — wrap in try / catch (mirrors
  /// `run_screen._announceA11yState`).
  void _announceA11yState(String message) {
    try {
      SemanticsService.announce(message, TextDirection.ltr);
    } catch (e) {
      debugPrint('SemanticsService.announce failed: $e');
    }
  }

  /// Spoken summary of the current route after a mutation settles —
  /// "3 points, 2.40 km" / "Route cleared".
  void _announceRouteState() {
    final l10n = AppLocalizations.of(context);
    if (_waypoints.isEmpty) {
      _announceA11yState(l10n.routeBuilderRouteCleared);
      return;
    }
    final n = _waypoints.length;
    _announceA11yState(
      l10n.routeBuilderPointsSummary(n, formatDistanceForPref(_distanceM)),
    );
  }

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
      _announceRouteState();
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
      _announceRouteState();
      return;
    }
    // Bump the generation on entry; the captured snapshot is the
    // version this pass owns. Any newer pass during our awaits will
    // increment _routeGeneration, the `cancelled` gate will fire,
    // and we'll drop the result on the way back.
    final myGen = ++_routeGeneration;
    setState(() => _routing = true);
    try {
      final routed = await fetchRouteThrough(
        waypoints,
        profile: _osrmProfile,
        fetcher: widget.osrmFetcher,
        cancelled: () => myGen != _routeGeneration,
        cache: _segmentCache,
      );
      if (!mounted) return;
      if (routed.wasCancelled) {
        // A newer pass has started — DON'T touch _polyline /
        // _distanceM / _routing. The newer pass owns those now.
        return;
      }
      setState(() {
        _waypoints
          ..clear()
          ..addAll(waypoints);
        _polyline = routed.coordinates;
        _distanceM = routed.distanceMetres;
        _overlapSpans = detectOverlapSpans(routed.coordinates);
        _routing = false;
      });
      _announceRouteState();
      // Web-parity soft warning: per-segment routing means a
      // single unreachable waypoint falls back to a straight line
      // for that segment but the rest of the polyline stays
      // road-accurate. Surface the partial-success state so the
      // user knows to drag the bad pin.
      if (routed.hadFallbacks && routed.totalSegments > 0) {
        final failed = routed.totalSegments - routed.okSegments;
        showTopBanner(
          context,
          failed == routed.totalSegments
              ? AppLocalizations.of(context).routeBuilderRouteFailedStraightLines
              : AppLocalizations.of(context).routeBuilderSegmentsFailed(failed),
        );
      }
      unawaited(_refreshElevation());
    } catch (e) {
      if (!mounted) return;
      // Don't surface stale errors from cancelled passes — only the
      // current generation owns the user-visible banner.
      if (myGen != _routeGeneration) return;
      setState(() => _routing = false);
      showTopBanner(
          context, AppLocalizations.of(context).routeBuilderRoutingFailed('$e'));
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
    // Don't gate on `_routing` — the cancellation system in
    // `_rerouteThrough` (gen-counter + `cancelled` gate threaded
    // into fetchRouteThrough) handles overlapping passes correctly,
    // and gating the tap here would make rapid pin placement feel
    // sticky on a slow OSRM call. Still gate on `_saving` because
    // the save-dialog flow shouldn't be racing pin placements.
    if (_saving) return;
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
      // Reject a drag that lands within 5 m of any OTHER existing
      // waypoint — the OSRM segment between them would be a
      // zero-length back-and-forth, distorting the polyline and
      // the distance / elevation readouts. Surface the rejection
      // so the user knows the drag didn't take and can retry.
      if (isTooCloseToOtherWaypoints(
        candidate: moved,
        existing: _waypoints,
        excludeIndex: idx,
      )) {
        if (!mounted) return;
        showTopBanner(
          context,
          AppLocalizations.of(context).routeBuilderTooCloseToPin,
        );
        return;
      }
      final next = List<cm.Waypoint>.from(_waypoints);
      next[idx] = moved;
      await _rerouteThrough(next);
      return;
    }

    // Snap-to-start: close the loop instead of placing a stub-end
    // waypoint right next to the start marker. Runs BEFORE the
    // close-to-existing check below — closing the loop on the
    // start is a deliberate UX affordance, not a degenerate
    // placement.
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
    // Reject the placement when the new pin (post-snap) would
    // duplicate or near-duplicate an existing one. This catches:
    //   - fat-finger double-taps on the same spot
    //   - a tap visually distinct from the prior pin that
    //     `snapToRoad` pulled onto the same road segment
    // Either way the user's intended action would produce a
    // zero-length OSRM segment that breaks the polyline.
    if (isTooCloseToOtherWaypoints(
      candidate: next,
      existing: _waypoints,
    )) {
      if (!mounted) return;
      showTopBanner(
        context,
        AppLocalizations.of(context).routeBuilderPinAlreadyThere,
      );
      return;
    }
    await _rerouteThrough([..._waypoints, next]);
  }

  Future<void> _undo() async {
    if (_routing || _saving || _waypoints.isEmpty) return;
    final next = _waypoints.sublist(0, _waypoints.length - 1);
    // If the user was dragging the to-be-removed last waypoint,
    // cancel the drag — otherwise `_dragIndex` points at a stale
    // index and the status pill shows "Tap to move point N" for a
    // marker that no longer exists.
    if (_dragIndex == _waypoints.length - 1) {
      setState(() => _dragIndex = null);
    }
    await _rerouteThrough(next);
  }

  /// Remove the currently-dragged waypoint and re-route through the
  /// rest. Surfaced via the trash button in the status pill when a
  /// marker is "lifted" (drag mode active).
  ///
  /// Pre-fix, the only way to remove a specific interior waypoint
  /// was to Undo back to it (losing every later placement) and redo
  /// the rest of the route. With this affordance you can lift the
  /// stray waypoint and delete it in two taps without disturbing
  /// anything else.
  Future<void> _deleteSelectedWaypoint() async {
    if (_saving) return;
    final idx = _dragIndex;
    if (idx == null) return;
    setState(() => _dragIndex = null);
    final next = List<cm.Waypoint>.from(_waypoints)..removeAt(idx);
    await _rerouteThrough(next);
  }

  /// Generate a loop by target distance. Ports web's iterative
  /// bisection approach (`apps/web/src/lib/components/
  /// RouteBuilder.svelte:generateLoop`) — the previous mobile
  /// implementation was a single-shot generate-and-hope, which
  /// often produced routes 20-40 % off-target. The user reported
  /// "the generate loop logic is not good, can you copy what the
  /// web app does."
  ///
  /// Algorithm (mirrors web exactly):
  ///   1. Generate radial scaffolding from `centre` with the
  ///      default scale factor + a deterministic per-call radial
  ///      seed.
  ///   2. Route through; measure actual distance.
  ///   3. If within ±15 % of target → done.
  ///   4. Otherwise bisect the scale range and try again. Up to
  ///      4 attempts total.
  ///   5. Track the BEST attempt (closest to target) and keep
  ///      whichever ended closest — OSRM's response is non-
  ///      monotonic in twisty grids and the final attempt isn't
  ///      always the best.
  Future<void> _generateLoop() async {
    if (_routing || _saving) return;
    final centre = _map.camera.center;
    final unit = activeDistanceUnit;
    final picked = await _pickLoopDistance(unit);
    if (picked == null || !mounted) return;
    if (!isValidTargetDistance(picked)) {
      showTopBanner(
          context, AppLocalizations.of(context).routeBuilderTargetTooLong);
      return;
    }

    // Per-call deterministic radial seed so subsequent iterations
    // all share the same starting orientation — bisecting scale
    // with a re-randomised pattern would chase noise.
    final radialSeed =
        DateTime.now().millisecondsSinceEpoch / 1000 % 6.28;
    var scaleFactor = kDefaultScaleFactor;
    var scaleRange = initScaleRange();
    const maxAttempts = 4;

    // Track best attempt across iterations.
    List<cm.Waypoint>? bestWaypoints;
    List<cm.Waypoint>? bestPolyline;
    var bestDistance = double.infinity;
    var bestDelta = double.infinity;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final seeds = generateLoopWaypoints(
        start: centre,
        targetDistanceMetres: picked,
        scaleFactor: scaleFactor,
        radialSeedRad: radialSeed,
      );
      final next = seeds
          .map((p) => cm.Waypoint(lat: p.latitude, lng: p.longitude))
          .toList();
      // Route through the scaffolding. _rerouteThrough cancels any
      // in-flight previous attempt via the generation counter so
      // concurrent attempts are safe.
      await _rerouteThrough(next);
      if (!mounted) return;
      // Measure actual distance from the resulting polyline.
      final actual = _distanceM;
      if (actual <= 0) break;
      final delta = (picked - actual).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestDistance = actual;
        bestWaypoints = List.of(_waypoints);
        bestPolyline = List.of(_polyline);
      }
      if (isWithinAcceptBand(
        targetDistanceMetres: picked,
        actualDistanceMetres: actual,
      )) {
        break;
      }
      final advised = bisectScale(
        range: scaleRange,
        currentScale: scaleFactor,
        targetDistanceMetres: picked,
        actualDistanceMetres: actual,
      );
      scaleFactor = advised.scale;
      scaleRange = advised.range;
    }

    // If the final attempt drifted away from the best one,
    // restore the best. Mirrors web's post-loop fallback. Local
    // copies so flow analysis can narrow the nullables inside
    // the setState closure.
    final bw = bestWaypoints;
    final bp = bestPolyline;
    if (bw != null && bp != null) {
      final currentDelta = (picked - _distanceM).abs();
      if (bestDelta < currentDelta) {
        setState(() {
          _waypoints
            ..clear()
            ..addAll(bw);
          _polyline = bp;
          _distanceM = bestDistance;
          _overlapSpans = detectOverlapSpans(bp);
        });
        unawaited(_refreshElevation());
      }
    }
  }

  /// Prompt the user for a target distance. Returns metres, or null
  /// if cancelled. The unit picker renders in the user's preferred
  /// unit (km / mi) and converts to metres on confirm.
  Future<double?> _pickLoopDistance(DistanceUnit unit) async {
    // Delegated to a StatefulWidget so the TextEditingController is
    // owned by a state object — its lifecycle is framework-managed
    // (init in initState, freed in dispose). Pre-fix the controller
    // was constructed inline in the dialog builder and disposed
    // manually AFTER `await showDialog` returned; that ordering
    // tripped Flutter's `_dependents.isEmpty` assertion when the
    // user tapped Generate (the controller still had a dangling
    // listener from the popped TextField's deferred disposal).
    return showDialog<double>(
      context: context,
      builder: (ctx) => _GenerateLoopDialog(unit: unit),
    );
  }

  void _clear() {
    if (_routing || _saving) return;
    _segmentCache.clear();
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
      showTopBanner(
          context, AppLocalizations.of(context).routeBuilderSaveNeedTwo);
      return;
    }
    final result = await showDialog<SaveDialogResult>(
      context: context,
      builder: (_) => SaveRouteDialog(
        clubChoices: _clubChoices,
        initialClubId: widget.initialClubId,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    final route = cm.Route(
      id: const Uuid().v4(),
      // Stamp the signed-in user's id when available so route-detail
      // / share / kudos surfaces that branch on owner-vs-viewer can
      // recognise the freshly-built route as "mine" before the cloud
      // round-trip stamps it server-side. Falls back to '' for
      // signed-out builds (the route still saves locally; the detail
      // screen's empty-ownerId branch picks it up).
      userId: widget.apiClient.userId ?? '',
      name: result.name,
      waypoints: _polyline,
      distanceMetres: _distanceM,
      elevationGainMetres: _elevationGainM,
      isPublic: result.isPublic,
      surface: _surfaceFor(_mode),
      description: result.description,
      clubId: result.clubId,
    );
    // Local-first save. The route lands on disk (unsynced) BEFORE we
    // attempt the cloud push, so a signed-out / offline / Supabase-
    // init-failed state can never lose the route the user just spent
    // a few minutes building. SyncService drains unsynced routes on
    // the next connectivity flap / app foreground / manual Sync chip.
    await widget.routeStore.save(route);

    final cloudSave = widget.saveRouteFn ?? widget.apiClient.saveRoute;
    try {
      await cloudSave(route);
      await widget.routeStore.markRouteSynced(route.id);
      if (!mounted) return;
      Navigator.of(context).pop<cm.Route>(route);
    } catch (e) {
      // Local copy is already on disk — surface a non-blocking note
      // so the user knows it'll sync later, then proceed as if the
      // save succeeded. Beats yelling about a sign-in / network
      // issue at someone who just wants to capture the route they
      // built.
      if (!mounted) return;
      showTopBanner(
        context,
        AppLocalizations.of(context)
            .routeBuilderSavedLocally(formatSaveRouteError(e, context)),
      );
      Navigator.of(context).pop<cm.Route>(route);
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
      showTopBanner(context,
          AppLocalizations.of(context).routeBuilderLocationUnavailable('$e'));
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
    if (_saving) return;
    setState(() => _dragIndex = _dragIndex == index ? null : index);
  }

  /// Tap on a marker while a different marker is in drag mode →
  /// move the dragged marker to that marker's exact position.
  /// Skips the 5 m dedupe (the user deliberately chose to place the
  /// dragged marker on top of the tapped one — it's explicit
  /// intent, not a fat-finger accident).
  Future<void> _placeOverMarker(int tappedIndex) async {
    if (_saving) return;
    final draggedIdx = _dragIndex;
    if (draggedIdx == null || draggedIdx == tappedIndex) return;
    // Snapshot the tapped marker's position BEFORE clearing the
    // drag index, then build the new waypoints list with the
    // dragged marker relocated. The 5 m dedupe is intentionally
    // skipped — see method kdoc.
    final target = _waypoints[tappedIndex];
    setState(() => _dragIndex = null);
    final next = List<cm.Waypoint>.from(_waypoints);
    next[draggedIdx] = target;
    await _rerouteThrough(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
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

    // AppBar actions: when the search field is focused (keyboard
    // up + actively typing), condense everything except Save into
    // a single overflow (`⋮`) menu so the search TextField gets
    // the full title width. Pre-polish the 4 visible action icons
    // ate ~half the AppBar — the user reported "the search bar is
    // super tiny and only shows 1 letter when I'm typing." When
    // the search isn't focused, all 4 affordances stay visible
    // (most actions get used while building, not while searching).
    final canUndo = _waypoints.isNotEmpty && !_routing && !_saving;
    final canClear = _waypoints.isNotEmpty && !_routing && !_saving;
    final canGenerate = !_routing && !_saving;
    final canSave = _polyline.length >= 2 && !_routing && !_saving;
    final compactActions = _searchFocused;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtl,
          focusNode: _searchFocus,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: l10n.routeBuilderSearchHint,
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search, size: 20),
          ),
          style: theme.textTheme.bodyLarge,
        ),
        actions: compactActions
            ? [
                // Compact mode while searching: just Save +
                // overflow. The search field claims everything
                // else.
                TextButton(
                  onPressed: canSave ? _save : null,
                  child: Text(
                      _saving ? l10n.routeBuilderSaving : l10n.routeBuilderSave),
                ),
                PopupMenuButton<String>(
                  tooltip: l10n.routeBuilderMore,
                  onSelected: (a) {
                    switch (a) {
                      case 'loop':
                        if (canGenerate) _generateLoop();
                      case 'undo':
                        if (canUndo) _undo();
                      case 'clear':
                        if (canClear) _clear();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'loop',
                      enabled: canGenerate,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.all_inclusive),
                        title: Text(l10n.routeBuilderGenerateLoop),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'undo',
                      enabled: canUndo,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.undo),
                        title: Text(l10n.routeBuilderUndo),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'clear',
                      enabled: canClear,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.delete_outline),
                        title: Text(l10n.routeBuilderClear),
                      ),
                    ),
                  ],
                ),
              ]
            : [
                IconButton(
                  tooltip: l10n.routeBuilderGenerateLoop,
                  onPressed: canGenerate ? _generateLoop : null,
                  // Was Icons.refresh_outlined — looked like a retry
                  // / reload button. Icons.all_inclusive reads as
                  // "build a circular route" at a glance.
                  icon: const Icon(Icons.all_inclusive),
                ),
                IconButton(
                  tooltip: l10n.routeBuilderUndo,
                  onPressed: canUndo ? _undo : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: l10n.routeBuilderClear,
                  onPressed: canClear ? _clear : null,
                  icon: const Icon(Icons.delete_outline),
                ),
                TextButton(
                  onPressed: canSave ? _save : null,
                  child: Text(
                      _saving ? l10n.routeBuilderSaving : l10n.routeBuilderSave),
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
                        // Bigger marker hit-box + tap-area for the
                        // marker that's currently being dragged —
                        // makes it obvious where the "lifted" pin is
                        // and easier to tap to drop / cancel.
                        width: _dragIndex == i ? 56 : 36,
                        height: _dragIndex == i ? 56 : 36,
                        child: GestureDetector(
                          // Long-press = pick up this marker (or drop
                          // it if it's already picked up).
                          onLongPress: () => _toggleDragOn(i),
                          // Tap behaviour depends on drag state:
                          //   - no drag active → no-op (clean map
                          //     gestures stay in charge)
                          //   - this marker is dragged → tap drops it
                          //     (cancel-drag affordance)
                          //   - a DIFFERENT marker is dragged → tap
                          //     places the dragged marker at this
                          //     marker's exact position ("place over
                          //     another marker" — the user's
                          //     described intent)
                          onTap: _dragIndex == null
                              ? null
                              : _dragIndex == i
                                  ? () => _toggleDragOn(i)
                                  : () => _placeOverMarker(i),
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
              onDeleteDragged: _deleteSelectedWaypoint,
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
          // than the Locate FAB. **Hidden while the search field is
          // focused** — when the keyboard is up + the search-
          // results dropdown is open below the AppBar, the toggle
          // was overlapping the bottom of the dropdown.
          // The user reported "Trail, Road and Straight buttons
          // cover some of the dropdowns for the search results."
          if (!_searchFocused)
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
                        // Re-route through existing waypoints when
                        // the mode changes — the polyline shape
                        // depends on the OSRM profile.
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
        tooltip: l10n.routeBuilderLocateMe,
        onPressed: _routing || _saving ? null : _locate,
        child: const Icon(Icons.my_location),
      ),
    );
  }
}

/// Available routing profiles surfaced to the user. Maps to
/// [OsrmProfile] for road/trail and bypasses OSRM for straight.
enum RouteBuilderMode { trail, road, straight }

String _modeLabel(AppLocalizations l10n, RouteBuilderMode m) => switch (m) {
      RouteBuilderMode.trail => l10n.routeBuilderModeTrail,
      RouteBuilderMode.road => l10n.routeBuilderModeRoad,
      RouteBuilderMode.straight => l10n.routeBuilderModeStraight,
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
String formatSaveRouteError(Object e, [BuildContext? context]) {
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
    return context != null
        ? AppLocalizations.of(context).routeBuilderServerUnreachable
        : "Can't reach the server. Sign in or check your connection and try again.";
  }
  return context != null
      ? AppLocalizations.of(context).routeBuilderSaveFailed('$e')
      : 'Save failed: $e';
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
  final VoidCallback onDeleteDragged;

  const _StatusPill({
    required this.distanceM,
    required this.elevationGainM,
    required this.routing,
    required this.saving,
    required this.waypointCount,
    required this.mode,
    required this.dragIndex,
    required this.onCancelDrag,
    required this.onDeleteDragged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    String label;
    if (dragIndex != null) {
      // Pinning the affordance hierarchy: PRIMARY action is move,
      // SECONDARY is delete, TERTIARY is cancel. The label leads with
      // "Tap anywhere" because that's the move gesture; the two
      // icons cover the other two intents.
      label = l10n.routeBuilderTapToMovePoint(dragIndex! + 1);
    } else if (waypointCount == 0) {
      // Surface the current routing mode in the empty hint so flipping
      // Trail / Road / Straight gives immediate visual feedback even
      // before the user places two waypoints (otherwise the mode
      // toggle looks dead until there's a polyline to reshape).
      label = l10n.routeBuilderEmptyHint(_modeLabel(l10n, mode));
    } else if (waypointCount == 1) {
      // One waypoint placed — same rationale: show the mode so the
      // user can compose the toggle + next tap with confidence.
      label = l10n.routeBuilderOnePointHint(_modeLabel(l10n, mode));
    } else {
      final km = formatFixed(distanceM / 1000, 2, activeLocaleTag);
      label = elevationGainM > 0
          ? l10n.routeBuilderStatusGain(
              '$km km', elevationGainM.round(), waypointCount)
          : l10n.routeBuilderStatusNoGain('$km km', waypointCount);
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
          if (dragIndex != null) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: l10n.routeBuilderDeletePoint(dragIndex! + 1),
              color: theme.colorScheme.error,
              onPressed: onDeleteDragged,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: l10n.routeBuilderCancelDrag,
              onPressed: onCancelDrag,
              visualDensity: VisualDensity.compact,
            ),
          ] else if (routing || saving) ...[
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

/// Generate-Loop dialog. Owns its own TextEditingController via a
/// proper State object so the controller's lifecycle is bound to
/// the dialog widget tree — `dispose()` runs when the dialog
/// unmounts (after the pop animation completes), which is what
/// Flutter's ChangeNotifier disposal contract expects.
class _GenerateLoopDialog extends StatefulWidget {
  final DistanceUnit unit;
  const _GenerateLoopDialog({required this.unit});

  @override
  State<_GenerateLoopDialog> createState() => _GenerateLoopDialogState();
}

class _GenerateLoopDialogState extends State<_GenerateLoopDialog> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.unit == DistanceUnit.mi ? '3' : '5',
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctl.text.trim());
    if (v == null || v <= 0) {
      Navigator.pop(context);
      return;
    }
    final metres = widget.unit == DistanceUnit.mi
        ? v * 1609.344
        : v * 1000;
    Navigator.pop(context, metres);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = widget.unit == DistanceUnit.mi ? 'mi' : 'km';
    return AlertDialog(
      title: Text(l10n.routeBuilderGenerateLoop),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.routeBuilderLoopDialogBody,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(suffixText: label),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.routeBuilderCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.routeBuilderGenerate),
        ),
      ],
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
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor),
      ),
      child: SegmentedButton<RouteBuilderMode>(
        // User reported "the text wraps to the next line for Road
        // and Straight items." Default SegmentedButton labels can
        // wrap when the segment width is constrained by the FAB
        // column / map. Pin maxLines=1 + softWrap=false so the
        // labels stay on a single line; the icon stays inline,
        // so a really cramped viewport still reads "🏔 Trail",
        // "🚗 Road", "📏 Straight" each as one chip.
        segments: [
          ButtonSegment(
            value: RouteBuilderMode.trail,
            label: Text(
              l10n.routeBuilderModeTrail,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
            icon: const Icon(Icons.terrain),
          ),
          ButtonSegment(
            value: RouteBuilderMode.road,
            label: Text(
              l10n.routeBuilderModeRoad,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
            icon: const Icon(Icons.directions_car),
          ),
          ButtonSegment(
            value: RouteBuilderMode.straight,
            label: Text(
              l10n.routeBuilderModeStraight,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
            icon: const Icon(Icons.straighten),
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
    // Drag mode bumps the pin from 22→32 dp + adds a coloured
    // shadow so it visibly "lifts" off the map. Without this the
    // only sign you'd entered drag mode was a colour shift the
    // user might not notice.
    final size = widget.isDragging ? 32.0 : 22.0;
    final pin = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: widget.isDragging
            ? const [
                BoxShadow(
                  color: Colors.amber,
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '${widget.index + 1}',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: widget.isDragging ? 14 : 11,
        ),
      ),
    );
    // Two pulsing-halo paths: the start-pin "snap to close loop"
    // affordance (existing) and the new "drag in progress" affordance.
    // Either reuses the same `_pulse` controller so the animation
    // stays coordinated when both ever overlap (shouldn't, because
    // pulseStart gates on `_dragIndex == null`).
    final shouldPulse = widget.pulseStart || widget.isDragging;
    if (!shouldPulse) return pin;
    final ringColor = widget.isDragging ? Colors.amber : Colors.green;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        final t = _pulse.value;
        final ringScale = 1 + 0.7 * t;
        final ringOpacity = (1 - t).clamp(0.0, 1.0);
        return SizedBox(
          width: widget.isDragging ? 56 : 36,
          height: widget.isDragging ? 56 : 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: ringScale,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ringColor.withValues(alpha: 0.30 * ringOpacity),
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

/// One option in the SaveRouteDialog's "Save to" picker. Kept tiny
/// and screen-local so the dialog doesn't take a dependency on
/// `SocialService` / `ClubView` — the caller does the membership
/// lookup and hands in a flat list.
@visibleForTesting
class RouteClubChoice {
  final String id;
  final String name;
  const RouteClubChoice({required this.id, required this.name});
}

/// Result popped by [SaveRouteDialog]. Promoted alongside the dialog so
/// widget tests can pattern-match on the returned shape.
@visibleForTesting
class SaveDialogResult {
  final String name;
  final bool isPublic;
  final String? description;

  /// The club this route is being saved to, or null for "Personal".
  /// Mirrors web's `?club=<id>` URL parameter on `/routes/new`.
  final String? clubId;

  const SaveDialogResult({
    required this.name,
    required this.isPublic,
    this.description,
    this.clubId,
  });
}

/// Save-route modal. Promoted from file-private so the widget test
/// can pump it in isolation rather than mounting the whole builder
/// (which would need a working MapLibre/OSRM/elevation stack).
///
/// When the caller passes a non-empty [clubChoices], the dialog
/// renders a "Save to" dropdown that lets the user choose between
/// Personal (the default) and any club they're a member of. The
/// picker is hidden entirely when the list is empty so users who
/// aren't in any clubs see the same lean dialog as before.
@visibleForTesting
class SaveRouteDialog extends StatefulWidget {
  final List<RouteClubChoice> clubChoices;

  /// Pre-selected club id. Defaults to null (Personal). When the
  /// caller (e.g. the club-detail "Build route" CTA) wants the
  /// picker to open already pointing at a specific club, it passes
  /// that club's id here. The user can still change it.
  final String? initialClubId;

  const SaveRouteDialog({
    super.key,
    this.clubChoices = const [],
    this.initialClubId,
  });
  @override
  State<SaveRouteDialog> createState() => _SaveRouteDialogState();
}

class _SaveRouteDialogState extends State<SaveRouteDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _isPublic = false;
  late String? _clubId;

  @override
  void initState() {
    super.initState();
    // Seed the picker default from the caller's `initialClubId`, but
    // only if it matches one of the available choices — otherwise
    // fall back to Personal so a stale / wrong id can't put the
    // picker into a non-selectable state.
    final candidate = widget.initialClubId;
    final valid = candidate != null &&
        widget.clubChoices.any((c) => c.id == candidate);
    _clubId = valid ? candidate : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasClubs = widget.clubChoices.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.routeBuilderSaveDialogTitle),
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
              decoration: InputDecoration(
                labelText: l10n.routeBuilderNameLabel,
                hintText: l10n.routeBuilderNameHint,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: l10n.routeBuilderDescriptionLabel,
                hintText: l10n.routeBuilderDescriptionHint,
              ),
              maxLines: 3,
            ),
            if (hasClubs) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                key: const Key('save-route-dialog-club-picker'),
                initialValue: _clubId,
                decoration: InputDecoration(
                  labelText: l10n.routeBuilderSaveToLabel,
                ),
                items: <DropdownMenuItem<String?>>[
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.routeBuilderSaveToPersonal),
                  ),
                  for (final c in widget.clubChoices)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name),
                    ),
                ],
                onChanged: (v) => setState(() => _clubId = v),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.routeBuilderMakePublic),
              subtitle: Text(l10n.routeBuilderMakePublicSubtitle),
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.routeBuilderCancel),
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
              clubId: _clubId,
            ));
          },
          child: Text(l10n.routeBuilderSave),
        ),
      ],
    );
  }
}
