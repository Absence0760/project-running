import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import '../local_run_store.dart';
import '../preferences.dart';
import 'run_detail_screen.dart';

/// Run history showing local runs with sync status.
class HistoryScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  final Preferences preferences;
  const HistoryScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.preferences,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    widget.runStore.addListener(_onStoreChanged);
    widget.preferences.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.runStore.removeListener(_onStoreChanged);
    widget.preferences.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _syncAll() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in from Settings to sync runs')),
      );
      return;
    }

    final unsynced = widget.runStore.unsyncedRuns;
    if (unsynced.isEmpty) return;

    setState(() => _syncing = true);
    int synced = 0;
    String? lastError;

    for (final run in unsynced) {
      try {
        await api.saveRun(run);
        await widget.runStore.markSynced(run.id);
        synced++;
      } catch (e) {
        lastError = e.toString();
      }
    }

    setState(() => _syncing = false);

    if (!mounted) return;
    if (lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Synced $synced/${unsynced.length}. Error: $lastError')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('All $synced runs synced')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runs = widget.runStore.runs;
    final unsyncedCount = widget.runStore.unsyncedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (unsyncedCount > 0)
            Badge(
              label: Text('$unsyncedCount'),
              child: IconButton(
                icon: const Icon(Icons.cloud_upload),
                tooltip: 'Sync $unsyncedCount runs',
                onPressed: _syncAll,
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.cloud_done),
              tooltip: 'Nothing to sync',
              onPressed: null,
            ),
        ],
      ),
      body: runs.isEmpty
          ? Center(
              child: Text('No runs yet',
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
            )
          : _buildRunList(theme, runs),
    );
  }

  Widget _buildRunList(ThemeData theme, List<Run> runs) {
    final unit = widget.preferences.unit;
    final unsyncedIds = widget.runStore.unsyncedRuns.map((r) => r.id).toSet();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('All Runs', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...runs.map((run) {
          final dist = UnitFormat.distance(run.distanceMetres, unit);
          final dur = _formatDuration(run.duration);
          final paceSecPerKm = run.distanceMetres < 10
              ? null
              : run.duration.inSeconds / (run.distanceMetres / 1000);
          final pace = '${UnitFormat.pace(paceSecPerKm, unit)} ${UnitFormat.paceLabel(unit)}';
          final date = _formatDate(run.startedAt);
          final isUnsynced = unsyncedIds.contains(run.id);

          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.directions_run, color: theme.colorScheme.primary),
              ),
              title: Text(dist),
              subtitle: Text('$date  •  $dur'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(pace, style: theme.textTheme.bodySmall),
                  if (isUnsynced) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.cloud_off, size: 16, color: theme.colorScheme.outline),
                  ],
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RunDetailScreen(
                      run: run,
                      runStore: widget.runStore,
                      preferences: widget.preferences,
                    ),
                  ),
                );
              },
            ),
          );
        }),
      ],
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}

