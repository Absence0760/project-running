import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../backend_timeout.dart';
import '../local_route_store.dart';
import '../preferences.dart';
import '../route_geometry.dart' show interpolateAlongRoute;
import '../social_service.dart' show ClubView, SocialService;
import '../widgets/live_run_map.dart';
import '../widgets/missing_map_tiles_hint.dart';
import '../widgets/report_sheet.dart';
import '../widgets/route_share_card.dart';
import '../widgets/segments_panel.dart';
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

  const RouteDetailScreen({
    super.key,
    required this.route,
    required this.routeStore,
    required this.preferences,
    this.apiClient,
    this.isOwner = false,
    this.social,
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

  // Waypoints handed to the renderer. For the owner this mirrors
  // widget.route.waypoints from the row; for non-owners this is the
  // privacy-zone-clipped output of clip_route_for_viewer (decisions
  // §33). Bookmarked / public / club-readable routes the viewer
  // doesn't own would otherwise leak the unclipped polyline through
  // LiveRunMap's plannedRoute prop.
  List<cm.Waypoint> _displayWaypoints = const [];

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

  @override
  void initState() {
    super.initState();
    _fetchReviews();
    _loadBookmarkState();
    _resolveDisplayWaypoints();
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
    } catch (_) {
      if (mounted) setState(() => _displayWaypoints = const []);
    }
  }

  Future<void> _loadBookmarkState() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null || widget.isOwner) return;
    try {
      final saved = await api.isRouteBookmarked(widget.route.id);
      if (!mounted) return;
      setState(() => _bookmarked = saved);
    } catch (_) {
      // Best-effort; the toggle still falls through.
    }
  }

  Future<void> _toggleBookmark() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null || _bookmarkBusy) return;
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
      if (!mounted) return;
      setState(() => _bookmarked = before);
      showTopBanner(context, 'Bookmark failed: $e');
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingReviews = false;
          _reviewsOffline = true;
        });
      }
    }
  }

  Future<void> _togglePublic() async {
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
    setState(() => _isPublic = newValue);
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
              ? 'Route set to public. Will sync next time.'
              : 'Route set to private. Will sync next time.',
        );
      }
      return;
    }
    try {
      await api.setRoutePublic(widget.route.id, newValue);
    } catch (e) {
      // Roll back local state to match what cloud thinks. Surface
      // the error so the user knows the toggle didn't persist
      // cloud-side. The route stays in the unsynced queue if it
      // was locally-built so the SyncService will retry the
      // saveRoute push on the next cycle.
      if (mounted) {
        setState(() => _isPublic = !newValue);
        await widget.routeStore.save(buildRoute(!newValue));
        showTopBanner(context, 'Could not update visibility: $e');
      }
    }
  }

  Future<void> _toggleOfflinePin() async {
    final id = widget.route.id;
    final next = !_isOfflinePinned;
    setState(() => _isOfflinePinned = next);
    if (next) {
      // Make sure the JSON file is actually on disk — for a non-owner
      // viewer who only ever saw the route via the Explore tab, the
      // detail row may not yet be persisted locally. Mark synced so
      // the SyncService doesn't try to push someone else's route up.
      await widget.routeStore.save(widget.route, markSynced: true);
      await widget.routeStore.pinOffline(id);
    } else {
      await widget.routeStore.unpinOffline(id);
    }
    if (mounted) {
      showTopBanner(
        context,
        next ? 'Saved for offline use.' : 'Removed from offline saves.',
      );
    }
  }

  Future<void> _toggleStar() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
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
    setState(() => _isStarred = newValue);
    await widget.routeStore.save(buildRoute(newValue));
    try {
      await api.setRouteStar(r.id, newValue);
    } catch (e) {
      if (mounted) setState(() => _isStarred = !newValue);
      await widget.routeStore.save(buildRoute(!newValue));
      if (mounted) {
        showTopBanner(context, 'Could not update star: $e');
      }
    }
  }

  Future<void> _submitReview() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      showTopBanner(context, 'Sign in to leave a review');
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Rate this route'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return IconButton(
                    icon: Icon(
                      star <= selectedRating
                          ? Icons.star
                          : Icons.star_border,
                      color: const Color(0xFFEAB308),
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
                decoration: const InputDecoration(
                  labelText: 'Comment (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit'),
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
      if (mounted) {
        showTopBanner(context, 'Failed to submit review: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              onPressed: () => Navigator.pop(context, route),
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.play_arrow),
              label: const Text(
                'Start run',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : null,
      appBar: AppBar(
        title: Text(route.name),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share',
            onSelected: (fmt) => _shareAs(context, fmt),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'image', child: Text('Share as image')),
              PopupMenuItem(value: 'gpx', child: Text('Share as GPX')),
              PopupMenuItem(value: 'kml', child: Text('Share as KML')),
            ],
          ),
          // Offline-pin affordance — local-only flag (never synced).
          // Surfaces an inline tile below for discoverability and the
          // AppBar icon here so it sits next to the star (which gates
          // watch sync) — the two together read as "what stays where".
          IconButton(
            icon: Icon(
              _isOfflinePinned ? Icons.download_done : Icons.download_outlined,
              color: _isOfflinePinned
                  ? const Color(0xFF22C55E)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            tooltip: _isOfflinePinned
                ? 'Remove offline save'
                : 'Save for offline use',
            onPressed: _toggleOfflinePin,
          ),
          if (_isOwner)
            IconButton(
              icon: Icon(
                _isStarred ? Icons.star : Icons.star_border,
                color: _isStarred
                    ? const Color(0xFFFBBF24)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              tooltip: _isStarred ? 'Unstar route' : 'Star to show on watch',
              onPressed: _toggleStar,
            ),
          // Show the visibility toggle whenever the local store
          // considers the viewer to own this route — regardless of
          // signed-in state. _togglePublic itself handles the
          // signed-out path (writes local + queues for sync) so the
          // user surfaces the affordance they expect to see and
          // ALSO doesn't lose the toggle on a network hiccup.
          if (widget.isOwner)
            IconButton(
              icon: Icon(_isPublic ? Icons.public : Icons.public_off),
              tooltip: _isPublic ? 'Make private' : 'Make public',
              onPressed: _togglePublic,
            ),
          if (!widget.isOwner &&
              widget.apiClient != null &&
              widget.apiClient!.userId != null)
            IconButton(
              icon: Icon(
                (_bookmarked ?? false) ? Icons.bookmark : Icons.bookmark_border,
              ),
              tooltip: (_bookmarked ?? false) ? 'Remove bookmark' : 'Bookmark route',
              onPressed: _bookmarkBusy ? null : _toggleBookmark,
            ),
          if (!widget.isOwner && widget.apiClient != null)
            IconButton(
              tooltip: 'Report route',
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => showReportSheet(
                context,
                api: widget.apiClient!,
                targetKind: 'route',
                targetId: route.id,
              ),
            ),
          if (_isOwner)
            IconButton(
              icon: _transferBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_clubId == null
                      ? Icons.group_add_outlined
                      : Icons.group),
              tooltip: _clubId == null
                  ? 'Transfer to club'
                  : 'Detach or move to another club',
              onPressed: _transferBusy ? null : _transferToClub,
            ),
          if (_isOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete route',
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            SizedBox(
              height: 320,
              child: LiveRunMap(
                track: const [],
                plannedRoute: _displayWaypoints,
                followRunner: false,
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat(
                    label: 'Distance',
                    value: UnitFormat.distanceValue(route.distanceMetres, unit),
                    unit: UnitFormat.distanceLabel(unit),
                  ),
                  _Stat(
                    label: 'Elevation',
                    value: '${route.elevationGainMetres.round()}',
                    unit: 'm',
                  ),
                  if (_avgRating > 0)
                    _Stat(
                      label: '${_reviews.length} reviews',
                      value: _avgRating.toStringAsFixed(1),
                      unit: '/ 5',
                    )
                  else
                    _Stat(
                      label: 'Waypoints',
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
                      Text(
                        _isPublic ? 'Public route' : 'Private route',
                      ),
                    ],
                  ),
                  subtitle: Text(
                    _isPublic
                        ? 'Anyone with the share link can view this route'
                        : 'Only you can see this route',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  value: _isPublic,
                  onChanged: (_) => _togglePublic(),
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
                          ? const Color(0xFF22C55E)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(_isOfflinePinned
                        ? 'Saved for offline'
                        : 'Save for offline'),
                  ],
                ),
                subtitle: Text(
                  _isOfflinePinned
                      ? 'Route stays on this phone so you can run it without a connection.'
                      : 'Keep this route on your phone for use without a network.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                value: _isOfflinePinned,
                onChanged: (_) => _toggleOfflinePin(),
              ),
            ),

            if (route.description != null && route.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Description',
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
                        label: _surfaceLabel(route.surface!),
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    if (route.runCount > 0)
                      _MetaChip(
                        icon: Icons.directions_run,
                        label:
                            '${route.runCount} ${route.runCount == 1 ? 'run' : 'runs'}',
                        color: theme.colorScheme.primary,
                      ),
                    if (route.featured)
                      _MetaChip(
                        icon: Icons.star,
                        label: 'Featured',
                        color: const Color(0xFFFBBF24),
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

            // Segments panel — list segments + leaderboards. Owners
            // can create new ones; cascades drop their efforts.
            if (widget.apiClient != null)
              SegmentsPanel(
                api: widget.apiClient!,
                routeId: route.id,
                routeDistanceM: route.distanceMetres,
                canCreate: _isOwner,
              ),

            const Divider(),

            // Reviews section
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Reviews', style: theme.textTheme.titleMedium),
                  TextButton.icon(
                    onPressed: _submitReview,
                    icon: const Icon(Icons.rate_review, size: 18),
                    label: const Text('Rate'),
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
                      ? 'Reviews unavailable offline'
                      : 'No reviews yet',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            else
              ..._reviews.map((review) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
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
                                    color: const Color(0xFFEAB308),
                                  ),
                                ),
                                const Spacer(),
                                if (review.createdAt != null)
                                  Text(
                                    _formatDate(review.createdAt!),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
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

            // Trailing bottom-of-scroll padding so the FAB doesn't
            // sit on top of the last review card.
            const SizedBox(height: 88),
          ],
        ),
      ),
    );
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
      final file = File('${tmp.path}/$base.${isKml ? 'kml' : 'gpx'}');
      await file.writeAsString(
          isKml ? _routeToKml(route) : _routeToGpx(route));
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
        showTopBanner(context, 'Could not share ${format.toUpperCase()}: $e');
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
      showTopBanner(context, 'Couldn\'t load your clubs — check your network.');
      return;
    } catch (e, s) {
      debugPrint('transferToClub: fetchMyClubs failed: $e\n$s');
      if (!mounted) return;
      setState(() => _transferBusy = false);
      showTopBanner(context, 'Couldn\'t load your clubs.');
      return;
    }
    if (!mounted) return;

    final eligible = adminClubsForRouteTransfer(myClubs);
    final result = await showModalBottomSheet<TransferRouteResult>(
      context: context,
      isScrollControlled: true,
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
            ? 'Detached from club; route is now personal.'
            : 'Route moved into the club library.',
      );
    } catch (e, s) {
      debugPrint('setRouteClub failed: $e\n$s');
      if (!mounted) return;
      setState(() => _transferBusy = false);
      showTopBanner(context, 'Transfer failed: $e');
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete route?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
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
        if (!context.mounted) return;
        showTopBanner(context, 'Delete failed: $e');
        return;
      }
    }
    await widget.routeStore.delete(widget.route.id);
    if (context.mounted) Navigator.pop(context);
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}';
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

  static String _surfaceLabel(String surface) {
    switch (surface) {
      case 'trail':
        return 'TRAIL';
      case 'mixed':
        return 'MIXED';
      case 'road':
      default:
        return 'ROAD';
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
              Text(
                'Preview',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
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
                Text(
                  'Start',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Finish',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const _Stat({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            )),
      ],
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
      setState(() => _saving = false);
      if (mounted) {
        showTopBanner(context, 'Could not save tag: $e');
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
    } catch (_) {
      setState(() => _saving = false);
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
              label: Text(t, style: const TextStyle(fontSize: 12)),
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
                style: const TextStyle(fontSize: 12),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: 'add tag',
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              currentClubId == null ? 'Transfer to club' : 'Manage club ownership',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              currentClubId == null
                  ? 'Members of the club will see this route in the club library and can adopt it onto their plans.'
                  : 'Move this route into another club you admin, or detach it back to personal.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (currentClubId != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person),
                title: const Text('Detach to personal'),
                subtitle: Text(
                  'Removes the route from the current club\'s library.',
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
                  'You don\'t own or admin any clubs yet.',
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
                            ? 'Current club'
                            : '${c.row.locationLabel ?? c.row.slug} · '
                                '${c.memberCount} member${c.memberCount == 1 ? '' : 's'}',
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
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
