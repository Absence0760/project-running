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
  /// Run id. Required for non-owner thumbnails — the
  /// `clip-public-track` Edge Function takes a run id and resolves
  /// `track_url` server-side so the unclipped blob never crosses the
  /// wire. Omit only when [ownerUserId] is null (i.e. the viewer is
  /// the owner) and the direct-Storage path is taken instead.
  final String? runId;

  final String? trackUrl;
  final ApiClient api;
  final Color color;
  final double aspect;

  /// User id of the run's owner. When set AND it differs from the
  /// signed-in viewer's id, the thumbnail goes through the
  /// `clip-public-track` Edge Function so the owner's privacy zones
  /// are honoured server-side (decisions §33, migration
  /// `20260619_001` dropped the public-runs Storage policy). Omit
  /// when the row is the viewer's own — direct Storage download is
  /// fine and faster.
  final String? ownerUserId;

  const RunTrackPreview({
    super.key,
    required this.trackUrl,
    required this.api,
    this.runId,
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
  //
  // Cap at [_cacheMax] entries — `Map` literals are LinkedHashMaps that
  // preserve insertion order, so dropping `keys.first` evicts the
  // oldest. Without the cap a long session over a 1000-run history
  // holds every deserialised track in memory until app restart.
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
    final owner = widget.ownerUserId;
    if (owner == null) return false;
    // Treat anon (`viewer == null`) as non-owner — public share
    // surfaces can be reached without signing in and must still see a
    // clipped track.
    return widget.api.userId != owner;
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
        final List<Waypoint> track;
        if (_shouldClip) {
          // Non-owner thumbnail — direct Storage download has been
          // revoked (migration 20260619_001). Use the EF path instead.
          // No runId = no way to identify the run for the EF; fail
          // closed and render the placeholder rather than fall back to
          // the (now-blocked) direct download.
          final id = widget.runId;
          if (id == null || id.isEmpty) {
            _cacheSet(key, null);
            if (mounted) setState(() => _points = null);
            return;
          }
          track = await widget.api.fetchClippedTrackForRun(id);
        } else {
          track = await widget.api.fetchTrackByPath(url);
        }
        final renderable = isTrackRenderable(track) ? track : <Waypoint>[];
        _cacheSet(key, renderable);
        if (mounted) setState(() => _points = renderable);
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
