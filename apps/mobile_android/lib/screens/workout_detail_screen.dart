import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../training.dart';
import '../training_service.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final w = await widget.training.fetchWorkout(widget.workoutId);
    if (!mounted) return;
    setState(() {
      _workout = w;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final w = _workout;
    if (w == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Workout not found.')),
      );
    }
    final theme = Theme.of(context);
    final kind = workoutKindFromDb(w.kind);
    final structure = w.structure == null
        ? null
        : WorkoutStructure.fromJson(w.structure!);

    return Scaffold(
      appBar: AppBar(title: Text(workoutKindLabel(kind))),
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
          Text(workoutKindLabel(kind),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              if (w.targetDistanceM != null)
                _metric(theme, 'Distance', fmtKm(w.targetDistanceM, 2)),
              if (w.targetDurationSeconds != null)
                _metric(theme, 'Duration', fmtHms(w.targetDurationSeconds)),
              if (w.targetPaceSecPerKm != null)
                _metric(
                  theme,
                  'Target pace',
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
                  Text('Completed',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () async {
                      await widget.training
                          .markCompleted(widget.workoutId, null);
                      _load();
                    },
                    child: const Text('Unlink'),
                  ),
                ],
              ),
            ),
          ],
          if (w.notes != null && w.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(theme, 'Notes'),
            const SizedBox(height: 4),
            Text(w.notes!, style: theme.textTheme.bodyMedium),
          ],
          if (structure != null) ...[
            const SizedBox(height: 16),
            _section(theme, 'Structure'),
            const SizedBox(height: 4),
            _structureList(theme, structure),
          ],
          const SizedBox(height: 20),
          _section(theme, 'How to run it'),
          const SizedBox(height: 4),
          Text(_advice(kind), style: theme.textTheme.bodyMedium),
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

  Widget _structureList(ThemeData theme, WorkoutStructure s) {
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
      add('Warmup',
          '${fmtKm(s.warmup!['distance_m'] as num, 1)} @ easy');
    }
    if (s.repeats != null) {
      final r = s.repeats!;
      add('Repeats',
          '${r['count']}× ${fmtKm(r['distance_m'] as num, 2)} @ '
          '${fmtPace((r['pace_sec_per_km'] as num).toInt())} with '
          '${fmtKm(r['recovery_distance_m'] as num, 2)} ${r['recovery_pace']}');
    }
    if (s.steady != null) {
      final st = s.steady!;
      add('Steady',
          '${fmtKm(st['distance_m'] as num, 1)} @ '
          '${fmtPace((st['pace_sec_per_km'] as num).toInt())}');
    }
    if (s.cooldown != null) {
      add('Cooldown',
          '${fmtKm(s.cooldown!['distance_m'] as num, 1)} @ easy');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items,
    );
  }

  String _advice(WorkoutKind k) => switch (k) {
        WorkoutKind.easy ||
        WorkoutKind.recovery =>
          "Conversational pace. If you can't hold a conversation, you're running it too fast.",
        WorkoutKind.long =>
          'Stay relaxed. Aim for steady breathing. Drop 10% of the distance if weather is rough or you\'re sore — don\'t skip.',
        WorkoutKind.tempo =>
          '"Comfortably hard". You should feel like you could hold the pace for about an hour at peak effort, but no longer.',
        WorkoutKind.interval =>
          "Run the reps hard enough that the last one feels like the first. Don't pick a pace you can only hold for two or three reps.",
        WorkoutKind.marathonPace =>
          'Lock into goal marathon pace exactly. This is a rehearsal session — no faster, no slower.',
        WorkoutKind.race =>
          "Trust the plan. Don't chase a PB in the first mile.",
        WorkoutKind.rest =>
          'Rest day — if you need to move, walk or stretch.',
      };
}
