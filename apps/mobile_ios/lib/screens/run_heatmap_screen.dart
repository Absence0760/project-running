import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/gen/app_localizations.dart';
import '../run_heatmap.dart';
import '../tile_cache.dart';
import '../widgets/live_run_map.dart' show currentTileUrl;
import 'routes_heatmap_screen.dart';

/// Personal run-track heatmap — the mobile mirror of web `/runs/heatmap`
/// (decisions/parity row "Personal run-track heatmap"). A Strava-style
/// "everywhere you've run" map of the user's OWN tracks, distinct from
/// the public route-discovery heatmap (`routes_heatmap_screen.dart`).
///
/// Downloads the owner's own track blobs via the owner-only
/// `fetchTrackByPath`, aggregates them with the pure `run_heatmap.dart`
/// (grid-quantised weighted cells, [_maxTracks] cap + bounded
/// concurrency, weight clamped so a daily commute doesn't flatten the
/// gradient), and renders heat cells as low-opacity circles that
/// crossfade into the actual track lines as you zoom past street level.
/// Owner-only path, so no privacy-zone clip is needed (the runner
/// already knows where they live).
class RunHeatmapScreen extends StatefulWidget {
  final ApiClient api;

  /// Test seam — supplies the runs newest-first without the network.
  /// Production callers leave null (the screen calls `api.getRuns`).
  final Future<List<cm.Run>> Function()? fetchRunsFn;

  /// Test seam — replays a track per Storage path without hitting
  /// Storage. Production callers leave null.
  final Future<List<cm.Waypoint>> Function(String path)? fetchTrackFn;

  const RunHeatmapScreen({
    super.key,
    required this.api,
    this.fetchRunsFn,
    this.fetchTrackFn,
  });

  @override
  State<RunHeatmapScreen> createState() => _RunHeatmapScreenState();
}

/// Cap the number of tracks downloaded so a runner with thousands of runs
/// doesn't pull every blob on first paint. Newest-first; the
/// grid-quantising aggregation means older history past the cap adds
/// diminishing visual signal anyway.
const int _maxTracks = 250;

/// Concurrency bound keeps the Storage fan-out polite.
const int _downloadConcurrency = 6;

/// Crossfade window (zoom levels): the heat cloud is fully opaque up to
/// [_fadeMin], then dissolves to nothing by [_fadeMax] while the track
/// lines fade in over the same band — heatmaps thin out when you zoom in,
/// so past street level the precise paths read better than a fading blob.
const double _fadeMin = 13;
const double _fadeMax = 15.5;

class _RunHeatmapScreenState extends State<RunHeatmapScreen> {
  final _mapController = MapController();

  List<HeatCell> _cells = const [];
  List<List<LatLng>> _lines = const [];
  List<List<double>>? _bounds;

  bool _loading = true;
  bool _empty = false;
  bool _errored = false;
  int _trackCount = 0;
  int _totalWithTracks = 0;
  bool _mapReady = false;
  bool _didFit = false;

  double _zoom = 11;

  @override
  void initState() {
    super.initState();
    unawaited(_build());
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<List<cm.Run>> _fetchRuns() {
    if (widget.fetchRunsFn != null) return widget.fetchRunsFn!();
    return widget.api.getRuns(limit: _maxTracks);
  }

  Future<List<cm.Waypoint>> _fetchTrack(String path) {
    if (widget.fetchTrackFn != null) return widget.fetchTrackFn!(path);
    return widget.api.fetchTrackByPath(path);
  }

  Future<List<List<cm.Waypoint>>> _downloadTracks(List<String> paths) async {
    final out = <List<cm.Waypoint>>[];
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < paths.length) {
        final i = cursor++;
        try {
          final t = await _fetchTrack(paths[i]);
          if (t.isNotEmpty) {
            out.add(t);
            if (mounted) setState(() => _trackCount = out.length);
          }
        } catch (e) {
          // L4 best-effort — a single missing/corrupt blob must not abort
          // the whole heatmap. Skip and keep going.
          debugPrint('personal heatmap: track download failed: $e');
        }
      }
    }

