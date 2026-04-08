import 'package:flutter/material.dart';

import '../mock_data.dart';

/// Run history list with weekly summary.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListView(
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
                        value:
                            '${(weeklyDistanceMetres / 1000).toStringAsFixed(1)} km',
                      ),
                      _SummaryItem(
                        label: 'Runs',
                        value: '$weeklyRunCount',
                      ),
                      _SummaryItem(
                        label: 'Time',
                        value: '${weeklyDuration.inMinutes}m',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Run list
          Text('Recent Runs', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...mockRuns.map((run) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.directions_run,
                        color: theme.colorScheme.primary),
                  ),
                  title: Text(run.title),
                  subtitle: Text(
                      '${run.formattedDate}  •  ${run.formattedDistance}  •  ${run.formattedDuration}'),
                  trailing: Text(run.formattedPace,
                      style: theme.textTheme.bodySmall),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${run.title} detail coming soon')),
                    );
                  },
                ),
              )),
        ],
      ),
    );
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
