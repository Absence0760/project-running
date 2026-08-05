import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, StatGrid, StatTile;

import '../apple_watch_route_bridge.dart';
import '../auth_error.dart';
import '../backend_timeout.dart';
import '../dev_auto_login.dart' show isLocalSupabaseUrl;
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../fab_clearance.dart';
import '../local_route_store.dart';
import '../main.dart' show pendingStartRunWithRoute;
import '../offline_tile_pack.dart';
import '../preferences.dart';
import '../reactive_ble_watch_transport.dart';
import '../route_describe_client.dart';
import '../route_description.dart';
import '../route_geometry.dart' show interpolateAlongRoute;
import '../route_gpx.dart';
import '../roadbook.dart'
    show RoadbookMarker, RoadbookWaypoint, buildRoadbook;
import '../sim_watch_link.dart' show maybeDevBackendUrl;
import '../sim_watch_sync.dart'
    show WatchBleTransport, WatchPushRejected, WatchSyncClient;
import '../social_service.dart' show ClubView, SocialService;
import '../tile_pack.dart' show TileBbox;
import '../watch_course.dart';
import '../watch_roadbook.dart';
import 'roadbook_screen.dart';
import '../widgets/app_bar_actions.dart';
import '../widgets/live_run_map.dart';
import '../widgets/missing_map_tiles_hint.dart';
import '../widgets/report_sheet.dart';
import '../widgets/route_markers_panel.dart';
import '../widgets/route_conditions.dart';
import '../widgets/route_photos.dart';
import '../widgets/route_share_card.dart';
import '../widgets/segments_panel.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';

/// Pure helper — filter the viewer's club memberships down to clubs
/// they can transfer a route into (owner or admin). Mirrors the
/// equivalent helper for plan templates (see `plan_detail_screen.dart`
/// `adminClubsForPublish`); kept distinct so a future change of policy
/// (e.g. event organisers gain transfer rights) doesn't accidentally
/// loosen the publish path too.
@visibleForTesting
List<ClubView> adminClubsForRouteTransfer(Iterable<ClubView> clubs) {
  return clubs.where((c) => c.isAdmin).toList();
}

/// Public share URL for a route — the `/share/route/{id}` page anyone with
/// the link can open (and that deep-links back into the app). Host comes
/// from `WEB_BASE_URL`, falling back to the prod site; trailing slashes are
/// trimmed. Mirrors web's `${origin}/share/route/${id}` in
/// `routes/[id]/+page.svelte`.
String routeShareUrl(String routeId, {String? webBase}) {
  final base = (webBase ??
          (dotenv.isInitialized ? dotenv.maybeGet('WEB_BASE_URL') : null) ??
          'https://threkir.com')
      .trim()
      .replaceAll(RegExp(r'/+$'), '');
  return '$base/share/route/$routeId';
}

class RouteDetailScreen extends StatefulWidget {
  final cm.Route route;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final ApiClient? apiClient;
  /// Whether the current user owns this route. Callers opening from
  /// their own library pass `true`; the Explore tab opens read-only.
  final bool isOwner;

  /// Optional SocialService injection for the transfer-to-club sheet.
  /// When `null`, the screen constructs its own against the global
  /// Supabase client. Tests pass a fake.
  final SocialService? social;

  /// Injectable AI-enhancement call for the "Describe this route"
  /// affordance. Defaults to the real Pro-gated endpoint; tests pass a
  /// stub to exercise the enhance / upgrade / failure paths without a
  /// network or a Supabase session.
  final Future<AiDescriptionResult> Function(RouteDescriptionInput)?
      describeAi;

  /// Injectable Pro check. Defaults to `apiClient.isPro()`; tests pass a
  /// fixed value to drive the Pro vs free branch deterministically.
  final Future<bool> Function()? checkPro;

  /// Backend URL the custom-watch course push is gated on. The watch is
  /// research-tier with no hardware in anyone's hands ([decisions.md § 71]),
  /// so the affordance shows only against a loopback backend — the same rail
  /// the Sim Watch link uses (§ 209). Production reads dotenv; tests pass a
  /// URL to drive either side of the gate.
  final String? devBackendUrl;

  /// Injectable BLE transport for the course push. Defaults to the production
  /// `flutter_reactive_ble` client; tests pass a fake so the push is exercised
  /// with no radio attached.
  final WatchBleTransport Function()? watchTransportFactory;

  const RouteDetailScreen({
    super.key,
    required this.route,
    required this.routeStore,
    required this.preferences,
    this.apiClient,
    this.isOwner = false,
    this.social,
    this.describeAi,
    this.checkPro,
    this.devBackendUrl,
    this.watchTransportFactory,
  });

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  late bool _isPublic = widget.route.isPublic;
  late bool _isStarred = widget.route.isStarred;
  late bool _isOfflinePinned =
      widget.routeStore.isOfflinePinned(widget.route.id);
  late List<String> _tags = List.from(widget.route.tags);

  // Offline map-tile pack for a route the user pins for offline use. Lazily
  // built (device-led, owns its own download lifecycle); the download is a
  // best-effort L4 effect kicked from the pin toggle and never blocks it.
  OfflineTilePackStore? _tilePackStore;
  OfflineTilePackStore get _tilePacks => _tilePackStore ??= OfflineTilePackStore(
        tileUrlTemplate: currentTileUrl(context),
      );
  // Mirrors widget.route.clubId initially so the transfer/detach button
  // can show the current ownership state and `_transferToClub` can
  // refresh it without rebuilding the screen.
  late String? _clubId = widget.route.clubId;
  bool _transferBusy = false;

  // Lazy SocialService — production uses the global Supabase client;
  // tests inject a fake via the constructor.
  late final SocialService _social = widget.social ?? SocialService();
  List<cm.RouteReviewRow> _reviews = [];
  bool _loadingReviews = false;
  bool _reviewsOffline = false;
  double _avgRating = 0;

  bool? _bookmarked;
  bool _bookmarkBusy = false;
  bool _offlinePinBusy = false;
  bool _publicBusy = false;
  bool _starBusy = false;
  bool _watchPushBusy = false;

  /// Whether a paired Apple Watch running the app can take a route push.
  /// Resolved once in [initState] over the native bridge; false on Android
  /// and on an iPhone with no watch, so the menu row never offers a send
  /// that can only fail.
  bool _appleWatchAvailable = false;
  bool _appleWatchPushBusy = false;

  // Waypoints handed to the renderer. For the owner this mirrors
  // widget.route.waypoints from the row; for non-owners this is the
  // privacy-zone-clipped output of clip_route_for_viewer (decisions
  // §33). Bookmarked / public / club-readable routes the viewer
  // doesn't own would otherwise leak the unclipped polyline through
  // LiveRunMap's plannedRoute prop.
  List<cm.Waypoint> _displayWaypoints = const [];

  // Course-marker wiring between RouteMarkersPanel (owns the data) and the
  // LiveRunMap (renders the pins + reports placement / pin taps).
  final GlobalKey<RouteMarkersPanelState> _markersPanelKey = GlobalKey();
  List<MapMarkerPin> _markerPins = const [];
  bool _markerPlacing = false;
  // The map is the first list child and the markers panel sits far below the
  // fold, so "tap the map to place" arrived with no map on screen.
  final ScrollController _scrollController = ScrollController();

  /// 0.0 = start, 1.0 = finish. Drives the route-preview scrubber:
  /// dragging the slider feeds an interpolated lat/lng to the
  /// LiveRunMap as a "runner" pulse marker so the user can preview
  /// the direction + path of the run before they start.
  double _scrubFraction = 0.0;
  /// True while the user has the scrubber thumb under their finger
  /// — controls whether the runner marker is mounted on the map.
  /// Released the thumb → marker fades out so the static route
  /// preview is the default state.
  bool _scrubbing = false;

  bool get _isOwner => widget.isOwner && widget.apiClient?.userId != null;

  // "Describe this route" affordance. The templated description is the
  // always-works baseline (computed locally, no network); Pro users can
  // enhance it into an AI-written paragraph. `_genDescription` holds the
  // generated text (separate from `route.description`, the stored one);
  // `_genSource` tracks whether it came from the model. Only surfaced
  // when the route has no stored description, mirroring web.
  String? _genDescription;
  String? _genSource;
  bool _describing = false;
  bool _describeFailed = false;
  bool _showUpgradeHint = false;

  @override
  void initState() {
    super.initState();
    _fetchReviews();
    _loadBookmarkState();
    _resolveDisplayWaypoints();
    _resolveAppleWatchAvailability();
  }

  Future<void> _resolveAppleWatchAvailability() async {
    final available = await AppleWatchRouteBridge.isAvailable();
    if (!mounted || !available) return;
    setState(() => _appleWatchAvailable = true);
  }

