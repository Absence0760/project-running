import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors;

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../main.dart' show pendingStartRunWithRoute;
import '../preferences.dart';
import '../widgets/error_state.dart';
import '../widgets/live_run_map.dart';
import '../widgets/route_conditions.dart';
import '../widgets/route_photos.dart';
import '../widgets/segments_panel.dart';
import '../widgets/top_banner.dart';

/// Build the route a public / shared route starts a run against — carrying
/// the CLIPPED display waypoints the viewer is allowed to see, never the
/// source route's full trace (which may run through the owner's privacy
/// zones). Pulled out so the privacy-relevant "start uses the clipped line"
/// contract is unit-testable without the map-bearing screen.
@visibleForTesting
cm.Route publicRouteStartTarget(cm.Route source, List<cm.Waypoint> clipped) {
  return cm.Route(
    id: source.id,
    name: source.name,
    waypoints: clipped,
    distanceMetres: source.distanceMetres,
    userId: source.userId,
    elevationGainMetres: source.elevationGainMetres,
    isPublic: source.isPublic,
    surface: source.surface,
  );
}

/// Read-only public view of a single route. Mirrors the web
/// `/share/route/[id]` route — anyone with the link can view a public
/// route. Private routes (or club-only routes the viewer can't see)
/// fall through to a "not available" empty state via RLS.
class PublicRouteScreen extends StatefulWidget {
  final ApiClient api;
  final String routeId;

  const PublicRouteScreen({
    super.key,
    required this.api,
    required this.routeId,
  });

  @override
  State<PublicRouteScreen> createState() => _PublicRouteScreenState();
}

class _PublicRouteScreenState extends State<PublicRouteScreen> {
  bool _loading = true;
  Object? _loadError;
  cm.Route? _route;
  List<cm.Waypoint> _waypoints = const [];
  bool _isOwner = false;
  bool? _bookmarked;
  bool _bookmarkBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final fetched = await widget.api.fetchRouteById(widget.routeId);
      final route = fetched.route;
      if (route == null) {
        if (!mounted) return;
        setState(() {
          _route = null;
          _waypoints = const [];
          _loading = false;
        });
        return;
      }
      // Privacy-zone clipping for non-owner viewers (decisions §33).
      // Owners see the full route — anon (`api.userId == null`) is
      // treated as non-owner so unauthenticated `/share/route/[id]`
      // hits also honour zones. `clipRouteForViewer` is the route-
      // specific RPC: it visibility-gates server-side (owner / public /
      // club member) and applies the owner's privacy zones in one
      // SECURITY DEFINER call. Fails closed (returns []) on outage so
      // a transient blip renders an empty map for non-owners instead
      // of leaking the start / end home location. Run-bound
      // `clipTrackForUser` would be wrong here — it doesn't do route
      // visibility.
      final viewerId = widget.api.userId;
      final ownerId = fetched.ownerId;
      final isOwner =
          viewerId != null && ownerId != null && viewerId == ownerId;
      // Three explicit branches, NOT a `(isOwner || waypoints.isEmpty)`
      // short-circuit. The original combined form was correct today
      // (empty waypoints leak zero bytes by construction) but a future
      // change that populates `route.waypoints` for non-owners on the
      // empty-branch would silently bypass clipRouteForViewer. The
      // split documents each branch's intent. See audit:privacy-zones
      // 2026-05-25.
      final List<cm.Waypoint> waypoints;
      if (isOwner) {
        waypoints = route.waypoints;
      } else if (route.waypoints.isEmpty) {
        // Non-owner viewer + empty waypoints — nothing to render and
        // nothing to clip. Avoids a wasted clipRouteForViewer call.
        waypoints = const [];
      } else {
        waypoints = await widget.api.clipRouteForViewer(widget.routeId);
      }
      if (!mounted) return;
      setState(() {
        _route = route;
        _waypoints = waypoints;
        _isOwner = isOwner;
        _loading = false;
      });
      // A non-owner viewer can save (bookmark) the route to their library —
      // load the current bookmark state (best-effort) so the AppBar action
      // reflects reality on first paint.
      if (!isOwner && widget.api.userId != null) _loadBookmarkState();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadBookmarkState() async {
    try {
      final saved = await widget.api.isRouteBookmarked(widget.routeId);
      if (!mounted) return;
      setState(() => _bookmarked = saved);
    } catch (e) {
      debugPrint('public route isRouteBookmarked failed: $e');
    }
  }

