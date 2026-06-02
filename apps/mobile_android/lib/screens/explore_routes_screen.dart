import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/gen/app_localizations.dart';
import '../local_route_store.dart';
import '../preferences.dart';
import '../backend_timeout.dart';
import '../widgets/error_state.dart';
import '../widgets/route_track_preview.dart';
import 'route_detail_screen.dart';
import '../widgets/top_banner.dart';

enum _ExploreMode { search, nearMe }

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
  _ExploreMode _mode = _ExploreMode.search;
  final Set<String> _selectedTags = {};
  bool _featuredOnly = false;
  String _sort = 'popular';
  List<String> _popularTags = const [];

  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Defer the first search to after the first frame: the signed-out
    // early-return reads AppLocalizations.of(context), which isn't
    // available synchronously during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search();
    });
    _loadPopularTags();
  }

  Future<void> _loadPopularTags() async {
    final api = widget.apiClient;
    if (api == null) return;
    try {
      final tags = await api.fetchPopularRouteTags();
      if (mounted) setState(() => _popularTags = tags);
    } catch (e) {
      debugPrint('fetchPopularRouteTags failed: $e');
    }
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
      setState(() =>
          _error = AppLocalizations.of(context).exploreRoutesSignInRequired);
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
        tags: _selectedTags.isEmpty ? null : _selectedTags.toList(),
        featuredOnly: _featuredOnly,
        sort: _sort,
        limit: _pageSize,
        offset: 0,
      ).timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _results = results;
        _hasMore = results.length >= _pageSize;
        _loading = false;
      });
    } on TimeoutException catch (e) {
      debugPrint('ExploreRoutesScreen._search timed out: $e');
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).exploreRoutesTimeout;
        _loading = false;
      });
    } catch (e, s) {
      debugPrint('ExploreRoutesScreen._search failed: $e\n$s');
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).exploreRoutesSearchFailed;
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
        tags: _selectedTags.isEmpty ? null : _selectedTags.toList(),
        featuredOnly: _featuredOnly,
        sort: _sort,
        limit: _pageSize,
        offset: _results.length,
      );
      if (!mounted) return;
      setState(() {
        _results.addAll(results);
        _hasMore = results.length >= _pageSize;
        _loading = false;
      });
    } catch (e, s) {
      debugPrint('ExploreRoutesScreen._loadMore failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _hasMore = false;
        });
        showTopBanner(context,
            AppLocalizations.of(context).exploreRoutesLoadMoreFailed);
      }
    }
  }

  Future<void> _searchNearby() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      setState(() =>
          _error = AppLocalizations.of(context).exploreRoutesSignInRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _hasMore = false;
    });

    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _error = AppLocalizations.of(context)
                .exploreRoutesLocationPermissionRequired;
            _loading = false;
          });
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final results = await api.nearbyPublicRoutes(
        lat: pos.latitude,
        lng: pos.longitude,
        radiusM: 50000,
        limit: 50,
      ).timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on TimeoutException catch (e) {
      debugPrint('ExploreRoutesScreen._searchNearby timed out: $e');
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).exploreRoutesTimeout;
        _loading = false;
      });
    } catch (e, s) {
      debugPrint('ExploreRoutesScreen._searchNearby failed: $e\n$s');
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).exploreRoutesNearbyFailed;
        _loading = false;
      });
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
    // Browse-list rows come back from `search_public_routes` /
    // `nearby_routes` / `routes_within_box` with no waypoints (the
    // public_routes view strips them — see migration
    // 20260703_001_public_routes_view.sql). Pull the privacy-zone-
    // clipped polyline via `fetchRouteById` before persisting so the
    // locally-cached copy doesn't carry the original author's
    // unclipped start coordinate. Owner-of-route gets their full
    // unclipped polyline through the same call. Audit/privacy-zones
    // High fix.
    final api = widget.apiClient;
    cm.Route toSave = route;
    // Browse rows carry no waypoints; the fetch is what makes the saved
    // copy usable. If it fails we must NOT persist a polyline-less route
    // and then claim success — that produced an empty-thumbnail "saved"
    // route that looked like the bookmark silently did nothing.
    var hasGeometry = route.waypoints.length >= 2;
    if (api != null) {
      try {
        final result = await api.fetchRouteById(route.id);
        if (result.route != null && result.route!.waypoints.length >= 2) {
          toSave = result.route!;
          hasGeometry = true;
        }
      } catch (e) {
        debugPrint('save-route clip fetch failed: $e');
      }
    }
    if (!hasGeometry) {
      if (!mounted) return;
      showTopBanner(
        context,
        AppLocalizations.of(context)
            .exploreRoutesSaveCheckConnection(route.name),
      );
      return;
    }
    try {
      await widget.routeStore.save(toSave);
    } catch (e) {
      debugPrint('save-route persist failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).exploreRoutesSaveFailed(route.name));
      return;
    }
    if (!mounted) return;
    showTopBanner(
        context, AppLocalizations.of(context).exploreRoutesSaved(route.name));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.exploreRoutesTitle)),
      body: Column(
        children: [
          // Mode toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<_ExploreMode>(
              segments: [
                ButtonSegment(
                  value: _ExploreMode.search,
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(l10n.exploreRoutesModeSearch),
                ),
                ButtonSegment(
                  value: _ExploreMode.nearMe,
                  icon: const Icon(Icons.near_me, size: 18),
                  label: Text(l10n.exploreRoutesModeNearMe),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() => _mode = s.first);
                if (_mode == _ExploreMode.nearMe) {
                  _searchNearby();
                } else {
                  _search();
                }
              },
            ),
          ),

          // Search bar (only in search mode)
          if (_mode == _ExploreMode.search)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.exploreRoutesSearchHint,
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

          // Filter chips (search mode only)
          if (_mode == _ExploreMode.search) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildDistanceChip(theme),
                    const SizedBox(width: 8),
                    _buildSurfaceChip(theme),
                    const SizedBox(width: 8),
                    _buildSortChip(theme),
                    const SizedBox(width: 8),
                    FilterChip(
                      avatar: const Icon(Icons.star_border, size: 16),
                      label: Text(l10n.exploreRoutesFeatured),
                      selected: _featuredOnly,
                      onSelected: (v) {
                        setState(() => _featuredOnly = v);
                        _search();
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (_popularTags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final t in _popularTags) ...[
                        FilterChip(
                          label: Text(t),
                          selected: _selectedTags.contains(t),
                          onSelected: (v) {
                            setState(() {
                              if (v) _selectedTags.add(t);
                              else _selectedTags.remove(t);
                            });
                            _search();
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
          ],

          const Divider(height: 1),

          // Results
          Expanded(child: _buildBody(theme, unit)),
        ],
      ),
    );
  }

  Widget _buildDistanceChip(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final mi = widget.preferences.useMiles;
    final labels = {
      _DistanceFilter.any: l10n.exploreRoutesDistanceAny,
      _DistanceFilter.short:
          mi ? l10n.exploreRoutesDistanceUnderMi : l10n.exploreRoutesDistanceUnderKm,
      _DistanceFilter.medium:
          mi ? l10n.exploreRoutesDistanceMidMi : l10n.exploreRoutesDistanceMidKm,
      _DistanceFilter.long:
          mi ? l10n.exploreRoutesDistanceLongMi : l10n.exploreRoutesDistanceLongKm,
      _DistanceFilter.ultra:
          mi ? l10n.exploreRoutesDistanceUltraMi : l10n.exploreRoutesDistanceUltraKm,
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

  Widget _buildSortChip(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      'popular': l10n.exploreRoutesSortMostRun,
      'newest': l10n.exploreRoutesSortNewest,
      'featured': l10n.exploreRoutesSortFeatured,
    };
    return PopupMenuButton<String>(
      onSelected: (v) {
        setState(() => _sort = v);
        _search();
      },
      itemBuilder: (_) => labels.entries
          .map((e) => CheckedPopupMenuItem(
                value: e.key,
                checked: _sort == e.key,
                child: Text(e.value),
              ))
          .toList(),
      child: Chip(
        avatar: const Icon(Icons.sort, size: 16),
        label: Text(labels[_sort] ?? l10n.exploreRoutesSort),
      ),
    );
  }

  Widget _buildSurfaceChip(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      _SurfaceFilter.any: l10n.exploreRoutesSurfaceAny,
      _SurfaceFilter.road: l10n.exploreRoutesSurfaceRoad,
      _SurfaceFilter.trail: l10n.exploreRoutesSurfaceTrail,
      _SurfaceFilter.mixed: l10n.exploreRoutesSurfaceMixed,
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
    final l10n = AppLocalizations.of(context);
    if (_error != null) {
      return ErrorState(
        message: _error!,
        onRetry: _mode == _ExploreMode.nearMe ? _searchNearby : _search,
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
                  ? l10n.exploreRoutesEmptyNoPublic
                  : l10n.exploreRoutesEmptyNoMatch,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.exploreRoutesEmptyBody,
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
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                height: 48,
                // Explore is community-public routes — every row is by
                // a non-owner. RouteTrackPreview's owner branch
                // short-circuits to raw waypoints if the rare case of
                // viewing your own published route arises.
                child: route.waypoints.length >= 2
                    ? RouteTrackPreview(
                        routeId: route.id,
                        waypoints: route.waypoints,
                        ownerUserId: route.userId,
                        api: ApiClient(),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _surfaceIcon(route.surface),
                          color: theme.colorScheme.secondary,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            route.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (route.featured)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.star,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _tag(Icons.straighten,
                            UnitFormat.distance(route.distanceMetres, unit)),
                        if (route.elevationGainMetres > 0)
                          _tag(Icons.trending_up,
                              '${route.elevationGainMetres.round()}m'),
                        if (route.surface != null)
                          _tag(_surfaceIcon(route.surface),
                              _surfaceLabel(l10n, route.surface)),
                        if (route.runCount > 0)
                          _tag(Icons.directions_run, '${route.runCount}'),
                      ],
                    ),
                    if (route.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final t in route.tags.take(4))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                t,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
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
                tooltip: alreadySaved
                    ? l10n.exploreRoutesAlreadySaved
                    : l10n.exploreRoutesSaveToLibrary,
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

  static String _surfaceLabel(AppLocalizations l10n, String? surface) {
    switch (surface) {
      case 'trail':
        return l10n.exploreRoutesSurfaceTrailShort;
      case 'mixed':
        return l10n.exploreRoutesSurfaceMixedShort;
      default:
        return l10n.exploreRoutesSurfaceRoadShort;
    }
  }
}
