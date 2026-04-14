import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';

import '../local_route_store.dart';
import '../preferences.dart';
import 'route_detail_screen.dart';

enum _DistanceFilter { any, short, medium, long, ultra }

enum _SurfaceFilter { any, road, trail, mixed }

class ExploreRoutesScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final void Function(cm.Route route)? onStartRun;

  const ExploreRoutesScreen({
    super.key,
    this.apiClient,
    required this.routeStore,
    required this.preferences,
    this.onStartRun,
  });

  @override
  State<ExploreRoutesScreen> createState() => _ExploreRoutesScreenState();
}

class _ExploreRoutesScreenState extends State<ExploreRoutesScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<cm.Route> _results = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  _DistanceFilter _distanceFilter = _DistanceFilter.any;
  _SurfaceFilter _surfaceFilter = _SurfaceFilter.any;

  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _search();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _search() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      setState(() => _error = 'Sign in and connect to the internet to explore routes');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _hasMore = true;
    });

    try {
      final results = await api.searchPublicRoutes(
        query: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        minDistanceM: _minDistance,
        maxDistanceM: _maxDistance,
        surface: _surfaceValue,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _hasMore = results.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Search failed: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final api = widget.apiClient;
    if (api == null || _loading || !_hasMore) return;

    setState(() => _loading = true);
    try {
      final results = await api.searchPublicRoutes(
        query: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        minDistanceM: _minDistance,
        maxDistanceM: _maxDistance,
        surface: _surfaceValue,
        limit: _pageSize,
        offset: _results.length,
      );
      if (!mounted) return;
      setState(() {
        _results.addAll(results);
        _hasMore = results.length >= _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load more — check your connection')),
        );
      }
    }
  }

  static const _metresPerMile = 1609.344;

  // Thresholds in metres — adapt to the user's unit so the buckets feel
  // natural in both km and miles.
  List<double> get _thresholds => widget.preferences.useMiles
      ? [3 * _metresPerMile, 6 * _metresPerMile, 13 * _metresPerMile]
      : [5000, 10000, 21000];

  double? get _minDistance {
    final t = _thresholds;
    switch (_distanceFilter) {
      case _DistanceFilter.any:
      case _DistanceFilter.short:
        return null;
      case _DistanceFilter.medium:
        return t[0];
      case _DistanceFilter.long:
        return t[1];
      case _DistanceFilter.ultra:
        return t[2];
    }
  }

  double? get _maxDistance {
    final t = _thresholds;
    switch (_distanceFilter) {
      case _DistanceFilter.any:
        return null;
      case _DistanceFilter.short:
        return t[0];
      case _DistanceFilter.medium:
        return t[1];
      case _DistanceFilter.long:
        return t[2];
      case _DistanceFilter.ultra:
        return null;
    }
  }

  String? get _surfaceValue {
    switch (_surfaceFilter) {
      case _SurfaceFilter.any:
        return null;
      case _SurfaceFilter.road:
        return 'road';
      case _SurfaceFilter.trail:
        return 'trail';
      case _SurfaceFilter.mixed:
        return 'mixed';
    }
  }

  Future<void> _saveRoute(cm.Route route) async {
    await widget.routeStore.save(route);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "${route.name}" to your library')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;

    return Scaffold(
      appBar: AppBar(title: const Text('Explore Routes')),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search routes by name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _search();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
            ),
          ),

          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildDistanceChip(theme),
                  const SizedBox(width: 8),
                  _buildSurfaceChip(theme),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // Results
          Expanded(child: _buildBody(theme, unit)),
        ],
      ),
    );
  }

  Widget _buildDistanceChip(ThemeData theme) {
    final mi = widget.preferences.useMiles;
    final labels = {
      _DistanceFilter.any: 'Any distance',
      _DistanceFilter.short: mi ? 'Under 3 mi' : 'Under 5 km',
      _DistanceFilter.medium: mi ? '3-6 mi' : '5-10 km',
      _DistanceFilter.long: mi ? '6-13 mi' : '10-21 km',
      _DistanceFilter.ultra: mi ? '13 mi+' : '21 km+',
    };
    return PopupMenuButton<_DistanceFilter>(
      onSelected: (v) {
        setState(() => _distanceFilter = v);
        _search();
      },
      itemBuilder: (_) => _DistanceFilter.values
          .map((f) => CheckedPopupMenuItem(
                value: f,
                checked: _distanceFilter == f,
                child: Text(labels[f]!),
              ))
          .toList(),
      child: Chip(
        avatar: const Icon(Icons.straighten, size: 16),
        label: Text(labels[_distanceFilter]!),
        backgroundColor: _distanceFilter != _DistanceFilter.any
            ? theme.colorScheme.primaryContainer
            : null,
      ),
    );
  }

  Widget _buildSurfaceChip(ThemeData theme) {
    final labels = {
      _SurfaceFilter.any: 'Any surface',
      _SurfaceFilter.road: 'Road',
      _SurfaceFilter.trail: 'Trail',
      _SurfaceFilter.mixed: 'Mixed',
    };
    return PopupMenuButton<_SurfaceFilter>(
      onSelected: (v) {
        setState(() => _surfaceFilter = v);
        _search();
      },
      itemBuilder: (_) => _SurfaceFilter.values
          .map((f) => CheckedPopupMenuItem(
                value: f,
                checked: _surfaceFilter == f,
                child: Text(labels[f]!),
              ))
          .toList(),
      child: Chip(
        avatar: const Icon(Icons.terrain, size: 16),
        label: Text(labels[_surfaceFilter]!),
        backgroundColor: _surfaceFilter != _SurfaceFilter.any
            ? theme.colorScheme.primaryContainer
            : null,
      ),
    );
  }

  Widget _buildBody(ThemeData theme, DistanceUnit unit) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty && !_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No public routes yet'
                  : 'No routes match your search',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Routes shared from the web app appear here',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _results.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final route = _results[index];
        final alreadySaved = widget.routeStore.routes.any((r) =>
            r.id == route.id || r.name == route.name);

        return _RouteCard(
          route: route,
          unit: unit,
          theme: theme,
          alreadySaved: alreadySaved,
          onTap: () async {
            final picked = await Navigator.push<cm.Route?>(
              context,
              MaterialPageRoute(
                builder: (_) => RouteDetailScreen(
                  route: route,
                  routeStore: widget.routeStore,
                  preferences: widget.preferences,
                  apiClient: widget.apiClient,
                ),
              ),
            );
            if (picked != null) widget.onStartRun?.call(picked);
          },
          onSave: () => _saveRoute(route),
        );
      },
    );
  }
}

