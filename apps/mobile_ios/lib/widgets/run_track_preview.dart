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

  const RunTrackPreview({
    super.key,
    required this.trackUrl,
    required this.api,
    this.color = const Color(0xFF4F46E5),
    this.aspect = 2.4,
  });

  @override
  State<RunTrackPreview> createState() => _RunTrackPreviewState();
}

class _RunTrackPreviewState extends State<RunTrackPreview> {
  // Module-level cache keyed by track URL, mirroring the web component.
  // A `null` entry is a sentinel for "we tried and it failed" so we
  // don't hammer Storage on a broken object during rebuilds.
  static final Map<String, List<Waypoint>?> _cache = {};

  List<Waypoint>? _points;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant RunTrackPreview old) {
    super.didUpdateWidget(old);
    if (old.trackUrl != widget.trackUrl) {
      _attempted = false;
      _points = null;
      _maybeLoad();
    }
  }

  void _maybeLoad() {
    final url = widget.trackUrl;
    if (url == null || url.isEmpty) return;
    if (_cache.containsKey(url)) {
      _points = _cache[url];
      _attempted = true;
      return;
    }
    if (_attempted) return;
    _attempted = true;
    () async {
      try {
        final track = await widget.api.fetchTrackByPath(url);
        final renderable = isTrackRenderable(track) ? track : <Waypoint>[];
        _cache[url] = renderable;
        if (mounted) setState(() => _points = renderable);
      } catch (_) {
        _cache[url] = null;
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
