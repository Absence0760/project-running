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
      body: ListView(
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
