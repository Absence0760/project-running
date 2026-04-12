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
  /// Memoised fastest-5k window per run id. Rescanning a 200-run history
  /// with several thousand waypoints each on every rebuild (and the
  /// dashboard rebuilds every time a listener fires) is the hottest loop
  /// in the app — this cache flattens it to O(1) on subsequent builds.
  /// Invalidated wholesale when the run store changes.
  final Map<String, Duration?> _best5kCache = {};

  @override
  void initState() {
    super.initState();
    widget.runStore.addListener(_onRunStoreChanged);
    widget.preferences.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.runStore.removeListener(_onRunStoreChanged);
    widget.preferences.removeListener(_onChange);
    super.dispose();
  }

  void _onRunStoreChanged() {
    _best5kCache.clear();
    if (mounted) setState(() {});
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
    final weekStart = weekStartLocal(now);
    final monthStart = DateTime(now.year, now.month, 1);

    // One pass over the runs list collects everything every card needs —
    // week totals, month totals, all-time totals, and the PB candidates.
    // Replaces four separate `.where().fold()` chains. Matters at 10k+ runs.
    var weekRunCount = 0;
    var weekDistance = 0.0;
    var weekDurationSec = 0;
    var monthRunCount = 0;
    var monthDistance = 0.0;
    var allDistance = 0.0;
    Run? longest;
    Run? fastestPace;
    Duration? best5k;
    for (final r in runs) {
      allDistance += r.distanceMetres;
      if (!r.startedAt.isBefore(weekStart)) {
        weekRunCount++;
        weekDistance += r.distanceMetres;
        weekDurationSec += r.duration.inSeconds;
      }
      if (!r.startedAt.isBefore(monthStart)) {
        monthRunCount++;
        monthDistance += r.distanceMetres;
      }
      if (!_isRunActivity(r)) continue;
      if (longest == null || r.distanceMetres > longest.distanceMetres) {
        longest = r;
      }
      if (r.distanceMetres >= 1000) {
        if (fastestPace == null || _paceOf(r) < _paceOf(fastestPace)) {
          fastestPace = r;
        }
      }
      if (r.distanceMetres >= 5000) {
        final cached =
            _best5kCache.putIfAbsent(r.id, () => fastestWindowOf(r.track, 5000));
        if (cached != null && (best5k == null || cached < best5k)) {
          best5k = cached;
        }
      }
    }
    final hasAnyPb = longest != null || fastestPace != null || best5k != null;
    final weekDurationMin = Duration(seconds: weekDurationSec).inMinutes;

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
                          value: '$weekRunCount',
                        ),
                        _SummaryStat(
                          label: 'Time',
                          value: '$weekDurationMin',
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
                          value: '$monthRunCount',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (hasAnyPb) ...[
                  Text('Personal Bests', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          if (longest != null)
                            _PbRow(
                              icon: Icons.straighten,
                              label: 'Longest run',
                              value: UnitFormat.distance(
                                  longest.distanceMetres, unit),
                            ),
                          if (fastestPace != null) ...[
                            const SizedBox(height: 12),
                            _PbRow(
                              icon: Icons.speed,
                              label: 'Fastest pace',
                              value:
                                  '${UnitFormat.pace(_paceOf(fastestPace), unit)} '
                                  '${UnitFormat.paceLabel(unit)}',
                            ),
                          ],
                          if (best5k != null) ...[
                            const SizedBox(height: 12),
                            _PbRow(
                              icon: Icons.emoji_events,
                              label: 'Fastest 5k',
                              value: _formatDuration(best5k),
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
                          value: UnitFormat.distanceValue(allDistance, unit),
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

  double _paceOf(Run r) => r.duration.inSeconds / (r.distanceMetres / 1000);

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
    final periodLabel =
        goal.period == GoalPeriod.week ? 'WEEKLY' : 'MONTHLY';
    final customTitle = goal.title;

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customTitle ?? '$periodLabel GOAL',
                          style: (customTitle != null
                                  ? theme.textTheme.titleMedium
                                  : theme.textTheme.labelMedium)
                              ?.copyWith(
                            color: customTitle != null
                                ? null
                                : theme.colorScheme.outline,
                            letterSpacing: customTitle != null ? 0 : 1.1,
                            fontWeight: customTitle != null
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (customTitle != null)
                          Text(
                            periodLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                              letterSpacing: 1.1,
                            ),
                          ),
                      ],
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
