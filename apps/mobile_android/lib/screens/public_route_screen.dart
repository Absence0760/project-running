import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';

import '../preferences.dart';
import '../widgets/error_state.dart';
import '../widgets/live_run_map.dart';
import '../widgets/segments_panel.dart';

/// Read-only public view of a single route. Mirrors the web
/// `/share/route/[id]` route — anyone with the link can view a public
/// route. Private routes (or club-only routes the viewer can't see)
/// fall through to a "not available" empty state via RLS.
class PublicRouteScreen extends StatefulWidget {
  final ApiClient api;
  final String routeId;

  const PublicRouteScreen({
    super.key,
    required this.api,
    required this.routeId,
  });

  @override
  State<PublicRouteScreen> createState() => _PublicRouteScreenState();
}

class _PublicRouteScreenState extends State<PublicRouteScreen> {
  bool _loading = true;
  Object? _loadError;
  cm.Route? _route;
  List<cm.Waypoint> _waypoints = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final fetched = await widget.api.fetchRouteById(widget.routeId);
      final route = fetched.route;
      if (route == null) {
        if (!mounted) return;
        setState(() {
          _route = null;
          _waypoints = const [];
          _loading = false;
        });
        return;
      }
      // Privacy-zone clipping for non-owner viewers (decisions §33).
      // Owners see the full route — anon (`api.userId == null`) is
      // treated as non-owner so unauthenticated `/share/route/[id]`
      // hits also honour zones. The RPC fails closed (returns []) on
      // outage, so a transient blip renders an empty map for non-
      // owners instead of leaking the start/end home location.
      final viewerId = widget.api.userId;
      final ownerId = fetched.ownerId;
      final isOwner =
          viewerId != null && ownerId != null && viewerId == ownerId;
      final waypoints =
          (isOwner || ownerId == null || route.waypoints.isEmpty)
              ? route.waypoints
              : await _clipForViewer(route.waypoints, ownerId);
      if (!mounted) return;
      setState(() {
        _route = route;
        _waypoints = waypoints;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<List<cm.Waypoint>> _clipForViewer(
    List<cm.Waypoint> track,
    String ownerUserId,
  ) async {
    final clipped = await widget.api.clipTrackForUser(
      targetUserId: ownerUserId,
      points: track
          .map((w) => {
                'lat': w.lat,
                'lng': w.lng,
                if (w.elevationMetres != null) 'ele': w.elevationMetres,
              })
          .toList(),
    );
    return clipped
        .map((p) => cm.Waypoint(
              lat: (p['lat'] as num).toDouble(),
              lng: (p['lng'] as num).toDouble(),
              elevationMetres: (p['ele'] as num?)?.toDouble(),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_route?.name ?? 'Route')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorState(message: 'Could not load this route.', onRetry: _load)
              : _route == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'This route is private or no longer available.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : _buildBody(theme, _route!),
    );
  }

  Widget _buildBody(ThemeData theme, cm.Route route) {
    return ListView(
      children: [
        SizedBox(
          height: 320,
          child: LiveRunMap(
            track: const [],
            plannedRoute: _waypoints,
            followRunner: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Stat(
                label: 'Distance',
                value: UnitFormat.distanceValue(
                    route.distanceMetres, DistanceUnit.km),
                unit: 'km',
              ),
              _Stat(
                label: 'Elevation',
                value: '${route.elevationGainMetres.round()}',
                unit: 'm',
              ),
              _Stat(
                label: 'Waypoints',
                value: '${_waypoints.length}',
              ),
            ],
          ),
        ),
        if (widget.api.userId != null)
          SegmentsPanel(
            api: widget.api,
            routeId: route.id,
            routeDistanceM: route.distanceMetres,
            canCreate: false,
          ),
        const SizedBox(height: 32),
      ],
    );
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }
}
