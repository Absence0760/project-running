import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';

import '../local_route_store.dart';
import '../preferences.dart';
import '../widgets/live_run_map.dart';

/// Detail view for a saved route — shows the map, stats, and a delete button.
class RouteDetailScreen extends StatelessWidget {
  final cm.Route route;
  final LocalRouteStore routeStore;
  final Preferences preferences;

  const RouteDetailScreen({
    super.key,
    required this.route,
    required this.routeStore,
    required this.preferences,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = preferences.unit;

    return Scaffold(
      appBar: AppBar(
        title: Text(route.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete route',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
        children: [
          // Map preview
          SizedBox(
            height: 320,
            child: LiveRunMap(
              track: const [],
              plannedRoute: route.waypoints,
              followRunner: false,
            ),
          ),

          // Stats
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
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _surfaceLabel(route.surface!),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(),

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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
      await routeStore.delete(route.id);
      if (context.mounted) Navigator.pop(context);
    }
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
