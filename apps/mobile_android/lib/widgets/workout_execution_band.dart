import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:run_recorder/run_recorder.dart';

/// Top-of-map overlay that surfaces the current [WorkoutRunner] step
/// while the run screen is recording. Mirrors the spec in
/// [docs/workout_execution.md](../../../../docs/workout_execution.md).
///
/// Reads through a [ValueListenable] of `_BandState` snapshots so we
/// don't rebuild the whole run tree every GPS tick — the run screen
/// pushes a new state when transitions or progress events happen.
class WorkoutExecutionBand extends StatelessWidget {
  final ValueListenable<WorkoutBandState> state;
  final VoidCallback onSkip;
  final VoidCallback onAbandon;

  const WorkoutExecutionBand({
    super.key,
    required this.state,
    required this.onSkip,
    required this.onAbandon,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WorkoutBandState>(
      valueListenable: state,
      builder: (_, s, __) => _Band(
        state: s,
        onSkip: onSkip,
        onAbandon: onAbandon,
      ),
    );
  }
}

class WorkoutBandState {
  final WorkoutStep? step;
  final int totalSteps;
  final int currentIndex;
  final double progress; // 0..1
  final double remainingMetres;
  final int? actualPaceSecPerKm;
  final PaceAdherence adherence;
  final bool complete;
  final bool abandoned;

  const WorkoutBandState({
    required this.step,
    required this.totalSteps,
    required this.currentIndex,
    required this.progress,
    required this.remainingMetres,
    required this.actualPaceSecPerKm,
    required this.adherence,
    required this.complete,
    required this.abandoned,
  });

  static const empty = WorkoutBandState(
    step: null,
    totalSteps: 0,
    currentIndex: 0,
    progress: 0,
    remainingMetres: 0,
    actualPaceSecPerKm: null,
    adherence: PaceAdherence.onPace,
    complete: false,
    abandoned: false,
  );
}

class _Band extends StatelessWidget {
  final WorkoutBandState state;
  final VoidCallback onSkip;
  final VoidCallback onAbandon;
  const _Band({
    required this.state,
    required this.onSkip,
    required this.onAbandon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.abandoned) {
      return _shell(theme,
          child: Text('Workout abandoned · running freely',
              style: theme.textTheme.bodyMedium));
    }
    final step = state.step;
    if (step == null) {
      if (state.complete) {
        return _shell(theme,
            child: Text(
              'Workout complete · tap stop to save',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ));
      }
      return const SizedBox.shrink();
    }

    return _shell(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${step.label} · ${_fmtDistance(step.targetDistanceMetres)} '
                  '@ ${_fmtPace(step.targetPaceSecPerKm)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _PacePip(adherence: state.adherence, delta: _delta(step)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: theme.dividerColor,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${state.currentIndex + 1}/${state.totalSteps}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              Text(
                '${state.remainingMetres.round()} m to go',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSkip,
                  icon: const Icon(Icons.skip_next, size: 16),
                  label: const Text('Skip step'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAbandon,
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Abandon'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shell(ThemeData theme, {required Widget child}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  int? _delta(WorkoutStep step) {
    final actual = state.actualPaceSecPerKm;
    if (actual == null) return null;
    return actual - step.targetPaceSecPerKm;
  }

  static String _fmtDistance(double metres) {
    if (metres >= 1000) {
      return '${(metres / 1000).toStringAsFixed(1)} km';
    }
    return '${metres.round()} m';
  }

  static String _fmtPace(int secPerKm) {
    final m = secPerKm ~/ 60;
    final s = secPerKm % 60;
    return '$m:${s.toString().padLeft(2, '0')}/km';
  }
}

class _PacePip extends StatelessWidget {
  final PaceAdherence adherence;
  final int? delta;
  const _PacePip({required this.adherence, required this.delta});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (adherence) {
      PaceAdherence.onPace => Colors.green,
      PaceAdherence.ahead || PaceAdherence.behind => Colors.amber,
      PaceAdherence.wayAhead || PaceAdherence.wayBehind =>
        theme.colorScheme.error,
    };
    String label;
    if (delta == null) {
      label = '—';
    } else {
      final sign = delta! >= 0 ? '+' : '−';
      label = '$sign${delta!.abs()}s';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
