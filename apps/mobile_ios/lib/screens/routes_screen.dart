import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gpx_parser/gpx_parser.dart';

import '../local_route_store.dart';
import '../preferences.dart';
import 'explore_routes_screen.dart';
import 'route_detail_screen.dart';

/// Page size for the cloud fetch + visible-list window. Same value as
/// runs_screen — `docs/conventions.md § Pagination` makes consistency
/// across surfaces a load-bearing rule.
const int _kRoutesPageSize = 20;

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

  const RoutesScreen({
    super.key,
    this.apiClient,
    required this.routeStore,
    required this.preferences,
    this.onStartRun,
  });

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  bool _syncing = false;
  List<cm.Route> _bookmarks = const [];

  /// How many merged rows the list reveals. Resets only on explicit
  /// reload — there are no inline filters on this screen, unlike runs.
  int _visibleCount = _kRoutesPageSize;
  bool _loadingMore = false;
  bool _remoteHasMore = true;

  @override
  void initState() {
    super.initState();
    widget.routeStore.addListener(_onChange);
    widget.preferences.addListener(_onChange);
    _fetchRemoteRoutes();
    _fetchBookmarks();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not sync routes — working offline')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load more routes')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleStar(cm.Route route) async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    final next = !route.isStarred;
    final updated = cm.Route(
      id: route.id,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update star: $e')),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              'Import failed: pick the file from local storage, '
              'not a cloud-only document picker.',
            )),
          );
        }
        return;
      }
      final ext = result.files.first.extension?.toLowerCase();
      final content = await File(path).readAsString();
      final route = await compute(_parseRouteFile, _RouteParseRequest(ext, content));
      await widget.routeStore.save(route);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported "${route.name}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    final owned = widget.routeStore.routes;
    final ownedIds = {for (final r in owned) r.id};
    final allRoutes = <cm.Route>[
      ...owned,
      ..._bookmarks.where((b) => !ownedIds.contains(b.id)),
    ];
    final routes = allRoutes.length <= _visibleCount
        ? allRoutes
        : allRoutes.sublist(0, _visibleCount);
    final showLoadMore = shouldShowRoutesLoadMore(
      visibleCount: _visibleCount,
      totalCount: allRoutes.length,
      remoteHasMore: _remoteHasMore,
      apiSignedIn: widget.apiClient?.userId != null,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Routes'),
        actions: [
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'routes_import_fab',
        onPressed: _importFile,
        icon: const Icon(Icons.upload_file),
        label: const Text('Import'),
      ),
      body: routes.isEmpty
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
              itemCount: routes.length + (showLoadMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (showLoadMore && index == routes.length) {
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
                final route = routes[index];
                final isOwned = ownedIds.contains(route.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: Icon(
                        isOwned ? Icons.route : Icons.bookmark,
                        color: theme.colorScheme.secondary,
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
            ),
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
