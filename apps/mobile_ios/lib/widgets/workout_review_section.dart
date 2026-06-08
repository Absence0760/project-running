import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../training.dart' show fmtPace;

/// Post-run review surface for a structured workout. Reads the
/// `workout_step_results` + `workout_adherence` keys on `runs.metadata`
/// (registered in `docs/backend/metadata.md`) and renders the planned-vs-actual
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Text(l10n.workoutReviewTitle, style: theme.textTheme.titleMedium),
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
                _headerRow(theme, l10n),
                for (var i = 0; i < steps.length; i++)
                  _stepRow(theme, l10n, steps[i],
                      last: i == steps.length - 1),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
      ],
    );
  }

  Widget _headerRow(ThemeData theme, AppLocalizations l10n) {
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
          cell(l10n.workoutReviewColStep, flex: 3),
          cell(l10n.workoutReviewColPlan, flex: 2, align: TextAlign.right),
          cell(l10n.workoutReviewColActual, flex: 2, align: TextAlign.right),
          cell(l10n.workoutReviewColPace, flex: 2, align: TextAlign.right),
          cell(l10n.workoutReviewColDelta, flex: 2, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _stepRow(ThemeData theme, AppLocalizations l10n, WorkoutStepReview s,
      {required bool last}) {
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
          cell(s.localizedLabel(l10n), flex: 3, weight: FontWeight.w600),
          cell(
            s.isDurationBased
                ? formatStepDuration(s.targetDurationSec!)
                : UnitFormat.distance(s.targetDistanceM, activeDistanceUnit),
            flex: 2,
            align: TextAlign.right,
          ),
          cell(
            s.isDurationBased
                ? formatStepDuration(s.durationSeconds)
                : UnitFormat.distance(s.actualDistanceM, activeDistanceUnit),
            flex: 2,
            align: TextAlign.right,
          ),
          cell(fmtPace(s.actualPaceSecPerKm),
              flex: 2, align: TextAlign.right),
          Expanded(
            flex: 2,
            child: Text(
              skipped ? l10n.workoutReviewSkip : delta.label,
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
  final int? repIndex;
  final int? repTotal;
  final double targetDistanceM;
  final double actualDistanceM;
  // Duration target in seconds. Non-null when this step was authored as
  // duration-based (v2). When set, the review table renders time on the
  // plan + actual columns instead of km.
  final int? targetDurationSec;
  final int durationSeconds;
  final int targetPaceSecPerKm;
  final int? actualPaceSecPerKm;
  final int toleranceSecPerKm;
  final String status;

  const WorkoutStepReview({
    required this.label,
    required this.kind,
    this.repIndex,
    this.repTotal,
    required this.targetDistanceM,
    required this.actualDistanceM,
    this.targetDurationSec,
    this.durationSeconds = 0,
    required this.targetPaceSecPerKm,
    required this.actualPaceSecPerKm,
    this.toleranceSecPerKm = 10,
    required this.status,
  });

  bool get isDurationBased =>
      targetDurationSec != null && targetDurationSec! > 0;

  /// Localized step label. Derives from [kind] (+ optional rep index /
  /// total) so the label follows the device locale at render time;
  /// falls back to the parsed [label] for unknown kinds.
  String localizedLabel(AppLocalizations l10n) {
    final hasReps = repIndex != null && repTotal != null;
    switch (kind) {
      case 'warmup':
        return l10n.workoutReviewLabelWarmup;
      case 'cooldown':
        return l10n.workoutReviewLabelCooldown;
      case 'steady':
        return l10n.workoutReviewLabelSteady;
      case 'rep':
        return hasReps
            ? l10n.workoutReviewLabelRepN(repIndex!, repTotal!)
            : l10n.workoutReviewLabelRep;
      case 'recovery':
        return hasReps
            ? l10n.workoutReviewLabelRecoveryN(repIndex!, repTotal!)
            : l10n.workoutReviewLabelRecovery;
      case 'walk':
        return hasReps
            ? l10n.workoutReviewLabelWalkN(repIndex!, repTotal!)
            : l10n.workoutReviewLabelWalk;
      default:
        return label;
    }
  }

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
      case 'walk':
        label = repIndex != null && repTotal != null
            ? 'Walk $repIndex/${repTotal}'
            : 'Walk';
      default:
        label = kind;
    }
    return WorkoutStepReview(
      label: label,
      kind: kind,
      repIndex: repIndex,
      repTotal: repTotal,
      targetDistanceM: (raw['target_distance_m'] as num?)?.toDouble() ?? 0,
      actualDistanceM: (raw['actual_distance_m'] as num?)?.toDouble() ?? 0,
      targetDurationSec: (raw['target_duration_s'] as num?)?.toInt(),
      durationSeconds: (raw['duration_s'] as num?)?.toInt() ?? 0,
      targetPaceSecPerKm:
          (raw['target_pace_sec_per_km'] as num?)?.toInt() ?? 0,
      actualPaceSecPerKm: (raw['actual_pace_sec_per_km'] as num?)?.toInt(),
      toleranceSecPerKm:
          (raw['tolerance_sec_per_km'] as num?)?.toInt() ?? 10,
      status: raw['status']?.toString() ?? 'completed',
    );
  }
}

/// Formats a duration in seconds for the review table: "30s", "1m 30s",
/// "5m". Mirrors the band's same-name helper.
String formatStepDuration(int seconds) {
  if (seconds >= 60) {
    final m = seconds ~/ 60;
    final r = seconds % 60;
    return r == 0 ? '${m}m' : '${m}m ${r}s';
  }
  return '${seconds}s';
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
  final tol = s.toleranceSecPerKm;
  final mag = diff.abs();
  final tone = mag <= tol
      ? PaceDeltaTone.on
      : (mag <= tol * 2 ? PaceDeltaTone.amber : PaceDeltaTone.off);
  return PaceDelta('$sign${mag}s', tone);
}


class AdherencePill extends StatelessWidget {
  final String adherence;
  const AdherencePill({super.key, required this.adherence});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = switch (adherence) {
      'completed' => (Colors.green.shade100, Colors.green.shade900),
      // amber.900 text on amber.100 is only 2.4:1 — fails WCAG AA. #6D4C00 on
      // amber.100 is 6.7:1. Pinned by contrast_guard_test.dart.
      'partial' => (Colors.amber.shade100, const Color(0xFF6D4C00)),
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