class _RouteCard extends StatelessWidget {
  final cm.Route route;
  final DistanceUnit unit;
  final ThemeData theme;
  final bool alreadySaved;
  final VoidCallback onTap;
  final VoidCallback onSave;

  const _RouteCard({
    required this.route,
    required this.unit,
    required this.theme,
    required this.alreadySaved,
    required this.onTap,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _surfaceIcon(route.surface),
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _tag(Icons.straighten,
                            UnitFormat.distance(route.distanceMetres, unit)),
                        const SizedBox(width: 12),
                        if (route.elevationGainMetres > 0)
                          _tag(Icons.trending_up,
                              '${route.elevationGainMetres.round()}m'),
                        if (route.surface != null) ...[
                          const SizedBox(width: 12),
                          _tag(_surfaceIcon(route.surface),
                              _surfaceLabel(route.surface)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  alreadySaved ? Icons.bookmark : Icons.bookmark_border,
                  color: alreadySaved
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                tooltip: alreadySaved ? 'Already saved' : 'Save to library',
                onPressed: alreadySaved ? null : onSave,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.outline),
        const SizedBox(width: 3),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  static IconData _surfaceIcon(String? surface) {
    switch (surface) {
      case 'trail':
        return Icons.terrain;
      case 'mixed':
        return Icons.alt_route;
      default:
        return Icons.route;
    }
  }

  static String _surfaceLabel(String? surface) {
    switch (surface) {
      case 'trail':
        return 'Trail';
      case 'mixed':
        return 'Mixed';
      default:
        return 'Road';
    }
  }
}
