import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/date_format.dart';
import '../l10n/locale_support.dart';
import '../relink_candidates.dart';
import '../training.dart';
import '../training_labels.dart';
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';

class WorkoutDetailScreen extends StatefulWidget {
  final TrainingService training;
  final String planId;
  final String workoutId;
  const WorkoutDetailScreen({
    super.key,
    required this.training,
    required this.planId,
    required this.workoutId,
  });

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  PlanWorkoutRow? _workout;
  bool _loading = true;
  _WorkoutLoadError? _error;

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
      final w = await widget.training
          .fetchWorkout(widget.workoutId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _workout = w;
        _loading = false;
      });
    } on TimeoutException catch (e) {
      debugPrint('WorkoutDetailScreen._load timed out: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _WorkoutLoadError.timeout;
        });
      }
    } catch (e, s) {
      debugPrint('WorkoutDetailScreen._load failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _WorkoutLoadError.generic;
        });
      }
    }
  }

  Future<void> _openRelinkPicker(PlanWorkoutRow workout) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => _RelinkPickerDialog(
        training: widget.training,
        workout: workout,
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await widget.training.markCompleted(widget.workoutId, picked);
      await _load();
    } catch (e, s) {
      debugPrint('WorkoutDetailScreen._openRelinkPicker re-link failed: $e\n$s');
      if (mounted) showTopBanner(context, l10n.workoutRelinkError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(
            message: _error == _WorkoutLoadError.timeout
                ? l10n.workoutTimeoutError
                : l10n.workoutLoadError,
            onRetry: _load),
      );
    }
    final w = _workout;
    if (w == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.workoutNotFound)),
      );
    }
    final theme = Theme.of(context);
    final kind = workoutKindFromDb(w.kind);
    final structure = w.structure == null
        ? null
        : WorkoutStructure.fromJson(w.structure!);

    return Scaffold(
      appBar: AppBar(title: Text(workoutKindLabel(l10n, kind))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(toIsoDate(w.scheduledDate).toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 4),
          Text(workoutKindLabel(l10n, kind),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              if (w.targetDistanceM != null)
                _metric(theme, l10n.workoutMetricDistance,
                    fmtKm(w.targetDistanceM, 2)),
              if (w.targetDurationSeconds != null)
                _metric(theme, l10n.workoutMetricDuration,
                    fmtHms(w.targetDurationSeconds)),
              if (w.targetPaceSecPerKm != null)
                _metric(
                  theme,
                  l10n.workoutMetricTargetPace,
                  w.targetPaceEndSecPerKm != null &&
                          w.targetPaceEndSecPerKm != w.targetPaceSecPerKm
                      ? '${fmtPace(w.targetPaceSecPerKm)} → ${fmtPace(w.targetPaceEndSecPerKm)}'
                      : fmtPace(w.targetPaceSecPerKm),
                  tolerance: w.targetPaceToleranceSec,
                  zone: w.paceZone,
                ),
            ],
          ),
          if (w.completedRunId != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle,
                      size: 18, color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text(l10n.workoutCompleted,
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => _openRelinkPicker(w),
                    child: Text(l10n.workoutRelink),
                  ),
                  TextButton(
                    onPressed: () async {
                      await widget.training
                          .markCompleted(widget.workoutId, null);
                      _load();
                    },
                    child: Text(l10n.workoutUnlink),
                  ),
                ],
              ),
            ),
          ] else if (w.kind != 'rest') ...[
            const SizedBox(height: 16),
            // Start workout — pops with the workout row so callers can
            // load it into the WorkoutRunner. The plan_detail entry
            // also pops back to HomeScreen and signals
            // `pendingStartWorkout` so RunScreen consumes it across
            // a tab switch.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(w),
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.workoutStart),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
          if (w.notes != null && w.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(theme, l10n.workoutSectionNotes),
            const SizedBox(height: 4),
            Text(w.notes!, style: theme.textTheme.bodyMedium),
          ],
          if (structure != null) ...[
            const SizedBox(height: 16),
            _section(theme, l10n.workoutSectionStructure),
            const SizedBox(height: 4),
            _structureList(theme, l10n, structure),
          ],
          const SizedBox(height: 20),
          _section(theme, l10n.workoutSectionHowTo),
          const SizedBox(height: 4),
          Text(_advice(l10n, kind), style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String label) {
    return Text(label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          letterSpacing: 0.7,
          fontWeight: FontWeight.w700,
        ));
  }

  Widget _metric(ThemeData theme, String label, String value,
      {int? tolerance, String? zone}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              letterSpacing: 0.6,
            )),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (tolerance != null) ...[
              const SizedBox(width: 4),
              Text('±${tolerance}s',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
            ],
            if (zone != null && zone.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  zone,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _structureList(
      ThemeData theme, AppLocalizations l10n, WorkoutStructure s) {
    final items = <Widget>[];
    void add(String title, String body) {
      items.add(Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  )),
            ),
            Expanded(child: Text(body, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ));
    }

    if (s.warmup != null) {
      add(l10n.workoutStructWarmup,
          l10n.workoutStructWarmupValue(fmtKm(s.warmup!['distance_m'] as num, 1)));
    }
    if (s.repeats != null) {
      final r = s.repeats!;
      add(l10n.workoutStructRepeats,
          '${r['count']}× ${fmtKm(r['distance_m'] as num, 2)} @ '
          '${fmtPace((r['pace_sec_per_km'] as num).toInt())} with '
          '${fmtKm(r['recovery_distance_m'] as num, 2)} ${r['recovery_pace']}');
    }
    if (s.steady != null) {
      final st = s.steady!;
      add(l10n.workoutStructSteady,
          '${fmtKm(st['distance_m'] as num, 1)} @ '
          '${fmtPace((st['pace_sec_per_km'] as num).toInt())}');
    }
    if (s.cooldown != null) {
      add(l10n.workoutStructCooldown,
          l10n.workoutStructCooldownValue(
              fmtKm(s.cooldown!['distance_m'] as num, 1)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items,
    );
  }

  String _advice(AppLocalizations l10n, WorkoutKind k) => switch (k) {
        WorkoutKind.easy || WorkoutKind.recovery => l10n.workoutAdviceEasy,
        WorkoutKind.long => l10n.workoutAdviceLong,
        WorkoutKind.tempo => l10n.workoutAdviceTempo,
        WorkoutKind.interval => l10n.workoutAdviceInterval,
        WorkoutKind.marathonPace => l10n.workoutAdviceMarathonPace,
        WorkoutKind.walkRun => l10n.workoutAdviceWalkRun,
        WorkoutKind.race => l10n.workoutAdviceRace,
        WorkoutKind.rest => l10n.workoutAdviceRest,
      };
}

enum _WorkoutLoadError { timeout, generic }

class _RelinkPickerDialog extends StatefulWidget {
  final TrainingService training;
  final PlanWorkoutRow workout;
  const _RelinkPickerDialog({required this.training, required this.workout});

  @override
  State<_RelinkPickerDialog> createState() => _RelinkPickerDialogState();
}

class _RelinkPickerDialogState extends State<_RelinkPickerDialog> {
  bool _loading = true;
  bool _error = false;
  List<RelinkCandidateRun> _candidates = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final c = await widget.training
          .fetchRelinkCandidates(widget.workout)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _candidates = c;
        _loading = false;
      });
    } catch (e, s) {
      debugPrint('_RelinkPickerDialog._fetch failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final currentId = widget.workout.completedRunId;

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error) {
      body = Text(l10n.workoutRelinkError);
    } else if (_candidates.isEmpty) {
      body = Text(l10n.workoutRelinkEmpty);
    } else {
      body = ListView.builder(
        shrinkWrap: true,
        itemCount: _candidates.length,
        itemBuilder: (ctx, i) {
          final run = _candidates[i];
          final isCurrent = run.id == currentId;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(formatDateShort(run.startedAt, tag)),
            subtitle: Text(
              '${fmtKm(run.distanceM, 2)} · ${fmtHms(run.durationS)}',
            ),
            trailing: isCurrent
                ? Text(
                    l10n.workoutRelinkCurrent,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  )
                : null,
            onTap: () => Navigator.of(context).pop(run.id),
          );
        },
      );
    }

    return AlertDialog(
      title: Text(l10n.workoutRelinkTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.workoutRelinkHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(child: body),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}
