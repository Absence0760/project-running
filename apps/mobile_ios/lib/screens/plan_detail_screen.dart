import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../training.dart';
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/error_state.dart';
import '../widgets/plan_calendar.dart';
import '../widgets/workout_edit_sheet.dart';
import 'workout_detail_screen.dart';

class PlanDetailScreen extends StatefulWidget {
  final TrainingService training;
  final String planId;
  const PlanDetailScreen({
    super.key,
    required this.training,
    required this.planId,
  });

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  TrainingPlanRow? _plan;
  List<PlanWeekRow> _weeks = const [];
  Map<String, List<PlanWorkoutRow>> _byWeek = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.training
          .fetchPlan(widget.planId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      final byWeek = <String, List<PlanWorkoutRow>>{};
      for (final w in res.workouts) {
        byWeek.putIfAbsent(w.weekId, () => []).add(w);
      }
      setState(() {
        _plan = res.plan;
        _weeks = res.weeks;
        _byWeek = byWeek;
        _loading = false;
      });
    } on TimeoutException catch (e) {
      debugPrint('PlanDetailScreen._load timed out: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Connection timed out. Check your network and try again.';
        });
      }
    } catch (e, s) {
      debugPrint('PlanDetailScreen._load failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Couldn\'t load this plan. Tap retry to try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(message: _error!, onRetry: _load),
      );
    }
    final p = _plan;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Plan not found.')),
      );
    }
    final theme = Theme.of(context);
    final today = toIsoDate(DateTime.now());
    final start = p.startDate;
    final dayIndex = DateTime.now().difference(start).inDays;
    final currentWeek = dayIndex < 0
        ? 0
        : (dayIndex ~/ 7).clamp(0, _weeks.length - 1);
    final todayWorkout = _byWeek.values
        .expand((x) => x)
        .where((w) => toIsoDate(w.scheduledDate) == today && w.kind != 'rest')
        .cast<PlanWorkoutRow?>()
        .firstOrNull;
    final allActive =
        _byWeek.values.expand((x) => x).where((w) => w.kind != 'rest').toList();
    final done = allActive.where((w) => w.completedRunId != null).length;
    final pct =
        allActive.isEmpty ? 0 : (100 * done / allActive.length).round();

    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _heroCard(theme, p, pct, done, allActive.length),
            if (todayWorkout != null) ...[
              const SizedBox(height: 12),
              _todayCard(theme, p, todayWorkout),
            ],
            const SizedBox(height: 16),
            PlanCalendar(
              startDate: p.startDate,
              endDate: p.endDate,
              workouts: _byWeek.values.expand((x) => x).toList(),
              onSelect: (wo) async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WorkoutDetailScreen(
                      training: widget.training,
                      planId: p.id,
                      workoutId: wo.id,
                    ),
                  ),
                );
                _load();
              },
            ),
            const SizedBox(height: 16),
            for (final w in _weeks)
              _weekCard(theme, p, w, currentWeek),
          ],
        ),
      ),
    );
  }

  Widget _heroCard(ThemeData theme, TrainingPlanRow p, int pct, int done, int total) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    _chip(theme, Icons.flag, fmtKm(p.goalDistanceM, 1)),
                    if (p.goalTimeSeconds != null)
                      _chip(theme, Icons.timer, fmtHms(p.goalTimeSeconds)),
                    if (p.vdot != null)
                      _chip(theme, Icons.trending_up,
                          'VDOT ${p.vdot!.toStringAsFixed(1)}'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${toIsoDate(p.startDate)} → ${toIsoDate(p.endDate)} · '
                  '${p.daysPerWeek} days/wk',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _progressRing(theme, pct, done, total),
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.outline),
        const SizedBox(width: 3),
        Text(text, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _progressRing(ThemeData theme, int pct, int done, int total) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              value: pct / 100,
              strokeWidth: 5,
              color: theme.colorScheme.primary,
              backgroundColor: theme.dividerColor,
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$pct%',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text('$done/$total',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _todayCard(
      ThemeData theme, TrainingPlanRow p, PlanWorkoutRow wo) {
    final kind = workoutKindFromDb(wo.kind);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutDetailScreen(
              training: widget.training,
              planId: p.id,
              workoutId: wo.id,
            ),
          ),
        );
        _load();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TODAY',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 4),
            Text(workoutKindLabel(kind),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Row(
              children: [
                if (wo.targetDistanceM != null) ...[
                  Text(fmtKm(wo.targetDistanceM)),
                  const SizedBox(width: 8),
                ],
                if (wo.targetPaceSecPerKm != null)
                  Text('@ ${fmtPace(wo.targetPaceSecPerKm)}',
                      style: TextStyle(color: theme.colorScheme.outline)),
                if (wo.completedRunId != null) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.check_circle,
                      color: theme.colorScheme.primary, size: 18),
                  const SizedBox(width: 3),
                  Text('Completed',
                      style: TextStyle(color: theme.colorScheme.primary)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekCard(
      ThemeData theme, TrainingPlanRow p, PlanWeekRow w, int currentWeek) {
    final phase = planPhaseFromDb(w.phase);
    final today = toIsoDate(DateTime.now());
    final workouts = _byWeek[w.id] ?? const [];
    final isCurrent = w.weekIndex == currentWeek;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: isCurrent
              ? theme.colorScheme.primary
              : theme.dividerColor,
          width: isCurrent ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Week ${w.weekIndex + 1}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text(planPhaseLabel(phase).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  )),
              const Spacer(),
              Text(fmtKm(w.targetVolumeM, 0),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
            ],
          ),
          if (w.notes != null && w.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(w.notes!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
            ),
          const SizedBox(height: 8),
          for (final wo in workouts)
            _workoutRow(theme, p, wo, today),
        ],
      ),
    );
  }

  Widget _workoutRow(ThemeData theme, TrainingPlanRow p, PlanWorkoutRow wo,
      String today) {
    final kind = workoutKindFromDb(wo.kind);
    final isRest = kind == WorkoutKind.rest;
    final isToday = toIsoDate(wo.scheduledDate) == today;
    final dow = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
        [wo.scheduledDate.weekday % 7];
    return InkWell(
      onTap: isRest
          ? null
          : () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WorkoutDetailScreen(
                    training: widget.training,
                    planId: p.id,
                    workoutId: wo.id,
                  ),
                ),
              );
              _load();
            },
      onLongPress: () => _editWorkout(wo),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: isToday
              ? theme.colorScheme.primaryContainer.withOpacity(0.5)
              : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            SizedBox(width: 34, child: Text(dow,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ))),
            Expanded(
              child: Text(
                workoutKindLabel(kind),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isRest ? theme.colorScheme.outline : null,
                  fontWeight: isRest ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
            if (wo.targetDistanceM != null && !isRest) ...[
              Text(fmtKm(wo.targetDistanceM, 1),
                  style: theme.textTheme.bodySmall),
              const SizedBox(width: 6),
            ],
            if (wo.completedRunId != null)
              Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 16),
            // Inline edit affordance — discoverable button alongside the
            // long-press gesture. Hidden on rest days; nothing to edit.
            if (!isRest)
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  splashRadius: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Edit workout',
                  icon: Icon(Icons.edit_outlined,
                      color: theme.colorScheme.outline),
                  onPressed: () => _editWorkout(wo),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editWorkout(PlanWorkoutRow wo) async {
    final ok = await showWorkoutEditSheet(
      context,
      workout: wo,
      training: widget.training,
    );
    if (ok) await _load();
  }
}