  @override
  void dispose() {
    _tilePackStore?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll the map back into view. Course-marker placement is driven from
  /// the panel below the fold but happens ON the map, so the instruction is
  /// useless until the map is visible. L4: a scroll failure must not stop the
  /// placement itself.
  void _revealMap() {
    if (!_scrollController.hasClients) return;
    try {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (e) {
      debugPrint('route detail: reveal map for marker placement failed: $e');
    }
  }

  Future<void> _resolveDisplayWaypoints() async {
    final api = widget.apiClient;
    final viewerId = api?.userId;
    final ownerId = widget.route.userId;
    // Owner / direct-owner-bypass surface keeps the row's waypoints —
    // RPC at render time would round-trip and an outage would blank
    // the owner's own map.
    //
    // **Locally-built routes** carry an empty `userId` until the next
    // SyncService cycle pushes them to the cloud (the `Route`
    // constructor defaults to `userId = ''`). Treat empty-ownerId as
    // "owned by the current viewer" so the user can preview the route
    // they just saved without waiting for sync to land. Without this,
    // opening a freshly-built route shows "Waiting for GPS..." instead
    // of the polyline — the user's report.
    if (viewerId != null && (viewerId == ownerId || ownerId.isEmpty)) {
      setState(() => _displayWaypoints = widget.route.waypoints);
      return;
    }
    // Signed-out viewer looking at a locally-built route — same
    // logic, no cloud row to clip against. Use the row waypoints.
    if (viewerId == null && ownerId.isEmpty) {
      setState(() => _displayWaypoints = widget.route.waypoints);
      return;
    }
    // Non-owner (incl. anon api == null): fetch clipped output. The
    // helper fails closed — an RPC error renders an empty map rather
    // than fall through to the unclipped row column.
    if (api == null) {
      setState(() => _displayWaypoints = const []);
      return;
    }
    try {
      final clipped = await api.clipRouteForViewer(widget.route.id);
      if (!mounted) return;
      setState(() => _displayWaypoints = clipped);
    } catch (e) {
      debugPrint('clipRouteForViewer failed for ${widget.route.id}: $e');
      if (mounted) setState(() => _displayWaypoints = const []);
    }
  }

  /// Map the loaded route into the describer's input shape. Endpoints
  /// come from the first/last displayed waypoint so loop detection works
  /// for non-owners too (they get the clipped trace, which still starts
  /// and ends at the route's real endpoints unless a privacy zone
  /// clipped them — in which case point-to-point is the safe default).
  RouteDescriptionInput _describeInput() {
    final wps = _displayWaypoints;
    return RouteDescriptionInput(
      name: widget.route.name,
      distanceM: widget.route.distanceMetres,
      elevationM: widget.route.elevationGainMetres,
      surface: widget.route.surface,
      start: wps.isNotEmpty ? LatLng(wps.first.lat, wps.first.lng) : null,
      end: wps.length > 1 ? LatLng(wps.last.lat, wps.last.lng) : null,
    );
  }

  /// Build the localised, unit-aware templated description from the
  /// structured parts. The always-works L1 baseline — instant, no
  /// network — and the floor the AI path falls back to. Mirrors web's
  /// `localisedTemplate` (apps/web/src/lib/routes/route_description.ts):
  /// distance + gain run through the unit-aware formatters; every word is
  /// translated via the ARB catalogue.
  String _localisedTemplate(
    RouteDescriptionParts parts,
    String name,
    AppLocalizations l10n,
    DistanceUnit unit,
  ) {
    final shape = switch (parts.shape) {
      RouteShape.loop => l10n.routeDetailDescShapeLoop,
      RouteShape.outAndBack => l10n.routeDetailDescShapeOutAndBack,
      RouteShape.pointToPoint => l10n.routeDetailDescShapePointToPoint,
    };
    final surface = switch (parts.surface) {
      'road' => l10n.routeDetailDescSurfaceRoad,
      'trail' => l10n.routeDetailDescSurfaceTrail,
      'mixed' => l10n.routeDetailDescSurfaceMixed,
      _ => null,
    };
    final distance = UnitFormat.distance(parts.distanceM, unit);
    final sentence = surface != null
        ? l10n.routeDetailDescSentence(name, distance, surface, shape)
        : l10n.routeDetailDescSentenceNoSurface(name, distance, shape);
    if (parts.elevationM > 0) {
      final elevation = switch (parts.elevation) {
        ElevationProfile.flat => l10n.routeDetailDescElevFlat,
        ElevationProfile.rolling => l10n.routeDetailDescElevRolling,
        ElevationProfile.hilly => l10n.routeDetailDescElevHilly,
        ElevationProfile.mountainous => l10n.routeDetailDescElevMountainous,
      };
      final climb = l10n.routeDetailDescClimb(
        UnitFormat.elevation(parts.elevationM, unit),
        elevation,
        l10n.routeDetailDescPerKm(parts.gainPerKm),
      );
      return '$sentence $climb';
    }
    return '$sentence ${l10n.routeDetailDescFlat}';
  }

  /// Generate a description. Always shows the templated baseline first
  /// (instant, offline), then — for Pro users — asks the server to
  /// enhance it. A free user's request short-circuits to the upgrade
  /// hint without a network call. Any hard failure (network / non-200)
  /// leaves the templated text in place and shows a non-blocking error;
  /// the baseline is never lost. Fail-closed: an unknown Pro state is
  /// treated as not-Pro, so a check failure shows templated-only.
  Future<void> _describe() async {
    if (_describing) return;
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    setState(() {
      _describing = true;
      _describeFailed = false;
      _showUpgradeHint = false;
    });

    final input = _describeInput();
    final parts = describeRoute(input);
    // L1 baseline: render the localised templated sentence immediately.
    setState(() {
      _genDescription = _localisedTemplate(parts, input.name, l10n, unit);
      _genSource = 'template';
    });

    var isPro = false;
    try {
      isPro = await (widget.checkPro?.call() ??
          widget.apiClient?.isPro() ??
          Future.value(false));
    } catch (e) {
      debugPrint('route_detail: isPro check failed: $e');
      isPro = false;
    }

    if (!isPro) {
      if (mounted) {
        setState(() {
          _showUpgradeHint = true;
          _describing = false;
        });
      }
      return;
    }

    try {
      final ai =
          await (widget.describeAi ?? requestAiDescription)(input);
      if (!mounted) return;
      setState(() {
        _genDescription = ai.description;
        _genSource = ai.source;
        _showUpgradeHint = ai.upgrade;
      });
    } catch (e) {
      debugPrint('route_detail: requestAiDescription failed: $e');
      if (mounted) setState(() => _describeFailed = true);
    } finally {
      if (mounted) setState(() => _describing = false);
    }
  }

  /// The "Describe this route" surface shown when the route has no
  /// stored description. Before generation: a single button. After: the
  /// generated text, an AI-attribution line (when the model produced it),
  /// the Pro upgrade hint (free users / server upgrade signal), and a
  /// non-blocking error line that never replaces the baseline.
  Widget _describeBlock(ThemeData theme, AppLocalizations l10n) {
    if (_genDescription == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _describing ? null : _describe,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: Text(_describing
              ? l10n.routeDetailDescribing
              : l10n.routeDetailDescribe),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.routeDetailDescriptionHeading,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _genDescription!,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
        if (_genSource == 'ai')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    l10n.routeDetailAiAttribution,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_showUpgradeHint)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.routeDetailEnhanceUpgradeHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (_describeFailed)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.routeDetailDescribeFailed,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _loadBookmarkState() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null || widget.isOwner) return;
    try {
      final saved = await api.isRouteBookmarked(widget.route.id);
      if (!mounted) return;
      setState(() => _bookmarked = saved);
    } catch (e) {
      // Best-effort; the toggle still falls through.
      debugPrint('isRouteBookmarked failed for ${widget.route.id}: $e');
    }
  }

  Future<void> _toggleBookmark() async {
    final api = widget.apiClient;
    if (api == null || _bookmarkBusy) return;
    if (!await ensureSignedIn(context,
        viewerId: api.userId, api: api, onSignedIn: _loadBookmarkState)) {
      return;
    }
    if (!mounted) return;
    final before = _bookmarked ?? false;
    setState(() {
      _bookmarkBusy = true;
      _bookmarked = !before;
    });
    try {
      if (before) {
        await api.unbookmarkRoute(widget.route.id);
      } else {
        await api.bookmarkRoute(widget.route.id);
      }
    } catch (e) {
      debugPrint('route detail bookmark failed: $e');
      if (!mounted) return;
      setState(() => _bookmarked = before);
      showTopBanner(
          context, AppLocalizations.of(context).routeDetailBookmarkFailed(friendlyError(AppLocalizations.of(context), e)));
    } finally {
      if (mounted) setState(() => _bookmarkBusy = false);
    }
  }

  Future<void> _fetchReviews() async {
    final api = widget.apiClient;
    if (api == null) return;
    setState(() => _loadingReviews = true);
    try {
      final reviews = await api.getRouteReviews(widget.route.id);
      if (!mounted) return;
      setState(() {
        _reviews = reviews;
        _avgRating = reviews.isEmpty
            ? 0
            : reviews.map((r) => r.rating).reduce((a, b) => a + b) /
                reviews.length;
        _loadingReviews = false;
      });
    } catch (e) {
      debugPrint('getRouteReviews failed for ${widget.route.id}: $e');
      if (mounted) {
        setState(() {
          _loadingReviews = false;
          _reviewsOffline = true;
        });
      }
    }
  }

  Future<void> _togglePublic() async {
    // Serialize taps: a rapid on→off→on would otherwise fire overlapping
    // setRoutePublic calls that can land out of order, leaving the server on
    // one value while the UI shows the other.
    if (_publicBusy) return;
    final newValue = !_isPublic;
    final r = widget.route;
    cm.Route buildRoute(bool isPublic) => cm.Route(
          id: r.id,
          userId: r.userId,
          name: r.name,
          waypoints: r.waypoints,
          distanceMetres: r.distanceMetres,
          elevationGainMetres: r.elevationGainMetres,
          isPublic: isPublic,
          createdAt: r.createdAt,
          surface: r.surface,
          tags: _tags,
          featured: r.featured,
          runCount: r.runCount,
          isStarred: _isStarred,
          description: r.description,
        );
    // Same offline-tolerant pattern as `_toggleStar`: write the
    // local store first so the toggle is durable across the
    // signed-out / network-down / cloud-not-ready paths. Pre-fix,
    // _togglePublic bailed entirely when signed-out and rolled
    // back local state on any cloud error — locally-built routes
    // (which can't have a cloud row yet) could never be made
    // public until after the next sync, which wasn't obvious.
    setState(() {
      _publicBusy = true;
      _isPublic = newValue;
    });
    try {
      await widget.routeStore.save(buildRoute(newValue));
      final api = widget.apiClient;
      if (api == null || api.userId == null) {
        // Signed-out / no api → local-only is the right answer; the
        // route's `isPublic` flag rides through the next
        // SyncService cycle's `saveRoute` push (the route's still in
        // `unsyncedRoutes`).
        if (mounted) {
          showTopBanner(
            context,
            newValue
                ? AppLocalizations.of(context).routeDetailPublicWillSync
                : AppLocalizations.of(context).routeDetailPrivateWillSync,
          );
        }
        return;
      }
      try {
        await api.setRoutePublic(widget.route.id, newValue);
      } catch (e) {
        debugPrint('route detail visibility failed: $e');
        // Roll back local state to match what cloud thinks. Surface
        // the error so the user knows the toggle didn't persist
        // cloud-side. The route stays in the unsynced queue if it
        // was locally-built so the SyncService will retry the
        // saveRoute push on the next cycle.
        if (mounted) {
          setState(() => _isPublic = !newValue);
          await widget.routeStore.save(buildRoute(!newValue));
          showTopBanner(context,
              AppLocalizations.of(context).routeDetailVisibilityFailed(friendlyError(AppLocalizations.of(context), e)));
        }
      }
    } finally {
      if (mounted) setState(() => _publicBusy = false);
    }
  }

  Future<void> _toggleOfflinePin() async {
    // Serialize taps: without this, a rapid pin→unpin→pin races a tile-pack
    // download (kicked on pin) against its own delete (kicked on unpin) for
    // the same route id, which can leave a half-written or orphaned pack.
    if (_offlinePinBusy) return;
    final id = widget.route.id;
    final next = !_isOfflinePinned;
    setState(() {
      _offlinePinBusy = true;
      _isOfflinePinned = next;
    });
    try {
      if (next) {
        // Make sure the JSON file is actually on disk — for a non-owner
        // viewer who only ever saw the route via the Explore tab, the
        // detail row may not yet be persisted locally. Mark synced so
        // the SyncService doesn't try to push someone else's route up.
        await widget.routeStore.save(widget.route, markSynced: true);
        await widget.routeStore.pinOffline(id);
        _downloadTilePack();
      } else {
        await widget.routeStore.unpinOffline(id);
        // Best-effort — never block the pin toggle on a disk delete (L4).
        unawaited(_tilePacks.deletePack(id).catchError(
            (Object e) => debugPrint('tile-pack delete failed: $e')));
      }
      if (mounted) {
        showTopBanner(
          context,
          next
              ? AppLocalizations.of(context).routeDetailOfflineSaved
              : AppLocalizations.of(context).routeDetailOfflineRemoved,
        );
      }
    } finally {
      if (mounted) setState(() => _offlinePinBusy = false);
    }
  }

  /// Kick a best-effort offline tile-pack download for the pinned route. L4:
  /// the whole effect is fire-and-forget and swallow-on-fail — a failed or
  /// partial pack never breaks the pin or the online map (decisions §170).
  void _downloadTilePack() {
    final wps = widget.route.waypoints;
    if (wps.length < 2) return;
    var minLat = wps.first.lat, maxLat = wps.first.lat;
    var minLng = wps.first.lng, maxLng = wps.first.lng;
    for (final w in wps) {
      if (w.lat < minLat) minLat = w.lat;
      if (w.lat > maxLat) maxLat = w.lat;
      if (w.lng < minLng) minLng = w.lng;
      if (w.lng > maxLng) maxLng = w.lng;
    }
    final bbox = TileBbox(
      minLat: minLat,
      minLng: minLng,
      maxLat: maxLat,
      maxLng: maxLng,
    );
    unawaited(_tilePacks.downloadPack(widget.route.id, bbox).catchError(
        (Object e) => debugPrint('tile-pack download failed: $e')));
  }

  Future<void> _toggleStar() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    if (_starBusy) return;
    final newValue = !_isStarred;
    final r = widget.route;
    cm.Route buildRoute(bool starred) => cm.Route(
          id: r.id,
          userId: r.userId,
          name: r.name,
          waypoints: r.waypoints,
          distanceMetres: r.distanceMetres,
          elevationGainMetres: r.elevationGainMetres,
          isPublic: _isPublic,
          createdAt: r.createdAt,
          surface: r.surface,
          tags: _tags,
          featured: r.featured,
          runCount: r.runCount,
          isStarred: starred,
          description: r.description,
        );
    setState(() {
      _starBusy = true;
      _isStarred = newValue;
    });
    try {
      await widget.routeStore.save(buildRoute(newValue));
      try {
        await api.setRouteStar(r.id, newValue);
      } catch (e) {
        debugPrint('route detail star failed: $e');
        if (mounted) setState(() => _isStarred = !newValue);
        await widget.routeStore.save(buildRoute(!newValue));
        if (mounted) {
          showTopBanner(
              context, AppLocalizations.of(context).routeDetailStarFailed(friendlyError(AppLocalizations.of(context), e)));
        }
      }
    } finally {
      if (mounted) setState(() => _starBusy = false);
    }
  }

