import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../local_run_store.dart';
import '../preferences.dart';

/// Dashboard with weekly stats and recent runs summary.
class DashboardScreen extends StatefulWidget {
  final LocalRunStore runStore;
  final Preferences preferences;

  const DashboardScreen({
    super.key,
    required this.runStore,
    required this.preferences,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    widget.runStore.addListener(_onChange);
    widget.preferences.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.runStore.removeListener(_onChange);
    widget.preferences.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _editGoal() async {
    final current = widget.preferences.weeklyGoalKm;
    final ctl = TextEditingController(
      text: current > 0 ? current.toStringAsFixed(0) : '',
    );
    final result = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Weekly goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Set a weekly distance goal to track your progress.'),
            const SizedBox(height: 16),
            TextField(
              controller: ctl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Kilometres',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0.0),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctl.text);
              Navigator.pop(ctx, v ?? current);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await widget.preferences.setWeeklyGoalKm(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    final runs = widget.runStore.runs;

    final now = DateTime.now();
    final weekStart =
        DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));

    final weekRuns = runs.where((r) => r.startedAt.isAfter(weekStart)).toList();
    final weekDistance = weekRuns.fold<double>(0, (s, r) => s + r.distanceMetres);
    final weekDuration = weekRuns.fold<Duration>(Duration.zero, (s, r) => s + r.duration);

    final monthStart = DateTime(now.year, now.month, 1);
    final monthRuns = runs.where((r) => r.startedAt.isAfter(monthStart)).toList();
    final monthDistance =
        monthRuns.fold<double>(0, (s, r) => s + r.distanceMetres);

    final goalKm = widget.preferences.weeklyGoalKm;
    final weekKm = weekDistance / 1000;
    final progress = goalKm > 0 ? (weekKm / goalKm).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Weekly goal',
            onPressed: _editGoal,
          ),
        ],
      ),
      body: runs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_run, size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('Welcome!', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Start your first run from the Run tab',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (goalKm > 0) ...[
            Text('Weekly Goal', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${UnitFormat.distanceValue(weekDistance, unit)} / '
                          '${UnitFormat.distance(goalKm * 1000, unit)}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${(progress * 100).round()}%',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          Text('This Week', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryStat(
                    label: 'Distance',
                    value: UnitFormat.distanceValue(weekDistance, unit),
                    unit: UnitFormat.distanceLabel(unit),
                  ),
                  _SummaryStat(
                    label: 'Runs',
                    value: '${weekRuns.length}',
                  ),
                  _SummaryStat(
                    label: 'Time',
                    value: '${weekDuration.inMinutes}',
                    unit: 'min',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          Text('This Month', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryStat(
                    label: 'Distance',
                    value: UnitFormat.distanceValue(monthDistance, unit),
                    unit: UnitFormat.distanceLabel(unit),
                  ),
                  _SummaryStat(
                    label: 'Runs',
                    value: '${monthRuns.length}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          if (runs.isNotEmpty) ...[
            Text('Personal Bests', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (_longestRun(runs) != null)
                      _PbRow(
                        icon: Icons.straighten,
                        label: 'Longest run',
                        value: UnitFormat.distance(_longestRun(runs)!.distanceMetres, unit),
                      ),
                    if (_fastestPaceRun(runs) != null) ...[
                      const SizedBox(height: 12),
                      _PbRow(
                        icon: Icons.speed,
                        label: 'Fastest pace',
                        value: '${UnitFormat.pace(_paceOf(_fastestPaceRun(runs)!), unit)} '
                            '${UnitFormat.paceLabel(unit)}',
                      ),
                    ],
                    if (_best5k(runs) != null) ...[
                      const SizedBox(height: 12),
                      _PbRow(
                        icon: Icons.emoji_events,
                        label: 'Fastest 5k',
                        value: _formatDuration(_best5k(runs)!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          Text('All Time', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryStat(
                    label: 'Distance',
                    value: UnitFormat.distanceValue(
                        runs.fold<double>(0, (s, r) => s + r.distanceMetres), unit),
                    unit: UnitFormat.distanceLabel(unit),
                  ),
                  _SummaryStat(
                    label: 'Runs',
                    value: '${runs.length}',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Run? _longestRun(List<Run> runs) {
    if (runs.isEmpty) return null;
    return runs.reduce((a, b) => a.distanceMetres >= b.distanceMetres ? a : b);
  }

  Run? _fastestPaceRun(List<Run> runs) {
    // Only running-style activities use pace as a PB metric.
    final eligible = runs
        .where((r) =>
            r.distanceMetres >= 1000 &&
            !ActivityType.fromName(r.metadata?['activity_type'] as String?).usesSpeed)
        .toList();
    if (eligible.isEmpty) return null;
    return eligible.reduce((a, b) => _paceOf(a) <= _paceOf(b) ? a : b);
  }

  double _paceOf(Run r) => r.duration.inSeconds / (r.distanceMetres / 1000);

  Duration? _best5k(List<Run> runs) {
    final eligible = runs
        .where((r) =>
            r.distanceMetres >= 5000 &&
            !ActivityType.fromName(r.metadata?['activity_type'] as String?).usesSpeed)
        .toList();
    if (eligible.isEmpty) return null;
    final times = eligible.map((r) {
      final secPerMetre = r.duration.inSeconds / r.distanceMetres;
      return Duration(seconds: (secPerMetre * 5000).round());
    }).toList();
    return times.reduce((a, b) => a < b ? a : b);
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m}:${s.toString().padLeft(2, '0')}';
  }
}

class _PbRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _PbRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const _SummaryStat({required this.label, required this.value, this.unit});

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
