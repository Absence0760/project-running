import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gpx_parser/gpx_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local_route_store.dart';
import '../preferences.dart';
import '../widgets/route_track_preview.dart';
import 'explore_routes_screen.dart';
import 'routes_heatmap_screen.dart';
import 'route_builder_screen.dart';
import 'route_detail_screen.dart';
import '../widgets/top_banner.dart';

/// Page size for the cloud fetch + visible-list window. Same value as
/// runs_screen — `docs/conventions.md § Pagination` makes consistency
/// across surfaces a load-bearing rule.
const int _kRoutesPageSize = 20;

/// SharedPreferences key for the persisted filter blob (search /
/// surface / distance / sort / starredOnly). Matches the web app's
/// localStorage key so the convention is the same on every surface.
const String _kRoutesFiltersKey = 'routes_filters_v1';

enum _RouteSort { newest, longest, shortest, mostRun, az }

enum _DistanceBucket { any, lt5, t5to10, t10to20, gt20 }

enum _SurfaceFilter { any, road, trail, mixed }

/// True when the Load-more button should render at the bottom of the
/// routes list — either the merged local+bookmark superset has more
/// rows beyond `visibleCount`, or the cloud might have older owned
/// routes. Pure helper kept top-level so unit tests can assert the
/// boundary conditions without mounting the screen. Mirrors
/// `shouldShowRunsLoadMore` in runs_screen.dart.
@visibleForTesting
bool shouldShowRoutesLoadMore({
  required int visibleCount,
  required int totalCount,
  required bool remoteHasMore,
  required bool apiSignedIn,
}) {
  if (visibleCount < totalCount) return true;
  return remoteHasMore && apiSignedIn;
}

/// Route library: imported and synced routes.
class RoutesScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final void Function(cm.Route route)? onStartRun;
  /// When true, the screen renders only its body — the parent (e.g.
  /// `SocialScreen`) owns the Scaffold/AppBar/FAB chrome. The dual
  /// "Build" / "Import" FAB column is exposed via [RoutesScreenState.buildRouteFabs]
  /// so the parent can hoist it on demand. Same pattern as
  /// `ClubsScreen.embedded`.
  final bool embedded;

  const RoutesScreen({
    super.key,
    this.apiClient,
    required this.routeStore,
    required this.preferences,
    this.onStartRun,
    this.embedded = false,
  });

  @override
  State<RoutesScreen> createState() => RoutesScreenState();
}

class RoutesScreenState extends State<RoutesScreen> {
  bool _syncing = false;
  List<cm.Route> _bookmarks = const [];

  /// How many merged rows the list reveals. Resets to one page when
  /// the filter state changes so a narrowed view starts at page 1.
  int _visibleCount = _kRoutesPageSize;
  bool _loadingMore = false;
  bool _remoteHasMore = true;

  // Filter state — mirrors the web `/routes` toolbar. The
  // post-filter list feeds the visible-window paging.
  String _search = '';
  _SurfaceFilter _surfaceFilter = _SurfaceFilter.any;
  _DistanceBucket _distanceFilter = _DistanceBucket.any;
  _RouteSort _sort = _RouteSort.newest;
  bool _starredOnly = false;

  @override
  void initState() {
    super.initState();
    widget.routeStore.addListener(_onChange);
    widget.preferences.addListener(_onChange);
    _fetchRemoteRoutes();
    _fetchBookmarks();
    _hydrateFilters();
  }

  @override
  void dispose() {
    widget.routeStore.removeListener(_onChange);
    widget.preferences.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchBookmarks() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    try {
      final marks = await api.fetchBookmarkedRoutes();
      if (!mounted) return;
      setState(() => _bookmarks = marks);
    } catch (_) {
      // Best-effort; the owned list still renders.
    }
  }