  Future<void> _submitReview() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      showTopBanner(
          context, AppLocalizations.of(context).routeDetailSignInToReview);
      return;
    }

    int selectedRating = 4;
    final commentCtl = TextEditingController();

    final existing = _reviews
        .where((r) => r.userId == api.userId)
        .firstOrNull;
    if (existing != null) {
      selectedRating = existing.rating;
      commentCtl.text = existing.comment ?? '';
    }

    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.routeDetailRateDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return IconButton(
                    tooltip: AppLocalizations.of(context).routeDetailRateStars(star),
                    icon: Icon(
                      star <= selectedRating
                          ? Icons.star
                          : Icons.star_border,
                      color: AppSemanticColors.of(context).crown,
                      size: 32,
                    ),
                    onPressed: () =>
                        setDialogState(() => selectedRating = star),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentCtl,
                decoration: InputDecoration(
                  labelText: l10n.routeDetailCommentLabel,
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.routeDetailCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.routeDetailSubmit),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      await api.upsertRouteReview(
        routeId: widget.route.id,
        rating: selectedRating,
        comment: commentCtl.text.trim().isEmpty
            ? null
            : commentCtl.text.trim(),
      );
      await _fetchReviews();
    } catch (e) {
      debugPrint('route detail review failed: $e');
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).routeDetailReviewFailed(friendlyError(AppLocalizations.of(context), e)));
      }
    }
  }

  /// Delete the viewer's own review. Scoped by (route_id, user_id) inside
  /// the client rather than by review id, so the call can't be aimed at
  /// another user's row; the route_reviews delete RLS policy is the hard
  /// gate behind it.
  Future<void> _deleteOwnReview() async {
    final api = widget.apiClient;
    if (api == null) return;

    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.routeDetailDeleteReviewTitle),
        content: Text(l10n.routeDetailDeleteReviewBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.routeDetailCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppSemanticColors.of(ctx).danger,
              foregroundColor: AppSemanticColors.of(ctx).onDanger,
            ),
            child: Text(l10n.routeDetailDeleteReviewCta),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await api.deleteRouteReview(widget.route.id);
      await _fetchReviews();
    } catch (e) {
      debugPrint('route detail review delete failed: $e');
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).routeDetailReviewDeleteFailed(friendlyError(AppLocalizations.of(context), e)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    final route = widget.route;
    // Surface the primary "Start run" CTA as a floating action
    // button so it's always reachable — pre-polish it lived at the
    // very bottom of the ListView, after description / surface /
    // tags / segments / reviews, so the user had to scroll past
    // every detail panel to actually start a run with the route.
    // Hidden when the polyline is empty (clipped-to-empty privacy
    // outcome) — nothing meaningful to start.
    final canStartRun = _displayWaypoints.length >= 2;
    return Scaffold(
      floatingActionButton: canStartRun
          ? FloatingActionButton.extended(
              heroTag: 'route_detail_start_run',
              // Hand off through the global notifier (HomeScreen listens and
              // routes into the recorder + pops back to the shell) instead of
              // popping the route back to the caller. The old pop relied on
              // whoever pushed this screen handling the returned route, so
              // Start silently did nothing from any pusher that didn't — the
              // shared-file import landing, a deep push, etc.
              onPressed: () => pendingStartRunWithRoute.value = route,
              backgroundColor: semantic.success,
              foregroundColor: semantic.onSuccess,
              icon: const Icon(Icons.play_arrow),
              label: Text(
                l10n.routeDetailStartRun,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : null,
      appBar: AppBar(
        title: Text(route.name),
        // Six concurrent owner actions left a measured 0dp of a 360dp toolbar
        // for the route's name. Share stays pinned (it is itself a menu, and
        // menus don't nest), one action earns the remaining slot, the rest
        // fold into the overflow — the policy `run_detail_screen` follows.
        actions: [
          AppBarActions(
            pinned: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.ios_share),
                tooltip: l10n.routeDetailShare,
                onSelected: (fmt) => switch (fmt) {
                  'link' => _shareLink(context),
                  'watch' => _sendCourseToWatch(),
                  'apple_watch' => _sendRouteToAppleWatch(),
                  _ => _shareAs(context, fmt),
                },
                itemBuilder: (_) => [
                  // "Share link" is the intuitive send-to-someone path: it
                  // hands the public /share/route/[id] URL to the OS share
                  // sheet. Shown only when the route is already public or the
                  // viewer owns it (an owner's tap flips it public first) —
                  // otherwise the link would resolve to nothing for the
                  // recipient.
                  if (_isPublic || _isOwner)
                    PopupMenuItem(
                        value: 'link', child: Text(l10n.routeDetailShareLink)),
                  PopupMenuItem(
                      value: 'image',
                      child: Text(l10n.routeDetailShareAsImage)),
                  PopupMenuItem(
                      value: 'gpx', child: Text(l10n.routeDetailShareAsGpx)),
                  PopupMenuItem(
                      value: 'gpx_markers',
                      child: Text(l10n.routeDetailShareAsGpxMarkers)),
                  PopupMenuItem(
                      value: 'kml', child: Text(l10n.routeDetailShareAsKml)),
                  // The custom watch is research-tier with no unit in a
                  // runner's hands, so this stays behind the loopback-backend
                  // rail the Sim Watch link uses rather than promising every
                  // user a device that does not exist (decisions §71, §209).
                  if (_watchPushAvailable && !_watchPushBusy)
                    PopupMenuItem(
                        value: 'watch',
                        child: Text(l10n.routeDetailSendToWatch)),
                  if (_appleWatchAvailable && !_appleWatchPushBusy)
                    PopupMenuItem(
                        value: 'apple_watch',
                        child: Text(l10n.routeDetailSendToAppleWatch)),
                ],
              ),
            ],
            actions: [
              // A viewer who does not own the route came to keep it, so the
              // bookmark leads for them; an owner already has it and reaches
              // for the offline pin before a run instead.
              if (!widget.isOwner &&
                  widget.apiClient != null &&
                  widget.apiClient!.userId != null)
                AppBarAction(
                  icon: Icon(
                    (_bookmarked ?? false)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                  ),
                  label: (_bookmarked ?? false)
                      ? l10n.routeDetailRemoveBookmark
                      : l10n.routeDetailBookmarkRoute,
                  onPressed: _bookmarkBusy ? null : _toggleBookmark,
                ),
              // Offline-pin affordance — local-only flag (never synced).
              // Also surfaces an inline tile below for discoverability.
              AppBarAction(
                icon: Icon(_isOfflinePinned
                    ? Icons.download_done
                    : Icons.download_outlined),
                iconColor: _isOfflinePinned
                    ? semantic.success
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                label: _isOfflinePinned
                    ? l10n.routeDetailRemoveOfflineSave
                    : l10n.routeDetailSaveForOffline,
                onPressed: _offlinePinBusy ? null : _toggleOfflinePin,
              ),
              if (_isOwner)
                AppBarAction(
                  icon: Icon(_isStarred ? Icons.star : Icons.star_border),
                  iconColor: _isStarred
                      ? semantic.crown
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  label: _isStarred
                      ? l10n.routeDetailUnstarRoute
                      : l10n.routeDetailStarForWatch,
                  onPressed: _starBusy ? null : _toggleStar,
                ),
              // Show the visibility toggle whenever the local store
              // considers the viewer to own this route — regardless of
              // signed-in state. _togglePublic itself handles the
              // signed-out path (writes local + queues for sync) so the
              // user surfaces the affordance they expect to see and
              // ALSO doesn't lose the toggle on a network hiccup.
              if (widget.isOwner)
                AppBarAction(
                  icon: Icon(_isPublic ? Icons.public : Icons.public_off),
                  label: _isPublic
                      ? l10n.routeDetailMakePrivate
                      : l10n.routeDetailMakePublic,
                  onPressed: _publicBusy ? null : _togglePublic,
                ),
              if (_isOwner)
                AppBarAction(
                  icon: _transferBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_clubId == null
                          ? Icons.group_add_outlined
                          : Icons.group),
                  label: _clubId == null
                      ? l10n.routeDetailTransferToClub
                      : l10n.routeDetailManageClub,
                  onPressed: _transferBusy ? null : _transferToClub,
                ),
              if (!widget.isOwner && widget.apiClient != null)
                AppBarAction(
                  icon: const Icon(Icons.flag_outlined),
                  label: l10n.routeDetailReportRoute,
                  onPressed: () => showReportSheet(
                    context,
                    api: widget.apiClient!,
                    targetKind: 'route',
                    targetId: route.id,
                  ),
                ),
              if (_isOwner)
                AppBarAction(
                  icon: const Icon(Icons.delete_outline),
                  label: l10n.routeDetailDeleteRoute,
                  destructive: true,
                  onPressed: () => _confirmDelete(context),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          controller: _scrollController,
          children: [
            // Keep the map alive across ListView scroll. A bare list child is
            // disposed once it scrolls past the cache extent, tearing down the
            // FlutterMap + MapController; scrolling back rebuilt it from
            // scratch — a visible tile reload plus a jank spike. Keeping it
            // alive also pauses its pulse ticker while off-screen.
            _KeepAliveMap(
              child: SizedBox(
                height: 320,
                child: LiveRunMap(
                  track: const [],
                  plannedRoute: _displayWaypoints,
                  followRunner: false,
                  courseMarkers: _markerPins,
                  markerPlacing: _markerPlacing,
                  onMarkerPlace: (wp) =>
                      _markersPanelKey.currentState?.placeAt(wp),
                  onMarkerTap: (id) =>
                      _markersPanelKey.currentState?.selectMarker(id),
                  // Only mount the preview-runner pulse while the user
                  // is actually scrubbing — releasing the thumb fades
                  // back to the static polyline view so the marker
                  // doesn't sit at the start indefinitely after a
                  // single drag.
                  previewPosition: _scrubbing
                      ? interpolateAlongRoute(
                          _displayWaypoints,
                          _scrubFraction,
                        )
                      : null,
                ),
              ),
            ),
            // Diagnostic for the "I'm still not seeing the map"
            // user report — when `MAPTILER_KEY` isn't set in
            // `.env.local`, the LiveRunMap above renders the
            // polyline on a blank grey backdrop (the tile fetch
            // returns 401 with an empty key). The hint widget
            // surfaces the exact fix-instruction instead of the
            // user having to scroll logs.
            const MissingMapTilesHint(),
            // Route preview scrubber — drag the thumb to see the
            // direction of the run. Hidden when the polyline is too
            // short to interpolate (`< 2` waypoints — clipped-to-
            // empty privacy outcome or a degenerate route).
            if (_displayWaypoints.length >= 2)
              _RoutePreviewScrubber(
                fraction: _scrubFraction,
                totalDistanceM: route.distanceMetres,
                unit: unit,
                onChangeStart: () => setState(() => _scrubbing = true),
                onChanged: (f) => setState(() => _scrubFraction = f),
                onChangeEnd: () => setState(() => _scrubbing = false),
              ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: StatGrid(
                cells: [
                  StatTile.large(
                    label: l10n.routeDetailStatDistance,
                    value: UnitFormat.distanceValue(route.distanceMetres, unit),
                    unit: UnitFormat.distanceLabel(unit),
                  ),
                  StatTile.large(
                    label: l10n.routeDetailStatElevation,
                    value: '${route.elevationGainMetres.round()}',
                    unit: 'm',
                  ),
                  if (_avgRating > 0)
                    StatTile.large(
                      label: l10n.routeDetailStatReviews(_reviews.length),
                      value: formatFixed(_avgRating, 1, activeLocaleTag),
                      unit: '/ 5',
                    )
                  else
                    StatTile.large(
                      label: l10n.routeDetailStatWaypoints,
                      value: '${route.waypoints.length}',
                    ),
                ],
              ),
            ),

            // Inline Visibility row for the route owner — surfaced
            // here in the body (in addition to the AppBar icon) so
            // the affordance is impossible to miss. Pre-fix, users
            // who didn't notice the small globe icon in the AppBar
            // couldn't figure out how to make their routes public
            // on mobile.
            if (widget.isOwner)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Icon(
                        _isPublic ? Icons.public : Icons.lock_outline,
                        size: 20,
                        color: _isPublic
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isPublic
                              ? l10n.routeDetailPublicRoute
                              : l10n.routeDetailPrivateRoute,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    _isPublic
                        ? l10n.routeDetailPublicSubtitle
                        : l10n.routeDetailPrivateSubtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  value: _isPublic,
                  onChanged: _publicBusy ? null : (_) => _togglePublic(),
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Icon(
                      _isOfflinePinned
                          ? Icons.download_done
                          : Icons.download_outlined,
                      size: 20,
                      color: _isOfflinePinned
                          ? semantic.success
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isOfflinePinned
                            ? l10n.routeDetailSavedForOffline
                            : l10n.routeDetailSaveForOfflineTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  _isOfflinePinned
                      ? l10n.routeDetailOfflinePinnedSubtitle
                      : l10n.routeDetailOfflineUnpinnedSubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                value: _isOfflinePinned,
                onChanged: _offlinePinBusy ? null : (_) => _toggleOfflinePin(),
              ),
            ),

            if (route.description != null && route.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.routeDetailDescriptionHeading,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      route.description!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: _describeBlock(theme, l10n),
              ),

            // Surface + run-count + featured metadata. Left-aligned
            // (was centered + orphaned-feeling) and uses the same
            // chip language as the new VerifiedBadge / sync-pill
            // affordances elsewhere.
            if (route.surface != null ||
                route.runCount > 0 ||
                route.featured)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (route.surface != null)
                      _MetaChip(
                        icon: _surfaceIcon(route.surface!),
                        label: _surfaceLabel(l10n, route.surface!),
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    if (route.runCount > 0)
                      _MetaChip(
                        icon: Icons.directions_run,
                        label: l10n.routeDetailRunCount(route.runCount),
                        color: theme.colorScheme.primary,
                      ),
                    if (route.featured)
                      _MetaChip(
                        icon: Icons.star,
                        label: l10n.routeDetailFeatured,
                        color: semantic.crown,
                      ),
                  ],
                ),
              ),

            // Tags — display + owner-only inline editor.
            _RouteTagsRow(
              route: route,
              isOwner: _isOwner,
              apiClient: widget.apiClient,
              onChange: (next) {
                setState(() => _tags = next);
              },
              initialTags: _tags,
            ),

            const Divider(),

            // Course markers — aid stations, cutoffs, crew access, etc.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: RouteMarkersPanel(
                key: _markersPanelKey,
                api: widget.apiClient,
                routeId: route.id,
                isOwner: _isOwner,
                viewerId: widget.apiClient?.userId,
                routeOwnerId: widget.route.userId,
                routeLine: _displayWaypoints,
                onPinsChanged: (pins) {
                  if (mounted) setState(() => _markerPins = pins);
                },
                onPlacingChanged: (placing) {
                  if (!mounted) return;
                  setState(() => _markerPlacing = placing);
                  if (placing) _revealMap();
                },
              ),
            ),
            if (_markerPins.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RoadbookScreen(
                        route: widget.route,
                        waypoints: _displayWaypoints,
                        api: widget.apiClient,
                        preferences: widget.preferences,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: Text(AppLocalizations.of(context).roadbookCrewSheet),
                ),
              ),

            const Divider(),

            // Segments panel — list segments + leaderboards. Owners
            // can create new ones; cascades drop their efforts.
            if (widget.apiClient != null)
              SegmentsPanel(
                api: widget.apiClient!,
                routeId: route.id,
                routeDistanceM: route.distanceMetres,
                // Any signed-in viewer can add a segment (community
                // contribution); only the owner moderates others' segments.
                canCreate: widget.apiClient?.userId != null,
                isRouteOwner: _isOwner,
              ),

            const Divider(),

            // Reviews section
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(l10n.routeDetailReviewsHeading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium),
                  ),
                  TextButton.icon(
                    onPressed: _submitReview,
                    icon: const Icon(Icons.rate_review, size: 18),
                    label: Text(l10n.routeDetailRate),
                  ),
                ],
              ),
            ),

            if (_loadingReviews)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_reviews.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Text(
                  _reviewsOffline
                      ? l10n.routeDetailReviewsOffline
                      : l10n.routeDetailNoReviews,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ..._reviews.map((review) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ...List.generate(
                                  5,
                                  (i) => Icon(
                                    i < review.rating
                                        ? Icons.star
                                        : Icons.star_border,
                                    size: 16,
                                    color: AppSemanticColors.of(context).crown,
                                  ),
                                ),
                                const Spacer(),
                                if (review.createdAt != null)
                                  Text(
                                    formatDateShort(review.createdAt!,
                                        localeToTag(Localizations.localeOf(context))),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                if (widget.apiClient?.userId != null)
                                  if (widget.apiClient!.userId != review.userId)
                                    IconButton(
                                      icon: const Icon(Icons.flag_outlined, size: 16),
                                      tooltip: l10n.routeDetailReportReview,
                                      padding: const EdgeInsets.only(left: 8),
                                      constraints: const BoxConstraints(
                                        minWidth: 48,
                                        minHeight: 48,
                                      ),
                                      color: theme.colorScheme.outline,
                                      onPressed: () => showReportSheet(
                                        context,
                                        api: widget.apiClient!,
                                        targetKind: 'route_review',
                                        targetId: review.id,
                                      ),
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 16),
                                      tooltip: l10n.routeDetailDeleteReview,
                                      padding: const EdgeInsets.only(left: 8),
                                      constraints: const BoxConstraints(
                                        minWidth: 48,
                                        minHeight: 48,
                                      ),
                                      color: theme.colorScheme.outline,
                                      onPressed: _deleteOwnReview,
                                    ),
                              ],
                            ),
                            if (review.comment != null &&
                                review.comment!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(review.comment!,
                                  style: theme.textTheme.bodySmall),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )),

            if (widget.apiClient != null) ...[
              const SizedBox(height: 8),
              RoutePhotos(
                api: widget.apiClient!,
                routeId: widget.route.id,
                routeOwnerId: widget.route.userId,
              ),
              RouteConditions(
                api: widget.apiClient!,
                routeId: widget.route.id,
                routeOwnerId: widget.route.userId,
              ),
            ],

            // Trailing bottom-of-scroll padding so the FAB doesn't
            // sit on top of the last review card.
            SizedBox(height: fabScrollClearance(context)),
          ],
        ),
      ),
    );
  }

  /// Share the route as a link — the intuitive "send this to a follower"
  /// path. Hands the public `/share/route/[id]` URL to the OS share sheet
  /// (pick WhatsApp / a DM / any app). An owner sharing a still-private
  /// route flips it public first (mirrors web's `handleShare`); the menu
  /// only offers this when the route is public or the viewer owns it, so a
  /// non-owner never shares a dead link.
  Future<void> _shareLink(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    if (_isOwner && !_isPublic) {
      // Making a still-private route public exposes it (and its start point)
      // to anyone with the link and in Explore — confirm before that flip.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.routeDetailShareConfirmTitle),
          content: Text(l10n.routeDetailShareConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.routeDetailCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.routeDetailShareConfirmCta),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
      final api = widget.apiClient!;
      try {
        await api.setRoutePublic(widget.route.id, true);
        if (!mounted) return;
        setState(() => _isPublic = true);
        showTopBanner(context, l10n.routeDetailMadePublicForLink);
      } catch (e) {
        if (!mounted) return;
        showTopBanner(context,
            l10n.routeDetailShareLinkFailed(friendlyError(l10n, e)));
        return;
      }
    }
    await Share.share(routeShareUrl(widget.route.id),
        subject: widget.route.name);
  }

  /// Whether the custom-watch course push is offered at all. See
  /// [RouteDetailScreen.devBackendUrl] for why it is gated.
  bool get _watchPushAvailable =>
      isLocalSupabaseUrl(widget.devBackendUrl ?? maybeDevBackendUrl());

  /// Send this route to the paired custom watch as a `CRS1` breadcrumb course
  /// and, when the route has course markers, the `RBK1` race schedule those
  /// markers imply — the last leg of "generate a loop on the phone, follow it
  /// on the wrist".
  ///
  /// The two ride one action because a schedule without its course is close to
  /// useless: every checkpoint is a distance *along the course*, and the
  /// watch's Roadbook / CutoffEta / Fuel pages all read the along-route
  /// position the loaded course provides. Pushing a schedule alone would arm
  /// pages that can never resolve a position.
  ///
  /// Reads the same clipped polyline the map and the GPX exporter do, so a
  /// non-owner sending a public route to their own watch can't carry the
  /// owner's unclipped trace out through the radio (decisions §33).
  ///
  /// A route too dense for the frame is thinned to fit and the runner is told
  /// by how much; a route that cannot be represented at all is refused with a
  /// reason. Neither path quietly sends a partial course — a breadcrumb that
  /// ends early is a wrong answer the watch has no way to notice. The schedule
  /// half is held to the same bar: an over-cap one is reduced deliberately (see
  /// [watchRoadbookFromRoadbook]) and the runner is told what was dropped, or
  /// refused outright when it can't be reduced honestly.
  Future<void> _sendCourseToWatch() async {
    if (_watchPushBusy) return;
    final l10n = AppLocalizations.of(context);
    final course = courseFromWaypoints(_displayWaypoints);
    final points = course.points;
    if (points == null) {
      showTopBanner(context, l10n.routeDetailWatchCourseTooShort);
      return;
    }
    setState(() => _watchPushBusy = true);
    try {
      // Shaped before the radio opens: the schedule half may have to ask the
      // runner for a goal time and a start clock, and a modal answered at
      // leisure would otherwise hold a live BLE connection open behind it.
      final schedule = await _watchRoadbook();
      if (!mounted) return;
      final client = WatchSyncClient(
        transport: (widget.watchTransportFactory ??
            ReactiveBleWatchTransport.new)(),
        // The push path never delivers a run; the sink is the run-sync half of
        // the same client.
        onRun: (_) async {},
      );
      await client.pushCourse(
        chunkCourse(encodeCourse(points, elevationM: course.elevationM)),
      );

      if (schedule?.checkpoints != null) {
        await client.pushRoadbook(chunkRoadbook(
          encodeRoadbook(schedule!.checkpoints!, schedule.cutoffs!),
        ));
      }
      if (!mounted) return;
      showTopBanner(
          context, _watchPushMessage(l10n, course, points.length, schedule));
    } catch (e) {
      if (!mounted) return;
      // A refusal is not a generic failure: the watch answered, and what it
      // said is that it kept the course it had. `friendlyError` classifies
      // AUTH failures, so routing this through it would report "something
      // went wrong" for the one error whose cause is known exactly.
      showTopBanner(
          context,
          e is WatchPushRejected
              ? l10n.routeDetailWatchPushRejected
              : l10n.routeDetailWatchCourseFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _watchPushBusy = false);
    }
  }

  /// Send this route to the paired Apple Watch so its `RouteNavigator` has a
  /// line to follow during a wrist-recorded run — the counterpart of
  /// [_sendCourseToWatch] for the watch a runner actually owns.
  ///
  /// Reads the same clipped polyline the map and the GPX exporter do, so a
  /// non-owner sending a public route to their own watch can't carry the
  /// owner's unclipped trace out over Watch Connectivity (decisions §33).
  ///
  /// A route too dense for one push is thinned to fit and the runner is told
  /// by how much; one that can't be represented at all is refused with a
  /// reason. Neither path quietly sends a partial line — the watch would then
  /// call the runner off route against geometry the route does not have.
  Future<void> _sendRouteToAppleWatch() async {
    if (_appleWatchPushBusy) return;
    final l10n = AppLocalizations.of(context);
    final shaped = appleWatchRouteFromWaypoints(_displayWaypoints);
    final points = shaped.points;
    if (points == null) {
      showTopBanner(context, l10n.routeDetailAppleWatchRouteTooShort);
      return;
    }
    setState(() => _appleWatchPushBusy = true);
    try {
      await AppleWatchRouteBridge.push(
        id: widget.route.id,
        name: widget.route.name,
        distanceMetres: widget.route.distanceMetres,
        points: points,
      );
      if (!mounted) return;
      showTopBanner(
        context,
        shaped.simplified
            ? l10n.routeDetailAppleWatchRouteSimplified(
                shaped.sourcePointCount, points.length)
            : l10n.routeDetailAppleWatchRouteSent(points.length),
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context,
          l10n.routeDetailAppleWatchRouteFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _appleWatchPushBusy = false);
    }
  }

  /// Build the schedule to push alongside the course, or null when this route
  /// has none to build.
  ///
  /// Built from the runner's own [RoadbookPlan] — the same stored record the
  /// crew sheet reads and writes — so the arrivals and cut-off verdicts on the
  /// wrist are the ones on the sheet in the crew's hands. Nothing here invents
  /// a pace: a canned one guarantees the two disagree, and a missing start
  /// clock silently drops every wall-clock cut-off from the push, which on a
  /// race whose barriers are all wall-clock is the entire schedule.
  ///
  /// Fetching markers is an auxiliary step: a failure degrades to a course-only
  /// push (the course still goes) instead of sinking the whole action.
  Future<WatchRoadbookResult?> _watchRoadbook() async {
    final api = widget.apiClient;
    if (api == null) return null;
    List<cm.RouteMarkerRow> markers;
    try {
      markers = await api.fetchRouteMarkers(widget.route.id);
    } catch (e) {
      debugPrint('sendToWatch: fetchRouteMarkers failed: $e');
      return null;
    }
    if (markers.isEmpty || !mounted) return null;
    final plan = await _roadbookPlan();
    if (plan == null || !mounted) return null;
    return watchRoadbookFromRoadbook(buildRoadbook(
      [
        for (final w in _displayWaypoints)
          RoadbookWaypoint(lat: w.lat, lng: w.lng, ele: w.elevationMetres),
      ],
      [
        for (final m in markers)
          RoadbookMarker(
              positionM: m.positionM, kind: m.kind, label: m.label, meta: m.meta),
      ],
      goalSeconds: plan.goalSeconds.toDouble(),
      startClockMin: plan.startClockMin?.toDouble(),
      model: plan.model,
    ));
  }

  /// This route's stored race plan, asking for one when there is none. A
  /// declined prompt returns null and the caller sends no schedule at all.
  Future<RoadbookPlan?> _roadbookPlan() async {
    final stored = await loadRoadbookPlan(widget.route.id);
    if (stored != null) return stored;
    if (!mounted) return null;
    final asked = await showRoadbookPlanSheet(
      context,
      distanceMetres: widget.route.distanceMetres,
    );
    if (asked == null) return null;
    await saveRoadbookPlan(widget.route.id, asked);
    return asked;
  }

  /// The one thing worth telling the runner about a completed push. Ordered by
  /// what would hurt most to miss: a schedule that could not be sent, then
  /// cut-offs the watch will not know about, then a thinned schedule, then the
  /// clean case.
  String _watchPushMessage(
    AppLocalizations l10n,
    WatchCourseResult course,
    int pointCount,
    WatchRoadbookResult? schedule,
  ) {
    final checkpoints = schedule?.checkpoints;
    if (schedule != null && checkpoints == null) {
      // noSchedule is not worth a warning — it just means the markers carry no
      // positions yet, and the course still landed.
      if (schedule.refusal == WatchRoadbookRefusal.tooManyCutoffs) {
        return l10n.routeDetailWatchScheduleTooManyCutoffs(
            pointCount, schedule.sourceCutoffCount, kMaxRoadbookCutoffs);
      }
    } else if (checkpoints != null) {
      if (schedule!.unresolvedCutoffCount > 0) {
        return l10n.routeDetailWatchScheduleClockCutoffs(
            checkpoints.length, schedule.unresolvedCutoffCount);
      }
      if (schedule.reduced) {
        return l10n.routeDetailWatchScheduleThinned(pointCount,
            schedule.sourceCheckpointCount, checkpoints.length);
      }
      return l10n.routeDetailWatchCourseAndScheduleSent(
          pointCount, checkpoints.length);
    }
    return course.simplified
        ? l10n.routeDetailWatchCourseSimplified(
            course.sourcePointCount, pointCount)
        : l10n.routeDetailWatchCourseSent(pointCount);
  }

  Future<void> _shareAs(BuildContext context, String format) async {
    // Use displayWaypoints (clipped for non-owners) so a non-owner
    // sharing a public route can't leak the unclipped polyline via
    // the GPX/KML exporter.
    final route = cm.Route(
      id: widget.route.id,
      userId: widget.route.userId,
      name: widget.route.name,
      waypoints: _displayWaypoints,
      distanceMetres: widget.route.distanceMetres,
      elevationGainMetres: widget.route.elevationGainMetres,
      isPublic: widget.route.isPublic,
      createdAt: widget.route.createdAt,
      surface: widget.route.surface,
      tags: widget.route.tags,
      featured: widget.route.featured,
      runCount: widget.route.runCount,
      isStarred: widget.route.isStarred,
      description: widget.route.description,
    );
    if (format == 'image') {
      await showRouteShareSheet(
        context,
        route: route,
        preferences: widget.preferences,
      );
      return;
    }
    try {
      final tmp = await getTemporaryDirectory();
      final safe = route.name
              .replaceAll(RegExp(r'[^a-zA-Z0-9-_ ]'), '')
              .replaceAll(RegExp(r'\s+'), '_');
      final base = safe.isEmpty ? 'route' : safe;
      final isKml = format == 'kml';
      final withMarkers = format == 'gpx_markers';

      // Fetch the raw course markers on demand so the waypoints land in
      // the export. A failure (offline / RLS) must never sink the share —
      // fall back to a line-only GPX.
      var markers = <cm.RouteMarkerRow>[];
      if (withMarkers) {
        try {
          markers =
              await widget.apiClient?.fetchRouteMarkers(widget.route.id) ??
                  <cm.RouteMarkerRow>[];
        } catch (e) {
          debugPrint('shareAs gpx_markers: fetchRouteMarkers failed: $e');
        }
      }

      final fileName = withMarkers
          ? '${base}_with_markers.gpx'
          : '$base.${isKml ? 'kml' : 'gpx'}';
      final file = File('${tmp.path}/$fileName');
      final String contents;
      if (isKml) {
        contents = _routeToKml(route);
      } else if (withMarkers) {
        contents = routeGpxFromRoute(route, markers);
      } else {
        contents = _routeToGpx(route);
      }
      await file.writeAsString(contents);
      await Share.shareXFiles(
        [
          XFile(file.path,
              mimeType: isKml
                  ? 'application/vnd.google-earth.kml+xml'
                  : 'application/gpx+xml')
        ],
        text: route.name,
      );
    } catch (e) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        showTopBanner(
            context,
            l10n.routeDetailShareFailed(
                format.toUpperCase(), friendlyError(l10n, e)));
      }
    }
  }

  /// Owner-only — open the transfer/detach sheet, then commit the
  /// chosen action via `SocialService.setRouteClub`. Detach is
  /// distinguished from transfer by passing `null` as the new clubId.
  Future<void> _transferToClub() async {
    if (_transferBusy) return;
    setState(() => _transferBusy = true);

    List<ClubView> myClubs;
    try {
      myClubs = await _social.fetchMyClubs().timeout(kBackendLoadTimeout);
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _transferBusy = false);
      showTopBanner(
          context, AppLocalizations.of(context).routeDetailClubsLoadTimeout);
      return;
    } catch (e, s) {
      debugPrint('transferToClub: fetchMyClubs failed: $e\n$s');
      if (!mounted) return;
      setState(() => _transferBusy = false);
      showTopBanner(
          context, AppLocalizations.of(context).routeDetailClubsLoadFailed);
      return;
    }
    if (!mounted) return;

    final eligible = adminClubsForRouteTransfer(myClubs);
    final result = await showModalBottomSheet<TransferRouteResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RouteTransferClubPicker(
        clubs: eligible,
        currentClubId: _clubId,
      ),
    );
    if (result == null) {
      if (mounted) setState(() => _transferBusy = false);
      return;
    }

    final targetClubId = result.detach ? null : result.clubId;
    if (targetClubId == _clubId) {
      // No-op selection.
      if (mounted) setState(() => _transferBusy = false);
      return;
    }

    try {
      await _social
          .setRouteClub(routeId: widget.route.id, clubId: targetClubId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _clubId = targetClubId;
        _transferBusy = false;
      });
      showTopBanner(
        context,
        targetClubId == null
            ? AppLocalizations.of(context).routeDetailDetached
            : AppLocalizations.of(context).routeDetailMovedToClub,
      );
    } catch (e, s) {
      debugPrint('setRouteClub failed: $e\n$s');
      if (!mounted) return;
      setState(() => _transferBusy = false);
      showTopBanner(
          context, AppLocalizations.of(context).routeDetailTransferFailed(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.routeDetailDeleteTitle),
        content: Text(l10n.routeDetailDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.routeDetailCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppSemanticColors.of(ctx).danger,
              foregroundColor: AppSemanticColors.of(ctx).onDanger,
            ),
            child: Text(l10n.routeDetailDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Delete the cloud row first — if the API call succeeds, removing
    // the local file can't leave the cloud row dangling. The previous
    // behaviour deleted only the local file, so the next refresh
    // pulled the cloud row back and the route reappeared in the list.
    //
    // When the cloud delete fails (offline / RLS / network), surface
    // the error and KEEP the local file so the user can retry once
    // they're back online. Falls back to local-only delete when the
    // ApiClient isn't available (signed-out / no-Supabase build).
    final api = widget.apiClient;
    if (api != null && api.userId != null) {
      try {
        await api.deleteRoute(widget.route.id);
      } catch (e) {
        debugPrint('route detail delete failed: $e');
        if (!context.mounted) return;
        showTopBanner(
            context, AppLocalizations.of(context).routeDetailDeleteFailed(friendlyError(AppLocalizations.of(context), e)));
        return;
      }
    }
    await widget.routeStore.delete(widget.route.id);
    if (context.mounted) Navigator.pop(context);
  }


  static IconData _surfaceIcon(String surface) {
    switch (surface) {
      case 'trail':
        return Icons.terrain;
      case 'mixed':
        return Icons.alt_route;
      case 'road':
      default:
        return Icons.add_road;
    }
  }

  static String _surfaceLabel(AppLocalizations l10n, String surface) {
    switch (surface) {
      case 'trail':
        return l10n.routeDetailSurfaceTrail;
      case 'mixed':
        return l10n.routeDetailSurfaceMixed;
      case 'road':
      default:
        return l10n.routeDetailSurfaceRoad;
    }
  }
}

String _routeToKml(cm.Route route) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  final coords = StringBuffer();
  for (final w in route.waypoints) {
    coords.writeln('          ${w.lng},${w.lat},${w.elevationMetres ?? 0}');
  }

  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<kml xmlns="http://www.opengis.net/kml/2.2">\n'
      '  <Document>\n'
      '    <name>${esc(route.name)}</name>\n'
      '    <Placemark>\n'
      '      <name>${esc(route.name)}</name>\n'
      '      <Style>\n'
      '        <LineStyle>\n'
      '          <color>ffff0000</color>\n'
      '          <width>3</width>\n'
      '        </LineStyle>\n'
      '      </Style>\n'
      '      <LineString>\n'
      '        <tessellate>1</tessellate>\n'
      '        <coordinates>\n${coords.toString().trimRight()}\n'
      '        </coordinates>\n'
      '      </LineString>\n'
      '    </Placemark>\n'
      '  </Document>\n'
      '</kml>\n';
}

