import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../local_run_store.dart';
import '../preferences.dart';
import '../recap.dart';

/// Year-in-running recap. Mobile mirror of web `/recap/[year]`.
/// Reads runs from the local store + the LocalRunStore's already-
/// fetched cache (no extra Supabase round-trip) and builds the
/// hero numbers via `buildYearInRunningRecap`. Includes a share
/// CTA that hands a one-line summary to the OS share sheet.
class RecapScreen extends StatefulWidget {
  final LocalRunStore runStore;
  final Preferences preferences;
  final int? year;

  const RecapScreen({
    super.key,
    required this.runStore,
    required this.preferences,
    this.year,
  });

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.year ?? DateTime.now().year;
  }

  void _shiftYear(int delta) {
    setState(() => _year = _year + delta);
  }

  Future<void> _share(YearInRunningRecap recap) async {
    final total = UnitFormat.distance(recap.totalDistanceM, widget.preferences.unit);
    final lines = <String>[
      'My ${recap.year} in running:',
      '$total across ${recap.runCount} runs',
      if (recap.longestRunM > 0)
        'Longest run: ${UnitFormat.distance(recap.longestRunM, widget.preferences.unit)}',
      if (recap.bestStreakDays > 0)
        'Best streak: ${recap.bestStreakDays} days',
    ];
    await SharePlus.instance.share(
      ShareParams(text: lines.join('\n'), subject: '${recap.year} recap'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    final recap = buildYearInRunningRecap(widget.runStore.runs, _year);
    final earliestPossible = _year < 2000 || _year > DateTime.now().year + 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('Year in running'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share recap',
            onPressed: recap.runCount == 0 ? null : () => _share(recap),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Year switcher
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => _shiftYear(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$_year', style: theme.textTheme.headlineMedium),
                IconButton(
                  onPressed: _year >= DateTime.now().year
                      ? null
                      : () => _shiftYear(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (earliestPossible) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No runs to recap for $_year.',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ] else if (recap.runCount == 0) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No runs in $_year yet. Log one to see your recap.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ] else ...[
              // Hero distance
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        UnitFormat.distance(recap.totalDistanceM, unit),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'across ${recap.runCount} ${recap.runCount == 1 ? 'run' : 'runs'}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Longest run',
                      value: UnitFormat.distance(recap.longestRunM, unit),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Best streak',
                      value:
                          '${recap.bestStreakDays} ${recap.bestStreakDays == 1 ? 'day' : 'days'}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Top week',
                      value: recap.topWeek == null
                          ? '—'
                          : UnitFormat.distance(
                              recap.topWeek!.distanceM, unit),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Unique routes',
                      value: '${recap.uniqueRouteCount}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Earliest start',
                      value: recap.earliestStartLocal ?? '—',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Latest start',
                      value: recap.latestStartLocal ?? '—',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