  Future<void> _fetchRemoteRoutes() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    setState(() => _syncing = true);
    try {
      // Initial sync pulls only the first page — older routes flow in
      // through Load more. Cap mirrors `_kRoutesPageSize` so a returning
      // user sees the same shape as the web `/routes` first paint.
      final remote = await api.getRoutes(limit: _kRoutesPageSize);
      await widget.routeStore.saveBatch(remote);
      if (!mounted) return;
      setState(() => _remoteHasMore = remote.length == _kRoutesPageSize);
    } catch (e) {
      debugPrint('Fetch routes failed: $e');
      if (mounted) {
        showTopBanner(context, 'Could not sync routes — working offline');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Reveal the next page. Same two-layer shape as runs_screen: bump
  /// the local visibility window first, only hit the cloud once we've
  /// shown everything cached.
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final owned = widget.routeStore.routes;
    final ownedIds = {for (final r in owned) r.id};
    final mergedCount =
        owned.length + _bookmarks.where((b) => !ownedIds.contains(b.id)).length;

    if (_visibleCount < mergedCount) {
      setState(() => _visibleCount += _kRoutesPageSize);
      // After revealing locally, opportunistically fetch the next cloud
      // page if we just hit the bottom and the cloud might have more.
      if (_visibleCount >= mergedCount && _remoteHasMore) {
        await _fetchOlderFromRemote();
      }
      return;
    }

    if (_remoteHasMore) {
      await _fetchOlderFromRemote();
    }
  }

  Future<void> _fetchOlderFromRemote() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      if (mounted) setState(() => _remoteHasMore = false);
      return;
    }

