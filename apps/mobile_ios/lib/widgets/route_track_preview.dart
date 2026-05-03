import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import 'track_preview.dart';

/// Lazy waypoint-fetching wrapper around [TrackPreview] for routes
/// (the planned-shape sibling of runs). Mirrors
/// `apps/web/src/lib/components/RouteTrackPreview.svelte`.
///
/// Routes carry waypoints inline as a jsonb column on the `routes`
/// row, unlike runs (whose tracks live in Storage). So:
///
///   - **Owner:** the row's `waypoints` is already the unclipped
///     polyline. No fetch, no RPC. Hand it straight to [TrackPreview].
///   - **Non-owner:** the row's `waypoints` is unclipped from the
///     server's perspective and must not reach the renderer. Lazy-
///     fetch via `clip_route_for_viewer` (decisions §33), which
///     visibility-gates internally and returns clipped output.
///
/// The clip RPC fails closed in `ApiClient.clipRouteForViewer`; an
/// outage renders the placeholder rather than leaking.
class RouteTrackPreview extends StatefulWidget {
  /// The route id. Required when the viewer isn't the owner —
  /// `clip_route_for_viewer` looks up the owner + zones server-side.
  final String routeId;

  /// The row's `waypoints`. Used directly when the viewer is the
  /// owner; ignored otherwise (the non-owner path goes through the
  /// clip RPC).
  final List<Waypoint> waypoints;

  /// User id of the route's owner. When this differs from the
  /// signed-in viewer's id (or the viewer is anon), the thumbnail
  /// goes through `clip_route_for_viewer`.
  final String ownerUserId;

  final ApiClient api;
  final Color color;
  final double aspect;

  const RouteTrackPreview({
    super.key,
    required this.routeId,
    required this.waypoints,
    required this.ownerUserId,
    required this.api,
    this.color = const Color(0xFF4F46E5),
    this.aspect = 2.4,
  });

  @override
  State<RouteTrackPreview> createState() => _RouteTrackPreviewState();
}

class _RouteTrackPreviewState extends State<RouteTrackPreview> {
  // Module-level cache. The key prefix (`raw:` vs `clip:`) keeps owner
  // and non-owner reads of the same route from polluting each other —
  // identical to the RunTrackPreview cache shape. Bounded LRU; drops
  // the oldest entry when full so a long browsing session through a
  // big club's routes doesn't hold every clipped polyline in memory.
  static const int _cacheMax = 200;
  static final Map<String, List<Waypoint>?> _cache = {};

  static void _cacheSet(String key, List<Waypoint>? value) {
    if (_cache.length >= _cacheMax && !_cache.containsKey(key)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  List<Waypoint>? _points;
  bool _attempted = false;

  bool get _shouldClip {
    return widget.api.userId != widget.ownerUserId;
  }

  String _cacheKey() {
    return '${_shouldClip ? 'clip' : 'raw'}:${widget.routeId}';
  }

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant RouteTrackPreview old) {
    super.didUpdateWidget(old);
    if (old.routeId != widget.routeId ||
        old.ownerUserId != widget.ownerUserId) {
      _attempted = false;
      _points = null;
      _maybeLoad();
    }
  }

  void _maybeLoad() {
    if (_attempted) return;
    _attempted = true;

    // Owner: use the row's waypoints directly. No RPC.
    if (!_shouldClip) {
      _points = widget.waypoints;
      return;
    }

    final key = _cacheKey();
    if (_cache.containsKey(key)) {
      _points = _cache[key];
      return;
    }

    () async {
      try {
        final clipped = await widget.api.clipRouteForViewer(widget.routeId);
        _cacheSet(key, clipped);
        if (mounted) setState(() => _points = clipped);
      } catch (_) {
        _cacheSet(key, null);
        if (mounted) setState(() => _points = null);
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final pts = _points;
    if (pts == null || pts.length < 2) {
      return _placeholder(context);
    }
    return TrackPreview(points: pts, color: widget.color, aspect: widget.aspect);
  }

  Widget _placeholder(BuildContext context) {
    return Center(
      child: Icon(
        Icons.map_outlined,
        size: 18,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
