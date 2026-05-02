import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import 'track_preview.dart';

/// Lazy track-fetching wrapper around [TrackPreview]. Mirrors
/// `apps/web/src/lib/components/RunTrackPreview.svelte`: takes a track
/// URL (the path stored in `runs.metadata.track_url`), fetches the
/// gzipped JSON on first build, caches the result keyed by URL so
/// scrolling away and back doesn't re-download.
///
/// Falls back to a placeholder when the URL is missing, the fetch
/// fails, or the bounding-box diagonal is below the jitter threshold.
class RunTrackPreview extends StatefulWidget {
  final String? trackUrl;
  final ApiClient api;
  final Color color;
  final double aspect;

  /// User id of the run's owner. When set AND it differs from the
  /// signed-in viewer's id, the fetched track is routed through the
  /// `clip_track_for_user` RPC so the owner's privacy zones are
  /// honoured before we render the polyline (decisions §33). Omit
  /// when the row is the viewer's own — no clip required, faster
  /// cold load.
  final String? ownerUserId;

  const RunTrackPreview({
    super.key,
    required this.trackUrl,
    required this.api,
    this.color = const Color(0xFF4F46E5),
    this.aspect = 2.4,
    this.ownerUserId,
  });

  @override
  State<RunTrackPreview> createState() => _RunTrackPreviewState();
}

class _RunTrackPreviewState extends State<RunTrackPreview> {
  // Module-level cache. The key prefix (`raw:` vs `clip:`) keeps owner
  // and non-owner reads of the same track from polluting each other —
  // a sibling user that shares no privacy zones with the viewer would
  // otherwise see the cached clipped polyline.
  static final Map<String, List<Waypoint>?> _cache = {};

  List<Waypoint>? _points;
  bool _attempted = false;

  bool get _shouldClip {
    final owner = widget.ownerUserId;
    final viewer = widget.api.userId;
    return owner != null && viewer != null && owner != viewer;
  }

  String? _cacheKey() {
    final url = widget.trackUrl;
    if (url == null || url.isEmpty) return null;
    return '${_shouldClip ? 'clip' : 'raw'}:$url';
  }

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant RunTrackPreview old) {
    super.didUpdateWidget(old);
    if (old.trackUrl != widget.trackUrl ||
        old.ownerUserId != widget.ownerUserId) {
      _attempted = false;
      _points = null;
      _maybeLoad();
    }
  }

  void _maybeLoad() {
    final url = widget.trackUrl;
    final key = _cacheKey();
    if (url == null || url.isEmpty || key == null) return;
    if (_cache.containsKey(key)) {
      _points = _cache[key];
      _attempted = true;
      return;
    }
    if (_attempted) return;
    _attempted = true;
    () async {
      try {
        var track = await widget.api.fetchTrackByPath(url);
        if (_shouldClip) {
          // Server-side privacy-zone clipping for non-owner viewers
          // (decisions §33). Owners always see their full track.
          final clipped = await widget.api.clipTrackForUser(
            targetUserId: widget.ownerUserId!,
            points: track
                .map((w) => {
                      'lat': w.lat,
                      'lng': w.lng,
                      if (w.elevationMetres != null) 'ele': w.elevationMetres,
                    })
                .toList(),
          );
          track = clipped
              .map((p) => Waypoint(
                    lat: (p['lat'] as num).toDouble(),
                    lng: (p['lng'] as num).toDouble(),
                    elevationMetres: (p['ele'] as num?)?.toDouble(),
                  ))
              .toList();
        }
        final renderable = isTrackRenderable(track) ? track : <Waypoint>[];
        _cache[key] = renderable;
        if (mounted) setState(() => _points = renderable);
      } catch (_) {
        _cache[key] = null;
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