    final n = paths.length < _downloadConcurrency
        ? paths.length
        : _downloadConcurrency;
    await Future.wait([for (var w = 0; w < n; w++) worker()]);
    return out;
  }

  Future<void> _build() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _empty = false;
        _errored = false;
      });
    }
    try {
      final runs = await _fetchRuns();
      final paths = <String>[];
      for (final r in runs) {
        final url = r.metadata?['track_url'] as String?;
        if (url != null && url.isNotEmpty) paths.add(url);
        if (paths.length >= _maxTracks) break;
      }
      _totalWithTracks = paths.length;
      if (paths.isEmpty) {
        if (mounted) setState(() => _empty = true);
        return;
      }
      final tracks = await _downloadTracks(paths);
      final heatTracks = [
        for (final t in tracks)
          [for (final w in t) HeatLatLng(w.lat, w.lng)],
      ];
      final cells = buildHeatCells(heatTracks);
      if (cells.isEmpty) {
        if (mounted) setState(() => _empty = true);
        return;
      }
      final lines = [
        for (final t in tracks)
          if (t.length >= 2) [for (final w in t) LatLng(w.lat, w.lng)],
      ];
      if (mounted) {
        setState(() {
          _cells = cells;
          _lines = lines;
          _bounds = heatBounds(cells);
        });
      }
      _fitToBounds();
    } catch (e) {
      debugPrint('personal heatmap build failed: $e');
      // A thrown build means we never learned whether the runner has mapped
      // runs — surface a retryable error, NOT the "no runs yet" empty state
      // (which would tell an active runner they've never run anywhere). If
      // some tracks already rendered, keep them.
      if (mounted && _trackCount == 0) setState(() => _errored = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fitToBounds() {
    final b = _bounds;
    if (!_mapReady || _didFit || b == null) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(b[0][1], b[0][0]),
            LatLng(b[1][1], b[1][0]),
          ),
          padding: const EdgeInsets.all(48),
          maxZoom: 14,
        ),
      );
      _didFit = true;
    } catch (e) {
      debugPrint('personal heatmap fit failed: $e');
    }
  }

  /// Heat-cloud opacity: full below [_fadeMin], gone by [_fadeMax].
  double get _heatOpacity {
    if (_zoom <= _fadeMin) return 0.85;
    if (_zoom >= _fadeMax) return 0;
    return 0.85 * (1 - (_zoom - _fadeMin) / (_fadeMax - _fadeMin));
  }

  /// Track-line opacity: the mirror image of the heat fade.
  double get _lineOpacity {
    if (_zoom <= _fadeMin) return 0;
    if (_zoom >= _fadeMax) return 0.55;
    return 0.55 * ((_zoom - _fadeMin) / (_fadeMax - _fadeMin));
  }

  Color _cellColor(int weight) {
    final t = (weight / kMaxCellWeight).clamp(0.0, 1.0);
    final base = t < 0.25
        ? const Color(0xFF3B82F6)
        : t < 0.5
            ? const Color(0xFF10B981)
            : t < 0.75
                ? const Color(0xFFF59E0B)
                : const Color(0xFFEF4444);
    return base.withValues(alpha: _heatOpacity * 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.runHeatmapTitle),
        actions: [
          // Labelled hand-off to the sibling surface: this screen is the
          // user's OWN tracks; the routes heatmap is the community map
          // (discoverable-route + club pins). Users looking for "the heatmap
          // like on web" land here first, so the sibling must be one
          // labelled tap away. pushReplacement keeps the stack flat.
          TextButton.icon(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => RoutesHeatmapScreen(api: widget.api),
              ),
            ),
            icon: const Icon(Icons.travel_explore, size: 18),
            label: Text(l10n.routesHeatmapTooltip),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(30, 0),
              initialZoom: 2,
              onMapReady: () {
                _mapReady = true;
                _zoom = _mapController.camera.zoom;
                _fitToBounds();
              },
              onPositionChanged: (pos, hasGesture) {
                if (pos.zoom != _zoom) {
                  setState(() => _zoom = pos.zoom);
                }
              },
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
              if (_heatOpacity > 0 && _cells.isNotEmpty)
                CircleLayer(
                  circles: [
                    for (final c in _cells)
                      CircleMarker(
                        point: LatLng(c.lat, c.lng),
                        radius: 6,
                        color: _cellColor(c.weight),
                        borderStrokeWidth: 0,
                      ),
                  ],
                ),
              if (_lineOpacity > 0 && _lines.isNotEmpty)
                PolylineLayer(
                  key: const ValueKey('personal-heatmap-lines'),
                  polylines: [
                    for (final line in _lines)
                      Polyline(
                        points: line,
                        strokeWidth: 2.5,
                        color: const Color(0xFF6366F1)
                            .withValues(alpha: _lineOpacity),
                      ),
                  ],
                ),
            ],
          ),
          if (_loading)
            Positioned(
              top: 12,
              left: 12,
              child: _Pill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _trackCount > 0
                            ? l10n.runHeatmapLoadingProgress(
                                _trackCount, _totalWithTracks)
                            : l10n.runHeatmapLoading,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_errored)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off,
                        size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    Text(l10n.runHeatmapErrorTitle,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      l10n.runHeatmapErrorBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => unawaited(_build()),
                      child: Text(l10n.runHeatmapRetry),
                    ),
                  ],
                ),
              ),
            )
          else if (_empty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department,
                        size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    Text(l10n.runHeatmapEmptyTitle,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      l10n.runHeatmapEmptyBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            Positioned(
              top: 12,
              left: 12,
              child: _Pill(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.runHeatmapLegendTitle,
                        style: theme.textTheme.labelLarge),
                    Text(
                      _trackCount == 1
                          ? l10n.runHeatmapLegendSummaryOne(_trackCount)
                          : l10n.runHeatmapLegendSummaryMany(_trackCount),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    const _LegendScale(),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.runHeatmapScaleLess,
                            style: theme.textTheme.labelSmall),
                        Text(l10n.runHeatmapScaleMore,
                            style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Widget child;
  const _Pill({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}

class _LegendScale extends StatelessWidget {
  const _LegendScale();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [
            Color(0xB33B82F6),
            Color(0xCC10B981),
            Color(0xD9F59E0B),
            Color(0xF2EF4444),
          ],
        ),
      ),
    );
  }
}