    setState(() => _loadingMore = true);
    try {
      // Cursor over the *oldest owned* route's created_at — bookmarked
      // routes share createdAt with the original author and would
      // produce false cursors. Owned routes are the only thing
      // getRoutes() returns anyway.
      final owned = widget.routeStore.routes;
      final cursor = owned.isEmpty || owned.last.createdAt == null
          ? DateTime.now()
          : owned.last.createdAt!;
      final remote = await api.getRoutes(
        limit: _kRoutesPageSize,
        before: cursor,
      );
      await widget.routeStore.saveBatch(remote);
      if (!mounted) return;
      setState(() {
        _remoteHasMore = remote.length == _kRoutesPageSize;
        _visibleCount += _kRoutesPageSize;
      });
    } catch (e) {
      debugPrint('Load more routes failed: $e');
      if (mounted) {
        showTopBanner(context, 'Could not load more routes');
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Restore filter state from SharedPreferences. Best-effort — a
  /// malformed blob is ignored and defaults stand. Mirrors the web
  /// app's runs/routes hydration shape.
  Future<void> _hydrateFilters() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kRoutesFiltersKey);
      if (raw == null || !mounted) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final search = j['search'];
      final surface = j['surface'];
      final distance = j['distance'];
      final sort = j['sort'];
      final starred = j['starredOnly'];
      setState(() {
        if (search is String) _search = search;
        if (surface is String) {
          _surfaceFilter = _SurfaceFilter.values.firstWhere(
            (e) => e.name == surface,
            orElse: () => _SurfaceFilter.any,
          );
        }
        if (distance is String) {
          _distanceFilter = _DistanceBucket.values.firstWhere(
            (e) => e.name == distance,
            orElse: () => _DistanceBucket.any,
          );
        }
        if (sort is String) {
          _sort = _RouteSort.values.firstWhere(
            (e) => e.name == sort,
            orElse: () => _sort,
          );
        }
        if (starred is bool) _starredOnly = starred;
        // Reset paging — the filtered list might be smaller.
        _visibleCount = _kRoutesPageSize;
      });
    } catch (_) {
      // Corrupt blob; leave defaults.
    }
  }

  void _persistFilters() {
    SharedPreferences.getInstance().then((p) {
      p.setString(
        _kRoutesFiltersKey,
        jsonEncode({
          'search': _search,
          'surface': _surfaceFilter.name,
          'distance': _distanceFilter.name,
          'sort': _sort.name,
          'starredOnly': _starredOnly,
        }),
      );
    }).catchError((Object _) {
      // L4 best-effort — never escalate.
    });
  }

  bool _filtersActive() =>
      _search.trim().isNotEmpty ||
      _surfaceFilter != _SurfaceFilter.any ||
      _distanceFilter != _DistanceBucket.any ||
      _starredOnly;

  void _clearFilters() {
    setState(() {
      _search = '';
      _surfaceFilter = _SurfaceFilter.any;
      _distanceFilter = _DistanceBucket.any;
      _starredOnly = false;
      _visibleCount = _kRoutesPageSize;
    });
    _persistFilters();
  }

  static bool _inDistanceBucket(double meters, _DistanceBucket b) {
    final km = meters / 1000;
    switch (b) {
      case _DistanceBucket.any:
        return true;
      case _DistanceBucket.lt5:
        return km < 5;
      case _DistanceBucket.t5to10:
        return km >= 5 && km < 10;
      case _DistanceBucket.t10to20:
        return km >= 10 && km < 20;
      case _DistanceBucket.gt20:
        return km >= 20;
    }
  }

  /// Apply the current filter + sort to the merged owned + bookmarks
  /// list. Pure pass over the input — no setState, no I/O.
  List<cm.Route> _filteredAndSorted(List<cm.Route> all) {
    final q = _search.trim().toLowerCase();
    Iterable<cm.Route> stream = all;
    if (_starredOnly) stream = stream.where((r) => r.isStarred);
    if (_surfaceFilter != _SurfaceFilter.any) {
      stream = stream.where((r) => r.surface == _surfaceFilter.name);
    }
    if (_distanceFilter != _DistanceBucket.any) {
      stream = stream
          .where((r) => _inDistanceBucket(r.distanceMetres, _distanceFilter));
    }
    if (q.isNotEmpty) {
      stream = stream.where((r) => r.name.toLowerCase().contains(q));
    }
    final out = stream.toList();
    switch (_sort) {
      case _RouteSort.newest:
        out.sort((a, b) {
          final ax = a.createdAt;
          final bx = b.createdAt;
          if (ax == null && bx == null) return 0;
          if (ax == null) return 1;
          if (bx == null) return -1;
          return bx.compareTo(ax);
        });
      case _RouteSort.longest:
        out.sort((a, b) => b.distanceMetres.compareTo(a.distanceMetres));
      case _RouteSort.shortest:
        out.sort((a, b) => a.distanceMetres.compareTo(b.distanceMetres));
      case _RouteSort.mostRun:
        out.sort((a, b) => b.runCount.compareTo(a.runCount));
      case _RouteSort.az:
        out.sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return out;
  }

  Future<void> _toggleStar(cm.Route route) async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    final next = !route.isStarred;
    final updated = cm.Route(
      id: route.id,
      userId: route.userId,
      name: route.name,
      waypoints: route.waypoints,
      distanceMetres: route.distanceMetres,
      elevationGainMetres: route.elevationGainMetres,
      isPublic: route.isPublic,
      createdAt: route.createdAt,
      surface: route.surface,
      tags: route.tags,
      featured: route.featured,
      runCount: route.runCount,
      isStarred: next,
    );
    await widget.routeStore.save(updated);
    try {
      await api.setRouteStar(route.id, next);
    } catch (e) {
      await widget.routeStore.save(route);
      if (mounted) {
        showTopBanner(context, 'Could not update star: $e');
      }
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx', 'kml'],
    );
    if (result == null || result.files.isEmpty) return;

    try {
      // path can be null when the picker hands back a content URI it
      // couldn't resolve to a real file (Drive / OneDrive document
      // providers do this). readAsString may also throw on permission
      // errors or if the user revokes access mid-read — both stay
      // inside the try so the snackbar handles them, not an uncaught
      // unhandled-async-error crash.
      final path = result.files.first.path;
      if (path == null) {
        if (mounted) {
          showTopBanner(context, 'Import failed: pick the file from local storage, '
              'not a cloud-only document picker.',);
        }
        return;
      }
      final ext = result.files.first.extension?.toLowerCase();
      final content = await File(path).readAsString();
      final route = await compute(_parseRouteFile, _RouteParseRequest(ext, content));
      await widget.routeStore.save(route);
      if (mounted) {
        showTopBanner(context, 'Imported "${route.name}"');
      }
    } catch (e) {
      if (mounted) {
        showTopBanner(context, 'Import failed: $e');
      }
    }
  }

  Future<void> _openBuilder() async {
    final api = widget.apiClient;
    if (api == null) return;
    final created = await Navigator.of(context).push<cm.Route>(
      MaterialPageRoute(
        builder: (_) => RouteBuilderScreen(
          apiClient: api,
          routeStore: widget.routeStore,
        ),
      ),
    );
    if (created != null && mounted) {
      showTopBanner(context, 'Saved "${created.name}"');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    final owned = widget.routeStore.routes;
    final ownedIds = {for (final r in owned) r.id};
    final mergedRoutes = <cm.Route>[
      ...owned,
      ..._bookmarks.where((b) => !ownedIds.contains(b.id)),
    ];
    // Filter pass first; pagination is computed against the filtered
    // list (a search of "trail" with 30 matches still pages 20 at a
    // time rather than locking the whole library to the screen).
    final filtered = _filteredAndSorted(mergedRoutes);
    final routes = filtered.length <= _visibleCount
        ? filtered
        : filtered.sublist(0, _visibleCount);
    final showLoadMore = shouldShowRoutesLoadMore(
      visibleCount: _visibleCount,
      totalCount: filtered.length,
      remoteHasMore: _remoteHasMore,
      apiSignedIn: widget.apiClient?.userId != null,
    );
    final emptyAfterFilter =
        mergedRoutes.isNotEmpty && filtered.isEmpty;

    final body = mergedRoutes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route, size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('No routes yet', style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Tap Import to add a GPX or KML file',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 1 +
                  (emptyAfterFilter ? 1 : routes.length) +
                  (showLoadMore && !emptyAfterFilter ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _RoutesFilterHeader(
                    search: _search,
                    surfaceFilter: _surfaceFilter,
                    distanceFilter: _distanceFilter,
                    sort: _sort,
                    starredOnly: _starredOnly,
                    visibleCount: routes.length,
                    totalCount: mergedRoutes.length,
                    filtersActive: _filtersActive(),
                    onSearchChanged: (v) {
                      setState(() {
                        _search = v;
                        _visibleCount = _kRoutesPageSize;
                      });
                      _persistFilters();
                    },
                    onSurfaceChanged: (v) {
                      setState(() {
                        _surfaceFilter = v;
                        _visibleCount = _kRoutesPageSize;
                      });
                      _persistFilters();
                    },
                    onDistanceChanged: (v) {
                      setState(() {
                        _distanceFilter = v;
                        _visibleCount = _kRoutesPageSize;
                      });
                      _persistFilters();
                    },
                    onSortChanged: (v) {
                      setState(() {
                        _sort = v;
                        _visibleCount = _kRoutesPageSize;
                      });
                      _persistFilters();
                    },
                    onStarredOnlyToggled: () {
                      setState(() {
                        _starredOnly = !_starredOnly;
                        _visibleCount = _kRoutesPageSize;
                      });
                      _persistFilters();
                    },
                    onClearFilters: _clearFilters,
                  );
                }
                if (emptyAfterFilter && index == 1) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Icon(Icons.filter_alt_off,
                            size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          'No routes match these filters',
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _clearFilters,
                          child: const Text('Clear filters'),
                        ),
                      ],
                    ),
                  );
                }
                final routeIndex = index - 1;
                if (showLoadMore && routeIndex == routes.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: _loadingMore
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : OutlinedButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more),
                              label: const Text('Load $_kRoutesPageSize more'),
                            ),
                    ),
                  );
                }
                final route = routes[routeIndex];
                final isOwned = ownedIds.contains(route.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: route.waypoints.length >= 2 && widget.apiClient != null
                        ? SizedBox(
                            width: 72,
                            height: 40,
                            // Bookmarked rows are owned by other users — must
                            // route through clip_route_for_viewer for non-owner
                            // viewers (decisions §33). Owner branch in
                            // RouteTrackPreview short-circuits to the raw row
                            // waypoints, so owned rows still render directly.
                            child: RouteTrackPreview(
                              routeId: route.id,
                              waypoints: route.waypoints,
                              ownerUserId: route.userId,
                              api: widget.apiClient!,
                            ),
                          )
                        : SizedBox(
                            width: 56,
                            height: 40,
                            child: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              child: Icon(
                                isOwned ? Icons.route : Icons.bookmark,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ),
                    title: Text(route.name),
                    subtitle: Text(
                      '${UnitFormat.distance(route.distanceMetres, unit)}'
                      '  •  ${route.elevationGainMetres.round()}m gain'
                      '${isOwned ? '' : '  •  Saved'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isOwned)
                          IconButton(
                            icon: Icon(
                              route.isStarred ? Icons.star : Icons.star_border,
                              color: route.isStarred
                                  ? const Color(0xFFFBBF24)
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            tooltip: route.isStarred
                                ? 'Unstar route'
                                : 'Star to show on watch',
                            onPressed: () => _toggleStar(route),
                          ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () async {
                      final picked = await Navigator.push<cm.Route?>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RouteDetailScreen(
                            route: route,
                            routeStore: widget.routeStore,
                            preferences: widget.preferences,
                            apiClient: widget.apiClient,
                            isOwner: isOwned,
                          ),
                        ),
                      );
                      if (picked != null) {
                        widget.onStartRun?.call(picked);
                      }
                      // Refresh bookmarks so unbookmarks made on the
                      // detail screen flow back into the list.
                      _fetchBookmarks();
                    },
                  ),
                );
              },
            );

    if (widget.embedded) {
      // Embedded mode: SocialScreen owns the Scaffold + the FAB. The
      // action buttons (Explore / Heatmap / Sync) move into an inline
      // toolbar row above the list — same pattern as `dashboard_screen`.
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _buildActions(context),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: _buildActions(context),
      ),
      floatingActionButton: buildRouteFabs(context),
      body: body,
    );
  }

  /// Inline action buttons: Explore (browse public routes), Heatmap,
  /// and a Sync indicator. Used by both the standalone AppBar (when
  /// `embedded: false`) and the inline toolbar row (when embedded).
  List<Widget> _buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.explore),
        tooltip: 'Explore public routes',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ExploreRoutesScreen(
                apiClient: widget.apiClient,
                routeStore: widget.routeStore,
                preferences: widget.preferences,
                onStartRun: widget.onStartRun,
              ),
            ),
          );
        },
      ),
      if (widget.apiClient != null)
        IconButton(
          icon: const Icon(Icons.local_fire_department_outlined),
          tooltip: 'Routes heatmap',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RoutesHeatmapScreen(
                api: widget.apiClient!,
              ),
            ),
          ),
        ),
      if (_syncing)
        const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      else if (widget.apiClient?.userId != null)
        IconButton(
          icon: const Icon(Icons.cloud_download),
          tooltip: 'Sync from cloud',
          onPressed: _fetchRemoteRoutes,
        ),
    ];
  }

  /// Dual-FAB column ("Build" + "Import"). Public so the embedded host
  /// (`SocialScreen`) can hoist it into its own Scaffold's
  /// `floatingActionButton` slot when the Routes sub-tab is active.
  Widget buildRouteFabs(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (widget.apiClient != null)
          FloatingActionButton.extended(
            heroTag: 'routes_build_fab',
            onPressed: _openBuilder,
            icon: const Icon(Icons.add_location_alt),
            label: const Text('Build'),
          ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'routes_import_fab',
          onPressed: _importFile,
          icon: const Icon(Icons.upload_file),
          label: const Text('Import'),
        ),
      ],
    );
  }
}

