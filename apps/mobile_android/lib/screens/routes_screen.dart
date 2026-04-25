import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gpx_parser/gpx_parser.dart';

import '../local_route_store.dart';
import '../preferences.dart';
import 'explore_routes_screen.dart';
import 'route_detail_screen.dart';

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

  @override
  void initState() {
    super.initState();
    widget.routeStore.addListener(_onChange);
    widget.preferences.addListener(_onChange);
    _fetchRemoteRoutes();
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

  Future<void> _fetchRemoteRoutes() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    setState(() => _syncing = true);
    try {
      final remote = await api.getRoutes();
      for (final r in remote) {
        await widget.routeStore.save(r);
      }
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

  Future<void> _importFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx', 'kml'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final content = await file.readAsString();
    final ext = result.files.first.extension?.toLowerCase();

    try {
      cm.Route route;
      if (ext == 'kml') {
        route = RouteParser.fromKml(content);
      } else {
        route = RouteParser.fromGpx(content);
      }
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
    final routes = widget.routeStore.routes;

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
              itemCount: routes.length,
              itemBuilder: (context, index) {
                final route = routes[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: Icon(Icons.route,
                          color: theme.colorScheme.secondary),
                    ),
                    title: Text(route.name),
                    subtitle: Text(
                      '${UnitFormat.distance(route.distanceMetres, unit)}'
                      '  •  ${route.elevationGainMetres.round()}m gain',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final picked = await Navigator.push<cm.Route?>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RouteDetailScreen(
                            route: route,
                            routeStore: widget.routeStore,
                            preferences: widget.preferences,
                            apiClient: widget.apiClient,
                            isOwner: true,
                          ),
                        ),
                      );
                      if (picked != null) {
                        widget.onStartRun?.call(picked);
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