  Future<void> _toggleBookmark() async {
    if (_bookmarkBusy || widget.api.userId == null) return;
    final l10n = AppLocalizations.of(context);
    final before = _bookmarked ?? false;
    setState(() {
      _bookmarkBusy = true;
      _bookmarked = !before;
    });
    try {
      if (before) {
        await widget.api.unbookmarkRoute(widget.routeId);
      } else {
        await widget.api.bookmarkRoute(widget.routeId);
      }
    } catch (e) {
      debugPrint('public route bookmark failed: $e');
      if (!mounted) return;
      setState(() => _bookmarked = before);
      showTopBanner(
          context, l10n.routeDetailBookmarkFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _bookmarkBusy = false);
    }
  }

  void _startRun(cm.Route route) {
    // Hand off through the global notifier — HomeScreen switches to the
    // recorder with the route preselected and pops back to the shell, so a
    // follower who opened a shared / public route can run it without owning
    // it. Carry the CLIPPED display waypoints (never the owner's full trace).
    pendingStartRunWithRoute.value = publicRouteStartTarget(route, _waypoints);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final route = _route;
    final canStartRun = route != null && _waypoints.length >= 2;
    // Save (bookmark) is offered to a signed-in viewer who doesn't own the
    // route — owners already have it, signed-out viewers can't have a
    // library. Starting a run needs no sign-in (offline recording is fine).
    final canBookmark =
        route != null && !_isOwner && widget.api.userId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(route?.name ?? l10n.publicRouteFallbackTitle),
        actions: [
          if (canBookmark)
            IconButton(
              icon: Icon(
                (_bookmarked ?? false) ? Icons.bookmark : Icons.bookmark_border,
              ),
              tooltip: (_bookmarked ?? false)
                  ? l10n.routeDetailRemoveBookmark
                  : l10n.routeDetailBookmarkRoute,
              onPressed: _bookmarkBusy ? null : _toggleBookmark,
            ),
        ],
      ),
      floatingActionButton: canStartRun
          ? FloatingActionButton.extended(
              heroTag: 'public_route_start_run',
              onPressed: () => _startRun(route),
              backgroundColor: AppSemanticColors.of(context).success,
              foregroundColor: AppSemanticColors.of(context).onSuccess,
              icon: const Icon(Icons.play_arrow),
              label: Text(
                l10n.routeDetailStartRun,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorState(
                  message: l10n.publicRouteLoadError, onRetry: _load)
              : _route == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.publicRouteUnavailable,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : _buildBody(theme, _route!),
    );
  }

  Widget _buildBody(ThemeData theme, cm.Route route) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        SizedBox(
          height: 320,
          child: LiveRunMap(
            track: const [],
            plannedRoute: _waypoints,
            followRunner: false,
          ),
        ),
        if (route.description != null && route.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              route.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Stat(
                label: l10n.publicRouteStatDistance,
                value: UnitFormat.distanceValue(
                    route.distanceMetres, activeDistanceUnit),
                unit: UnitFormat.distanceLabel(activeDistanceUnit),
              ),
              _Stat(
                label: l10n.publicRouteStatElevation,
                value: '${route.elevationGainMetres.round()}',
                unit: 'm',
              ),
              _Stat(
                label: l10n.publicRouteStatWaypoints,
                value: '${_waypoints.length}',
              ),
            ],
          ),
        ),
        if (widget.api.userId != null)
          SegmentsPanel(
            api: widget.api,
            routeId: route.id,
            routeDistanceM: route.distanceMetres,
            canCreate: false,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: RoutePhotos(
            api: widget.api,
            routeId: route.id,
            routeOwnerId: route.userId,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: RouteConditions(
            api: widget.api,
            routeId: route.id,
            routeOwnerId: route.userId,
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const _Stat({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }
}
