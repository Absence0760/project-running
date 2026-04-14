import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';

import '../local_route_store.dart';
import '../preferences.dart';
import '../widgets/live_run_map.dart';

class RouteDetailScreen extends StatefulWidget {
  final cm.Route route;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final ApiClient? apiClient;

  const RouteDetailScreen({
    super.key,
    required this.route,
    required this.routeStore,
    required this.preferences,
    this.apiClient,
  });

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  late bool _isPublic = widget.route.isPublic;
  List<cm.RouteReviewRow> _reviews = [];
  bool _loadingReviews = false;
  bool _reviewsOffline = false;
  double _avgRating = 0;

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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _surfaceIcon(route.surface!),
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _surfaceLabel(route.surface!),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    if (_isPublic) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.public, size: 14,
                          color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        'PUBLIC',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
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