class _RouteParseRequest {
  final String? ext;
  final String content;
  const _RouteParseRequest(this.ext, this.content);
}

cm.Route _parseRouteFile(_RouteParseRequest req) {
  if (req.ext == 'kml') return RouteParser.fromKml(req.content);
  return RouteParser.fromGpx(req.content);
}

/// Filter toolbar for the routes list. Stateless — every change goes
/// through callbacks back to the screen so persistence + paging reset
/// stay in one place. Layout matches the web `/routes` toolbar:
/// search, surface, distance, sort, starred toggle, then a
/// visible-count meta row with Clear filters when active.
class _RoutesFilterHeader extends StatefulWidget {
  final String search;
  final _SurfaceFilter surfaceFilter;
  final _DistanceBucket distanceFilter;
  final _RouteSort sort;
  final bool starredOnly;
  final int visibleCount;
  final int totalCount;
  final bool filtersActive;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_SurfaceFilter> onSurfaceChanged;
  final ValueChanged<_DistanceBucket> onDistanceChanged;
  final ValueChanged<_RouteSort> onSortChanged;
  final VoidCallback onStarredOnlyToggled;
  final VoidCallback onClearFilters;

  const _RoutesFilterHeader({
    required this.search,
    required this.surfaceFilter,
    required this.distanceFilter,
    required this.sort,
    required this.starredOnly,
    required this.visibleCount,
    required this.totalCount,
    required this.filtersActive,
    required this.onSearchChanged,
    required this.onSurfaceChanged,
    required this.onDistanceChanged,
    required this.onSortChanged,
    required this.onStarredOnlyToggled,
    required this.onClearFilters,
  });

