import 'dart:math' as math;

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../local_run_store.dart';
import '../preferences.dart';
import '../widgets/live_run_map.dart';

/// Detail view for a completed run, showing the route map, splits, and stats.
class RunDetailScreen extends StatelessWidget {
  final Run run;
  final LocalRunStore runStore;
  final Preferences preferences;

  const RunDetailScreen({
    super.key,
    required this.run,
    required this.runStore,
    required this.preferences,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = preferences.unit;

    return Scaffold(
      appBar: AppBar(
        title: Text(_formatDate(run.startedAt)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete run',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: ListView(
        children: [
          // Map
          SizedBox(
            height: 280,
            child: LiveRunMap(track: run.track, followRunner: false),
          ),

          // Primary stats
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatBig(
                  label: 'Distance',
                  value: UnitFormat.distanceValue(run.distanceMetres, unit),
                  unit: UnitFormat.distanceLabel(unit),
                ),
                _StatBig(
                  label: 'Time',
                  value: _formatDuration(run.duration),
                ),
                _StatBig(
                  label: 'Pace',
                  value: UnitFormat.pace(_avgPaceSecPerKm, unit),
                  unit: UnitFormat.paceLabel(unit),
                ),
              ],
            ),
          ),

          const Divider(),

          // Splits
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('Splits', style: theme.textTheme.titleMedium),
          ),
          ..._buildSplits(theme, unit),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  double? get _avgPaceSecPerKm {
    if (run.distanceMetres < 10) return null;
    return run.duration.inSeconds / (run.distanceMetres / 1000);
  }

  List<Widget> _buildSplits(ThemeData theme, DistanceUnit unit) {
    if (run.track.length < 2) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('No GPS data for splits'),
        ),
      ];
    }

    const metresPerMile = 1609.344;
    final tickLength = unit == DistanceUnit.mi ? metresPerMile : 1000.0;
    final unitLabel = UnitFormat.distanceLabel(unit);

    final splits = <_Split>[];
    double cumulative = 0;
    int nextTick = 1;
    DateTime tickStart = run.track.first.timestamp ?? run.startedAt;

    for (int i = 1; i < run.track.length; i++) {
      final a = run.track[i - 1];
      final b = run.track[i];
      cumulative += _haversine(a.lat, a.lng, b.lat, b.lng);

      while (cumulative >= nextTick * tickLength) {
        final tickEnd = b.timestamp ?? run.startedAt;
        final splitTime = tickEnd.difference(tickStart);
        splits.add(_Split(nextTick, splitTime));
        tickStart = tickEnd;
        nextTick++;
      }
    }

    if (splits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Run too short for a full $unitLabel split'),
        ),
      ];
    }

    return splits.map((s) {
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text('${s.tick}'),
        ),
        title: Text('$unitLabel ${s.tick}'),
        trailing: Text(
          _formatDuration(s.duration),
          style: theme.textTheme.titleMedium,
        ),
      );
    }).toList();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete run?'),
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
      await runStore.delete(run.id);
      if (context.mounted) Navigator.pop(context);
    }
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}

class _Split {
  final int tick;
  final Duration duration;
  const _Split(this.tick, this.duration);
}

class _StatBig extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const _StatBig({required this.label, required this.value, this.unit});

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
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(
                unit!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