String _routeToGpx(cm.Route route) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln(
      '<gpx version="1.1" creator="Run" xmlns="http://www.topografix.com/GPX/1/1">');
  buf.writeln('  <metadata>');
  buf.writeln('    <name>${esc(route.name)}</name>');
  buf.writeln('    <time>${DateTime.now().toUtc().toIso8601String()}</time>');
  buf.writeln('  </metadata>');
  buf.writeln('  <trk>');
  buf.writeln('    <name>${esc(route.name)}</name>');
  buf.writeln('    <trkseg>');
  for (final w in route.waypoints) {
    buf.write('      <trkpt lat="${w.lat}" lon="${w.lng}">');
    if (w.elevationMetres != null) {
      buf.write('<ele>${w.elevationMetres}</ele>');
    }
    buf.writeln('</trkpt>');
  }
  buf.writeln('    </trkseg>');
  buf.writeln('  </trk>');
  buf.writeln('</gpx>');
  return buf.toString();
}

/// Build the course-waypoint GPX for a route: the (privacy-clipped) line
/// plus one `<wpt>` per course marker. Pure composition over
/// `toRouteGpxWithMarkers` so the share path stays testable without file
/// IO. `[lng, lat]` order matches the shared emitter.
String routeGpxFromRoute(cm.Route route, List<cm.RouteMarkerRow> markers) {
  final coordinates = <List<double>>[];
  final elevations = <double>[];
  for (final w in route.waypoints) {
    coordinates.add([w.lng, w.lat]);
    elevations.add((w.elevationMetres ?? 0).toDouble());
  }
  final gpxMarkers = markers
      .map((m) => RouteGpxMarker(
            label: m.label,
            lat: m.lat,
            lng: m.lng,
            kind: m.kind,
            meta: m.meta is Map
                ? (m.meta as Map).cast<String, dynamic>()
                : <String, dynamic>{},
          ))
      .toList();
  return toRouteGpxWithMarkers(route.name, coordinates, elevations, gpxMarkers);
}

