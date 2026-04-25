import 'package:flutter/material.dart';

/// Post-run review surface for a structured workout. Reads the
/// `workout_step_results` + `workout_adherence` keys on `runs.metadata`
/// (registered in `docs/metadata.md`) and renders the planned-vs-actual
/// table. Hidden when the keys are absent.
///
/// Mirrors the web `/runs/[id]` "Workout" section so a runner sees the
/// same review whether they open the run on the phone or on web.
class WorkoutReviewSection extends StatelessWidget {
  final Map<String, dynamic>? metadata;
  const WorkoutReviewSection({super.key, required this.metadata});

  @override
  Widget build(BuildContext context) {
    final raw = metadata?['workout_step_results'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    final adherence = metadata?['workout_adherence'] as String?;

    final steps = <WorkoutStepReview>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      steps.add(WorkoutStepReview.fromMap(entry));
    }
    if (steps.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Text('Workout', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (adherence != null) AdherencePill(adherence: adherence),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _headerRow(theme),
                for (var i = 0; i < steps.length; i++)
                  _stepRow(theme, steps[i], last: i == steps.length - 1),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
      ],
    );
  }

  Widget _headerRow(ThemeData theme) {
    final outline = theme.colorScheme.outline;
    Widget cell(String label,
        {int flex = 1, TextAlign align = TextAlign.start}) {
      return Expanded(
        flex: flex,
        child: Text(
          label.toUpperCase(),
          textAlign: align,
          style: theme.textTheme.labelSmall?.copyWith(
            color: outline,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          cell('Step', flex: 3),
          cell('Plan', flex: 2, align: TextAlign.right),
          cell('Actual', flex: 2, align: TextAlign.right),
          cell('Pace', flex: 2, align: TextAlign.right),
          cell('Δ', flex: 2, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _stepRow(ThemeData theme, WorkoutStepReview s, {required bool last}) {
    final divider = BorderSide(color: theme.dividerColor);
    final muted = theme.colorScheme.outline;
    final skipped = s.status == 'skipped';

    Widget cell(String text,
        {int flex = 1,
        TextAlign align = TextAlign.start,
        Color? color,
        FontWeight? weight}) {
      return Expanded(
        flex: flex,
        child: Text(
          text,
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color ?? (skipped ? muted : null),
            fontWeight: weight,
            decoration: skipped ? TextDecoration.lineThrough : null,
          ),
        ),
      );
    }

    final delta = paceDeltaOf(s);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: last ? BorderSide.none : divider),
      ),
      child: Row(
        children: [
          cell(s.label, flex: 3, weight: FontWeight.w600),
          cell('${(s.targetDistanceM / 1000).toStringAsFixed(2)} km',
              flex: 2, align: TextAlign.right),
          cell('${(s.actualDistanceM / 1000).toStringAsFixed(2)} km',
              flex: 2, align: TextAlign.right),
          cell(formatPace(s.actualPaceSecPerKm),
              flex: 2, align: TextAlign.right),
          Expanded(
            flex: 2,
            child: Text(
              skipped ? 'skip' : delta.label,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: delta.color(theme),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkoutStepReview {
  final String label;
  final String kind;
  final double targetDistanceM;
  final double actualDistanceM;
  final int targetPaceSecPerKm;
  final int? actualPaceSecPerKm;
  final String status;

  const WorkoutStepReview({
    required this.label,
    required this.kind,
    required this.targetDistanceM,
    required this.actualDistanceM,
    required this.targetPaceSecPerKm,
    required this.actualPaceSecPerKm,
    required this.status,
  });

  factory WorkoutStepReview.fromMap(Map raw) {
    final kind = raw['kind']?.toString() ?? 'steady';
    final repIndex = (raw['rep_index'] as num?)?.toInt();
    final repTotal = (raw['rep_total'] as num?)?.toInt();
    String label;
    switch (kind) {
      case 'warmup':
        label = 'Warmup';
      case 'cooldown':
        label = 'Cooldown';
      case 'steady':
        label = 'Steady';
      case 'rep':
        label = repIndex != null && repTotal != null
            ? 'Rep $repIndex/$repTotal'
            : 'Rep';
      case 'recovery':
        label = repIndex != null && repTotal != null
            ? 'Recovery $repIndex/${repTotal}'
            : 'Recovery';
      default:
        label = kind;
    }
    return WorkoutStepReview(
      label: label,
      kind: kind,
      targetDistanceM: (raw['target_distance_m'] as num?)?.toDouble() ?? 0,
      actualDistanceM: (raw['actual_distance_m'] as num?)?.toDouble() ?? 0,
      targetPaceSecPerKm:
          (raw['target_pace_sec_per_km'] as num?)?.toInt() ?? 0,
      actualPaceSecPerKm: (raw['actual_pace_sec_per_km'] as num?)?.toInt(),
      status: raw['status']?.toString() ?? 'completed',
    );
  }
}

enum PaceDeltaTone { neutral, on, amber, off }

class PaceDelta {
  final String label;
  final PaceDeltaTone tone;
  const PaceDelta(this.label, this.tone);

  Color color(ThemeData theme) {
    switch (tone) {
      case PaceDeltaTone.on:
        return Colors.green;
      case PaceDeltaTone.amber:
        return Colors.amber;
      case PaceDeltaTone.off:
        return theme.colorScheme.error;
      case PaceDeltaTone.neutral:
        return theme.colorScheme.outline;
    }
  }
}

PaceDelta paceDeltaOf(WorkoutStepReview s) {
  if (s.actualPaceSecPerKm == null) {
    return const PaceDelta('—', PaceDeltaTone.neutral);
  }
  final diff = s.actualPaceSecPerKm! - s.targetPaceSecPerKm;
  if (diff.abs() < 1) return const PaceDelta('on', PaceDeltaTone.on);
  final sign = diff > 0 ? '+' : '−';
  final tol = 10; // matches recorder default
  final mag = diff.abs();
  final tone = mag <= tol
      ? PaceDeltaTone.on
      : (mag <= tol * 2 ? PaceDeltaTone.amber : PaceDeltaTone.off);
  return PaceDelta('$sign${mag}s', tone);
}

String formatPace(int? secPerKm) {
  if (secPerKm == null || secPerKm <= 0) return '—';
  final m = secPerKm ~/ 60;
  final s = secPerKm % 60;
  return '$m:${s.toString().padLeft(2, '0')}/km';
}

class AdherencePill extends StatelessWidget {
  final String adherence;
  const AdherencePill({super.key, required this.adherence});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = switch (adherence) {
      'completed' => (Colors.green.shade100, Colors.green.shade900),
      'partial' => (Colors.amber.shade100, Colors.amber.shade900),
      'abandoned' =>
        (theme.colorScheme.errorContainer, theme.colorScheme.onErrorContainer),
      _ => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.outline,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        adherence,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
