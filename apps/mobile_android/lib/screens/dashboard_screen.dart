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

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