/// Horizontal scrubber for previewing a route's direction. Hosted
/// just below the static map view on `RouteDetailScreen`: drag the
/// thumb from left (start) to right (finish) and the `LiveRunMap`
/// renders a pulsing runner marker at the interpolated position
/// along the polyline.
///
/// Self-contained — owns no map state; emits a 0..1 [fraction] up
/// to the parent which interpolates the lat/lng via
/// [interpolateAlongRoute] and passes it to the map. Three
/// callbacks (`onChangeStart` / `onChanged` / `onChangeEnd`) mirror
/// Material's [Slider] so the parent can mount the runner marker
/// only while the user is actively dragging (fade-back behaviour).
class _RoutePreviewScrubber extends StatelessWidget {
  final double fraction;
  final double totalDistanceM;
  final DistanceUnit unit;
  final VoidCallback onChangeStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  const _RoutePreviewScrubber({
    required this.fraction,
    required this.totalDistanceM,
    required this.unit,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final reachedM = totalDistanceM * fraction;
    final reachedLabel =
        UnitFormat.distance(reachedM, unit);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.directions_run,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.routeDetailPreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Live distance readout — updates as the user drags.
              // Gives feedback in distance terms rather than raw
              // percentage so the runner knows "I'm 2.3 km in" not
              // "I'm at 43%".
              Text(
                reachedLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Slider(
            value: fraction.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            onChangeStart: (_) => onChangeStart(),
            onChanged: onChanged,
            onChangeEnd: (_) => onChangeEnd(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    l10n.routeDetailPreviewStart,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    l10n.routeDetailPreviewFinish,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact icon + label pill used by the surface / run-count /
/// featured metadata row. Same visual language as the routes-list
/// badges (Will-sync / Public) so the two surfaces read as one
/// design system.
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


class _RouteTagsRow extends StatefulWidget {
  final cm.Route route;
  final bool isOwner;
  final ApiClient? apiClient;
  final List<String> initialTags;
  final void Function(List<String>) onChange;

  const _RouteTagsRow({
    required this.route,
    required this.isOwner,
    required this.apiClient,
    required this.initialTags,
    required this.onChange,
  });

  @override
  State<_RouteTagsRow> createState() => _RouteTagsRowState();
}

class _RouteTagsRowState extends State<_RouteTagsRow> {
  late List<String> _tags = List.from(widget.initialTags);
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final api = widget.apiClient;
    if (api == null) return;
    final t = _controller.text.trim().toLowerCase();
    if (t.isEmpty || _tags.contains(t)) { _controller.clear(); return; }
    final next = [..._tags, t];
    setState(() { _saving = true; });
    try {
      await api.updateRouteTags(widget.route.id, next);
      setState(() { _tags = next; _saving = false; _controller.clear(); });
      widget.onChange(next);
    } catch (e) {
      debugPrint('route detail tag save failed: $e');
      setState(() => _saving = false);
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).routeDetailTagSaveFailed(friendlyError(AppLocalizations.of(context), e)));
      }
    }
  }

  Future<void> _remove(String tag) async {
    final api = widget.apiClient;
    if (api == null) return;
    final next = _tags.where((t) => t != tag).toList();
    setState(() { _saving = true; });
    try {
      await api.updateRouteTags(widget.route.id, next);
      setState(() { _tags = next; _saving = false; });
      widget.onChange(next);
    } catch (e) {
      debugPrint('updateRouteTags (remove) failed for ${widget.route.id}: $e');
      setState(() => _saving = false);
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).routeDetailTagRemoveFailed(friendlyError(AppLocalizations.of(context), e)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_tags.isEmpty && !widget.isOwner) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in _tags)
            Chip(
              label: Text(t, style: theme.textTheme.labelMedium),
              onDeleted: widget.isOwner && !_saving ? () => _remove(t) : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          if (widget.isOwner)
            SizedBox(
              width: 120,
              child: TextField(
                controller: _controller,
                enabled: !_saving,
                style: theme.textTheme.bodySmall,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).routeDetailAddTagHint,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: theme.colorScheme.outline),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pop result for the route transfer picker. `detach` means "move
/// back to personal" (the parent passes `clubId: null` to
/// `setRouteClub`); otherwise `clubId` is the destination club's id.
@visibleForTesting
class TransferRouteResult {
  final bool detach;
  final String? clubId;
  const TransferRouteResult.transfer(this.clubId) : detach = false;
  const TransferRouteResult.detach()
      : detach = true,
        clubId = null;
}

/// Modal that lists the viewer's admin-able clubs + a "Detach to
/// personal" option (when the route is currently owned by a club).
/// Pops `null` on cancel, a `TransferRouteResult.detach()` on
/// detach, or `TransferRouteResult.transfer(clubId)` on a club tap.
class RouteTransferClubPicker extends StatelessWidget {
  final List<ClubView> clubs;
  final String? currentClubId;
  const RouteTransferClubPicker({
    super.key,
    required this.clubs,
    this.currentClubId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              currentClubId == null
                  ? l10n.routeDetailTransferDialogTitle
                  : l10n.routeDetailManageClubTitle,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              currentClubId == null
                  ? l10n.routeDetailTransferDialogBody
                  : l10n.routeDetailManageClubBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (currentClubId != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person),
                title: Text(l10n.routeDetailDetachToPersonal),
                subtitle: Text(
                  l10n.routeDetailDetachSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () =>
                    Navigator.pop(context, const TransferRouteResult.detach()),
              ),
            if (clubs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  l10n.routeDetailNoAdminClubs,
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: clubs.length,
                  itemBuilder: (_, i) {
                    final c = clubs[i];
                    final isCurrent = c.row.id == currentClubId;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.group),
                      title: Text(c.row.name),
                      subtitle: Text(
                        isCurrent
                            ? l10n.routeDetailCurrentClub
                            : l10n.routeDetailClubMemberCount(
                                c.row.locationLabel ?? c.row.slug,
                                c.memberCount),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: isCurrent
                          ? const Icon(Icons.check, size: 18)
                          : const Icon(Icons.chevron_right),
                      onTap: isCurrent
                          ? null
                          : () => Navigator.pop(
                              context,
                              TransferRouteResult.transfer(c.row.id),
                            ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.routeDetailCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Preserves its child's State when it scrolls out of the enclosing
/// ListView's cache extent. Wraps the route-detail map so the FlutterMap +
/// MapController aren't disposed and rebuilt (with a full tile reload) on
/// every scroll past it. Same `AutomaticKeepAliveClientMixin` idiom as
/// `_LazyKeepAliveTab` on the home shell.
class _KeepAliveMap extends StatefulWidget {
  final Widget child;
  const _KeepAliveMap({required this.child});

  @override
  State<_KeepAliveMap> createState() => _KeepAliveMapState();
}

class _KeepAliveMapState extends State<_KeepAliveMap>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
