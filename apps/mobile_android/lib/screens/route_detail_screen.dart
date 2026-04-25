import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../local_route_store.dart';
import '../preferences.dart';
import '../widgets/live_run_map.dart';

class RouteDetailScreen extends StatefulWidget {
  final cm.Route route;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final ApiClient? apiClient;
  /// Whether the current user owns this route. Callers opening from
  /// their own library pass `true`; the Explore tab opens read-only.
  final bool isOwner;

  const RouteDetailScreen({
    super.key,
    required this.route,
    required this.routeStore,
    required this.preferences,
    this.apiClient,
    this.isOwner = false,
  });

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  late bool _isPublic = widget.route.isPublic;
  late List<String> _tags = List.from(widget.route.tags);
  List<cm.RouteReviewRow> _reviews = [];
  bool _loadingReviews = false;
  bool _reviewsOffline = false;
  double _avgRating = 0;

  bool get _isOwner => widget.isOwner && widget.apiClient?.userId != null;

  Widget _inlineMeta(ThemeData theme, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchReviews();
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
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    final newValue = !_isPublic;
    setState(() => _isPublic = newValue);
    try {
      await api.setRoutePublic(widget.route.id, newValue);
    } catch (_) {
      if (mounted) setState(() => _isPublic = !newValue);
    }
  }

  Future<void> _submitReview() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to leave a review')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit review: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    final route = widget.route;
    final isOwner = widget.apiClient?.userId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(route.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share as GPX',
            onPressed: () => _shareAsGpx(context),
          ),
          if (isOwner)
            IconButton(
              icon: Icon(_isPublic ? Icons.public : Icons.public_off),
              tooltip: _isPublic ? 'Make private' : 'Make public',
              onPressed: _togglePublic,
            ),
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
                plannedRoute: route.waypoints,
                followRunner: false,
              ),
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

            if (route.surface != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _inlineMeta(
                      theme,
                      _surfaceIcon(route.surface!),
                      _surfaceLabel(route.surface!),
                    ),
                    if (_isPublic)
                      _inlineMeta(theme, Icons.public, 'PUBLIC'),
                    if (route.runCount > 0)
                      _inlineMeta(
                        theme,
                        Icons.directions_run,
                        '${route.runCount} ${route.runCount == 1 ? 'RUN' : 'RUNS'}',
                      ),
                    if (route.featured)
                      _inlineMeta(theme, Icons.star, 'FEATURED'),
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

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, route),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF22C55E),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(
                    'Start run with this route',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareAsGpx(BuildContext context) async {
    final route = widget.route;
    try {
      final tmp = await getTemporaryDirectory();
      final safe = route.name
              .replaceAll(RegExp(r'[^a-zA-Z0-9-_ ]'), '')
              .replaceAll(RegExp(r'\s+'), '_');
      final filename = (safe.isEmpty ? 'route' : safe);
      final file = File('${tmp.path}/$filename.gpx');
      await file.writeAsString(_routeToGpx(route));
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/gpx+xml')],
        text: route.name,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share GPX: $e')),
        );
      }
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
    if (ok == true) {
      await widget.routeStore.delete(widget.route.id);
      if (context.mounted) Navigator.pop(context);
    }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save tag: $e')),
        );
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
