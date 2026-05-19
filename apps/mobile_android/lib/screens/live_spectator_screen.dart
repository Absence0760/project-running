import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../preferences.dart';
import '../widgets/error_state.dart';
import '../widgets/live_run_map.dart';

/// Live spectator screen — mirrors the web `/live/[run_id]` page.
/// Hydrates the existing `live_run_pings` for a run, then subscribes
/// to new INSERTs via Supabase Realtime. RLS gates visibility (a
/// public run's pings are world-readable; a private run's pings are
/// owner-only).
///
/// Privacy-zone trust contract: this client renders pings verbatim. It
/// does NOT have the broadcaster's privacy zones (fetching them client-
/// side would defeat the point — anyone watching a public live run
/// could read off the broadcaster's home / work coordinates). The
/// single line of defence is the `live_run_pings_drop_in_zone`
/// BEFORE-INSERT trigger from migration
/// `20260618_001_clip_live_run_pings_to_privacy_zones.sql`, which
/// silently drops any ping whose (lat, lng) falls inside a zone before
/// the row reaches Realtime. If that trigger is dropped, weakened, or
/// renamed, this screen will start surfacing zone coordinates to every
/// spectator. The pgtap regression in
/// `apps/backend/supabase/tests/rls_live_run_pings_trigger_test.sql`
/// pins the trigger so a future migration can't silently undo it.
class LiveSpectatorScreen extends StatefulWidget {
  final ApiClient api;
  final String runId;

  const LiveSpectatorScreen({
    super.key,
    required this.api,
    required this.runId,
  });

  @override
  State<LiveSpectatorScreen> createState() => _LiveSpectatorScreenState();
}

class _LiveSpectatorScreenState extends State<LiveSpectatorScreen> {
  bool _loading = true;
  Object? _loadError;
  String _status = 'connecting';
  final List<Waypoint> _trace = [];
  double _distanceM = 0;
  int _elapsedS = 0;

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    super.dispose();
  }

  Future<void> _hydrate() async {
    try {
      final rows = await widget.api.fetchLiveRunPings(widget.runId);
      if (!mounted) return;
      for (final row in rows) {
        _ingest(row);
      }
      setState(() {
        _loading = false;
        _status = _trace.isEmpty ? 'idle' : 'live';
      });
      _subscribe();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _subscribe() {
    _channel = Supabase.instance.client
        .channel('live-run:${widget.runId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_run_pings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'run_id',
            value: widget.runId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (!mounted) return;
            setState(() {
              _ingest(row);
              _status = 'live';
            });
          },
        )
        .subscribe();
  }

  void _ingest(Map<String, dynamic> row) {
    final lat = (row['lat'] as num?)?.toDouble();
    final lng = (row['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final ele = (row['ele'] as num?)?.toDouble();
    final at = row['at'] as String?;
    _trace.add(Waypoint(
      lat: lat,
      lng: lng,
      elevationMetres: ele,
      // tryParse never throws — a manually-edited row or future format
      // change would otherwise crash the realtime callback (no outer
      // catch) and tear down live tracking for the spectator.
      timestamp: at == null ? null : DateTime.tryParse(at),
    ));
    final dist = (row['distance_m'] as num?)?.toDouble();
    if (dist != null) _distanceM = dist;
    final elapsed = (row['elapsed_s'] as num?)?.toInt();
    if (elapsed != null) _elapsedS = elapsed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live tracking'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: _StatusBadge(status: _status)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorState(message: 'Could not connect.', onRetry: _hydrate)
              : Column(
                  children: [
                    Expanded(
                      child: _trace.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'Waiting for the runner to send the first ping…',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : LiveRunMap(
                              track: _trace,
                              plannedRoute: const [],
                              followRunner: true,
                              currentPosition: _trace.last,
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(20),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _Metric(
                            label: 'Distance',
                            value: formatDistanceForPref(_distanceM),
                          ),
                          _Metric(
                            label: 'Time',
                            value: formatLiveDuration(Duration(seconds: _elapsedS)),
                          ),
                          _Metric(
                            label: 'Pace',
                            value: _distanceM > 0 && _elapsedS > 0
                                ? formatLivePace(_elapsedS / (_distanceM / 1000))
                                : '—',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

}

/// Live-spectator duration formatter — H:MM:SS past an hour, M:SS under.
/// Hoisted out of `_LiveSpectatorScreenState` so the widget test can
/// pin the boundary cases (the per-second realtime ingest path renders
/// this every tick; a regression to e.g. always-H:MM:SS would surface
/// `0:01:23` for a 1-minute live run).
@visibleForTesting
String formatLiveDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Live-spectator pace formatter — minutes:seconds per km. Same
/// rationale as `formatLiveDuration`: this lights up on every ping
/// payload, so the rounding shape ((seconds-fraction) → nearest int)
/// is worth pinning.
@visibleForTesting
String formatLivePace(double secPerKm) {
  final m = secPerKm ~/ 60;
  final s = (secPerKm % 60).round();
  return '$m:${s.toString().padLeft(2, '0')} /km';
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      'live' => ('Live', const Color(0xFF10B981)),
      'idle' => ('Idle', theme.colorScheme.outline),
      _ => ('Connecting', theme.colorScheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}
