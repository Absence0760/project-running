import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../goals.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../run_stats.dart';
import '../widgets/goal_editor_sheet.dart';

/// Dashboard with goals, weekly/monthly stats, and personal bests.
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

  Future<void> _newGoal() => showGoalEditorSheet(
        context,
        preferences: widget.preferences,
      );

  Future<void> _editGoal(RunGoal goal) => showGoalEditorSheet(
        context,
        preferences: widget.preferences,
        existing: goal,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    final runs = widget.runStore.runs;
    final goals = widget.preferences.goals;

    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    final weekRuns = runs.where((r) => r.startedAt.isAfter(weekStart)).toList();
    final weekDistance =
        weekRuns.fold<double>(0, (s, r) => s + r.distanceMetres);
    final weekDuration =
        weekRuns.fold<Duration>(Duration.zero, (s, r) => s + r.duration);

    final monthStart = DateTime(now.year, now.month, 1);
    final monthRuns =
        runs.where((r) => r.startedAt.isAfter(monthStart)).toList();
    final monthDistance =
        monthRuns.fold<double>(0, (s, r) => s + r.distanceMetres);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: runs.isEmpty && goals.isEmpty
          ? _WelcomeEmpty(theme: theme, onAddGoal: _newGoal)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _goalsSection(theme, unit, runs, goals, now),
                const SizedBox(height: 24),
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
                              value: UnitFormat.distance(
                                  _longestRun(runs)!.distanceMetres, unit),
                            ),
                          if (_fastestPaceRun(runs) != null) ...[
                            const SizedBox(height: 12),
                            _PbRow(
                              icon: Icons.speed,
                              label: 'Fastest pace',
                              value:
                                  '${UnitFormat.pace(_paceOf(_fastestPaceRun(runs)!), unit)} '
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
                              runs.fold<double>(
                                  0, (s, r) => s + r.distanceMetres),
                              unit),
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

  Widget _goalsSection(
    ThemeData theme,
    DistanceUnit unit,
    List<Run> runs,
    List<RunGoal> goals,
    DateTime now,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Goals', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (goals.isNotEmpty)
              TextButton.icon(
                onPressed: _newGoal,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (goals.isEmpty)
          _EmptyGoalsCta(onAdd: _newGoal)
        else
          for (final goal in goals)
            _GoalCard(
              goal: goal,
              progress: evaluateGoal(goal, runs, now),
              unit: unit,
              onTap: () => _editGoal(goal),
            ),
      ],
    );
  }

  /// Personal-best cards are running-only. Cycles, walks, and hikes have
  /// their own pace/distance scales and would otherwise starve the run PBs
  /// (a 40 km ride as "longest run", a brisk walk as "fastest pace"). Legacy
  /// runs with no `activity_type` in metadata default to run.
  static bool _isRunActivity(Run r) {
    final raw = r.metadata?['activity_type'] as String?;
    return raw == null || raw == 'run';
  }

  Run? _longestRun(List<Run> runs) {
    final eligible = runs.where(_isRunActivity).toList();
    if (eligible.isEmpty) return null;
    return eligible
        .reduce((a, b) => a.distanceMetres >= b.distanceMetres ? a : b);
  }

  Run? _fastestPaceRun(List<Run> runs) {
    final eligible = runs
        .where((r) => _isRunActivity(r) && r.distanceMetres >= 1000)
        .toList();
    if (eligible.isEmpty) return null;
    return eligible.reduce((a, b) => _paceOf(a) <= _paceOf(b) ? a : b);
  }

  double _paceOf(Run r) => r.duration.inSeconds / (r.distanceMetres / 1000);

  /// Fastest continuous 5 km across every running activity with a GPS
  /// track — a rolling-window scan per run, not a scaled average. Runs
  /// without a track (manual entries, summary-only imports) are ignored
  /// here because there's no way to know the runner's pace over any
  /// specific 5 km segment.
  Duration? _best5k(List<Run> runs) {
    Duration? best;
    for (final r in runs) {
      if (!_isRunActivity(r) || r.distanceMetres < 5000) continue;
      final window = fastestWindowOf(r.track, 5000);
      if (window == null) continue;
      if (best == null || window < best) best = window;
    }
    return best;
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _WelcomeEmpty extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onAddGoal;
  const _WelcomeEmpty({required this.theme, required this.onAddGoal});

  @override
  Widget build(BuildContext context) {
    return Center(
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
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onAddGoal,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Set a goal'),
          ),
        ],
      ),
    );
  }
}

class _EmptyGoalsCta extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyGoalsCta({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primaryContainer,
                ),
                child: Icon(Icons.flag_outlined,
                    color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Set your first goal',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Track distance, time, pace, or number of runs each week or month.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final RunGoal goal;
  final GoalProgress progress;
  final DistanceUnit unit;
  final VoidCallback onTap;
  const _GoalCard({
    required this.goal,
    required this.progress,
    required this.unit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completeColor = Colors.green.shade600;
    final accent =
        progress.complete ? completeColor : theme.colorScheme.primary;
    final title =
        goal.period == GoalPeriod.week ? 'WEEKLY GOAL' : 'MONTHLY GOAL';

    // Look up per-kind progress so the card can render every kind in order,
    // with unset targets shown as muted "-" rows. Keeps the layout stable
    // regardless of which targets the user has configured.
    final byKind = <GoalTargetKind, TargetProgress>{
      for (final t in progress.targets) t.kind: t,
    };

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.outline,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  Text(
                    '${(progress.overallPercent * 100).round()}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.edit_outlined,
                      size: 14, color: theme.colorScheme.outline),
                ],
              ),
              const SizedBox(height: 14),
              for (int i = 0; i < GoalTargetKind.values.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _TargetRow(
                  kind: GoalTargetKind.values[i],
                  target: byKind[GoalTargetKind.values[i]],
                  unit: unit,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  final GoalTargetKind kind;
  final TargetProgress? target;
  final DistanceUnit unit;
  const _TargetRow({
    required this.kind,
    required this.target,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = target;

    if (t == null) {
      // Unset target — single muted line, no bar, no feedback.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                goalKindLabel(kind),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline.withValues(alpha: 0.6),
                ),
              ),
            ),
            Text(
              '—',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline.withValues(alpha: 0.6),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final accent =
        t.complete ? Colors.green.shade600 : theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                goalKindLabel(kind),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            Text(
              _valueText(t, unit),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: t.percent,
            minHeight: 6,
            color: accent,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Icon(
              t.complete ? Icons.check_circle : Icons.trending_up,
              size: 12,
              color: accent,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                t.feedback,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _valueText(TargetProgress t, DistanceUnit unit) {
    switch (t.kind) {
      case GoalTargetKind.distance:
        final c = UnitFormat.distanceValue(t.current, unit);
        final tgt = UnitFormat.distanceValue(t.target, unit);
        return '$c / $tgt ${UnitFormat.distanceLabel(unit)}';
      case GoalTargetKind.time:
        return '${_coarseDuration(t.current)} / ${_coarseDuration(t.target)}';
      case GoalTargetKind.avgPace:
        final c =
            t.current > 0 ? UnitFormat.pace(t.current, unit) : '--:--';
        final tgt = UnitFormat.pace(t.target, unit);
        return '$c / $tgt ${UnitFormat.paceLabel(unit)}';
      case GoalTargetKind.runCount:
        return '${t.current.toInt()} / ${t.target.toInt()}';
    }
  }

  static String _coarseDuration(double seconds) {
    final totalMin = (seconds / 60).round();
    if (totalMin >= 60) {
      final h = totalMin ~/ 60;
      final m = totalMin % 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    return '${totalMin}m';
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
