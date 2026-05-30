import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:run_recorder/run_recorder.dart';

import '../preferences.dart';
import '../training.dart' show fmtPace;

/// Top-of-map overlay that surfaces the current [WorkoutRunner] step
/// while the run screen is recording. Mirrors the spec in
/// [docs/features/workout_execution.md](../../../../docs/features/workout_execution.md).
///
/// Reads through a [ValueListenable] of `_BandState` snapshots so we
/// don't rebuild the whole run tree every GPS tick — the run screen
/// pushes a new state when transitions or progress events happen.
class WorkoutExecutionBand extends StatelessWidget {
  final ValueListenable<WorkoutBandState> state;
  final VoidCallback onSkip;
  final VoidCallback onRewind;
  final VoidCallback onAbandon;

  const WorkoutExecutionBand({
    super.key,
    required this.state,
    required this.onSkip,
    required this.onRewind,
    required this.onAbandon,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WorkoutBandState>(
      valueListenable: state,
      builder: (_, s, __) => _Band(
        state: s,
        onSkip: onSkip,
        onRewind: onRewind,
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
  // Seconds remaining for duration-based steps. Zero for distance-based
  // (band reads `step.isDurationBased` to pick which to render).
  final Duration remainingDuration;
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
    this.remainingDuration = Duration.zero,
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
  final VoidCallback onRewind;
  final VoidCallback onAbandon;
  const _Band({
    required this.state,
    required this.onSkip,
    required this.onRewind,
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
                  '${step.label} · ${_fmtTarget(step)} '
                  '@ ${fmtPace(step.targetPaceSecPerKm)}',
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
                _fmtRemaining(step),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Rewind only enabled after the first step has advanced —
              // there's nothing to rewind to on step 0. WorkoutRunner
              // returns false safely in that case, but greying the
              // button matches user expectation.
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.currentIndex == 0 ? null : onRewind,
                  icon: const Icon(Icons.skip_previous, size: 16),
                  label: const Text('Rewind'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSkip,
                  icon: const Icon(Icons.skip_next, size: 16),
                  label: const Text('Skip'),
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
    // Mid-workout pill — honour the user's active distance pref so
    // a mi-mode runner sees miles + yards instead of km + metres.
    final unit = activeDistanceUnit;
    if (unit == DistanceUnit.mi) {
      const metresPerMile = 1609.344;
      if (metres >= metresPerMile) {
        return '${(metres / metresPerMile).toStringAsFixed(1)} mi';
      }
      return '${(metres * 1.09361).round()} yd';
    }
    if (metres >= 1000) {
      return '${(metres / 1000).toStringAsFixed(1)} km';
    }
    return '${metres.round()} m';
  }

  static String _fmtDuration(Duration d) {
    final s = d.inSeconds;
    if (s >= 60) {
      final m = s ~/ 60;
      final r = s % 60;
      return r == 0 ? '${m}m' : '${m}m ${r}s';
    }
    return '${s}s';
  }

  // "Rep 3/6 · 400 m" or "Stride · 30s" depending on the step's axis.
  // Picks one or the other so the band header doesn't grow on duration
  // steps (the time target IS the size signal).
  static String _fmtTarget(WorkoutStep step) {
    if (step.isDurationBased) {
      return _fmtDuration(Duration(seconds: step.targetDurationSec!));
    }
    return _fmtDistance(step.targetDistanceMetres);
  }

  String _fmtRemaining(WorkoutStep step) {
    if (step.isDurationBased) {
      return '${_fmtDuration(state.remainingDuration)} to go';
    }
    // Sub-1-unit fragments are the typical case mid-rep, so always
    // render in the small unit (m / yd).
    if (activeDistanceUnit == DistanceUnit.mi) {
      final yards = (state.remainingMetres * 1.09361).round();
      return '$yards yd to go';
    }
    return '${state.remainingMetres.round()} m to go';
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
