import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

/// Run history list fetched from Supabase.
class HistoryScreen extends StatefulWidget {
  final ApiClient apiClient;
  const HistoryScreen({super.key, required this.apiClient});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Run>? _runs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRuns();
  }

  Future<void> _loadRuns() async {
    try {
      final runs = await widget.apiClient.getRuns();
      setState(() {
        _runs = runs;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRuns,
              child: _runs == null || _runs!.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text('No runs yet',
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(color: theme.colorScheme.outline)),
                      ),
                    ])
                  : _buildRunList(theme),
            ),
    );
  }

  Widget _buildRunList(ThemeData theme) {
    // Weekly summary from the runs
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday % 7));
    final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final thisWeekRuns = _runs!.where((r) => r.startedAt.isAfter(weekStartDate)).toList();
    final weekDistance = thisWeekRuns.fold<double>(0, (sum, r) => sum + r.distanceMetres);
    final weekDuration = thisWeekRuns.fold<Duration>(Duration.zero, (sum, r) => sum + r.duration);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Weekly summary card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This Week', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryItem(
                      label: 'Distance',
                      value: '${(weekDistance / 1000).toStringAsFixed(1)} km',
                    ),
                    _SummaryItem(label: 'Runs', value: '${thisWeekRuns.length}'),
                    _SummaryItem(
                      label: 'Time',
                      value: '${weekDuration.inMinutes}m',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        Text('All Runs', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._runs!.map((run) {
          final dist = (run.distanceMetres / 1000).toStringAsFixed(2);
          final dur = _formatDuration(run.duration);
          final pace = _formatPace(run.duration.inSeconds, run.distanceMetres);
          final date = _formatDate(run.startedAt);
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.directions_run, color: theme.colorScheme.primary),
              ),
              title: Text('$dist km'),
              subtitle: Text('$date  •  $dur  •  ${run.source.name}'),
              trailing: Text(pace, style: theme.textTheme.bodySmall),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${run.track.length} GPS points recorded')),
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

  static String _formatPace(int seconds, double metres) {
    if (metres < 10) return '--:--';
    final paceSeconds = seconds / (metres / 1000);
    final m = paceSeconds ~/ 60;
    final s = (paceSeconds % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