  @override
  State<_RoutesFilterHeader> createState() => _RoutesFilterHeaderState();
}

class _RoutesFilterHeaderState extends State<_RoutesFilterHeader> {
  late final TextEditingController _searchCtl;

  @override
  void initState() {
    super.initState();
    _searchCtl = TextEditingController(text: widget.search);
  }

  @override
  void didUpdateWidget(covariant _RoutesFilterHeader old) {
    super.didUpdateWidget(old);
    // Only stomp the controller when an external reset (Clear filters)
    // changes the prop out from under us — otherwise the user's typing
    // would lose the cursor position on every keystroke roundtrip.
    if (widget.search != _searchCtl.text) {
      _searchCtl.value = TextEditingValue(
        text: widget.search,
        selection: TextSelection.collapsed(offset: widget.search.length),
      );
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  static String _surfaceLabel(_SurfaceFilter v) {
    switch (v) {
      case _SurfaceFilter.any:
        return 'Any surface';
      case _SurfaceFilter.road:
        return 'Road';
      case _SurfaceFilter.trail:
        return 'Trail';
      case _SurfaceFilter.mixed:
        return 'Mixed';
    }
  }

  static String _distanceLabel(_DistanceBucket v) {
    switch (v) {
      case _DistanceBucket.any:
        return 'Any distance';
      case _DistanceBucket.lt5:
        return '< 5 km';
      case _DistanceBucket.t5to10:
        return '5–10 km';
      case _DistanceBucket.t10to20:
        return '10–20 km';
      case _DistanceBucket.gt20:
        return '20+ km';
    }
  }

  static String _sortLabel(_RouteSort v) {
    switch (v) {
      case _RouteSort.newest:
        return 'Newest first';
      case _RouteSort.longest:
        return 'Longest';
      case _RouteSort.shortest:
        return 'Shortest';
      case _RouteSort.mostRun:
        return 'Most-run';
      case _RouteSort.az:
        return 'A–Z';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtl,
            onChanged: widget.onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchCtl.clear();
                        widget.onSearchChanged('');
                      },
                    ),
              hintText: 'Search routes by name…',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _DropdownChip<_SurfaceFilter>(
                value: widget.surfaceFilter,
                items: _SurfaceFilter.values,
                labelOf: _surfaceLabel,
                onChanged: widget.onSurfaceChanged,
              ),
              _DropdownChip<_DistanceBucket>(
                value: widget.distanceFilter,
                items: _DistanceBucket.values,
                labelOf: _distanceLabel,
                onChanged: widget.onDistanceChanged,
              ),
              _DropdownChip<_RouteSort>(
                value: widget.sort,
                items: _RouteSort.values,
                labelOf: _sortLabel,
                onChanged: widget.onSortChanged,
              ),
              FilterChip(
                label: const Text('Starred'),
                avatar: Icon(
                  widget.starredOnly ? Icons.star : Icons.star_border,
                  size: 18,
                  color: widget.starredOnly
                      ? const Color(0xFFFBBF24)
                      : theme.colorScheme.onSurfaceVariant,
                ),
                selected: widget.starredOnly,
                onSelected: (_) => widget.onStarredOnlyToggled(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${widget.visibleCount} of ${widget.totalCount} '
                '${widget.totalCount == 1 ? 'route' : 'routes'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (widget.filtersActive)
                TextButton(
                  onPressed: widget.onClearFilters,
                  child: const Text('Clear filters'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact dropdown rendered as a chip — used for surface / distance /
/// sort so they share the wrap row visually with the starred toggle.
class _DropdownChip<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const _DropdownChip({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          style: theme.textTheme.bodyMedium,
          items: [
            for (final v in items)
              DropdownMenuItem(value: v, child: Text(labelOf(v))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
