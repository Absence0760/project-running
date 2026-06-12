import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:run_recorder/run_recorder.dart';

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';

/// Top-of-screen overlay that surfaces the current [GymWorkoutRunner] step
/// while a guided gym session is running. Mirrors
/// [widgets/workout_execution_band.dart] for runs (and the web
/// `GymExecutionBand.svelte`): driven through a [ValueListenable] of
/// [GymBandState] snapshots so the rest-countdown tick and per-set entry don't
/// rebuild the whole session tree.
class GymExecutionBand extends StatelessWidget {
  final ValueListenable<GymBandState> state;
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final VoidCallback onRewind;
  final VoidCallback onAbandon;

  const GymExecutionBand({
    super.key,
    required this.state,
    required this.onComplete,
    required this.onSkip,
    required this.onRewind,
    required this.onAbandon,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GymBandState>(
      valueListenable: state,
      builder: (_, s, __) => _Band(
        state: s,
        onComplete: onComplete,
        onSkip: onSkip,
        onRewind: onRewind,
        onAbandon: onAbandon,
      ),
    );
  }
}

class GymBandState {
  final GymRunnerStep? step;
  final int total;
  final int currentIndex;
  final int restRemainingS;
  // Whether the current set has any entered reps / weight / duration yet —
  // drives the reps/load-hit pip without coupling the band to the controllers.
  final bool entered;
  // Whether the entered values reach the step's targets (green vs amber pip).
  final bool targetHit;
  final bool complete;
  final bool abandoned;

  const GymBandState({
    required this.step,
    required this.total,
    required this.currentIndex,
    required this.restRemainingS,
    required this.entered,
    required this.targetHit,
    required this.complete,
    required this.abandoned,
  });

  static const empty = GymBandState(
    step: null,
    total: 0,
    currentIndex: 0,
    restRemainingS: 0,
    entered: false,
    targetHit: false,
    complete: false,
    abandoned: false,
  );
}

class _Band extends StatelessWidget {
  final GymBandState state;
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final VoidCallback onRewind;
  final VoidCallback onAbandon;
  const _Band({
    required this.state,
    required this.onComplete,
    required this.onSkip,
    required this.onRewind,
    required this.onAbandon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (state.abandoned) {
      return _shell(theme,
          child: Text(l10n.gymSessionAbandon,
              style: theme.textTheme.bodyMedium));
    }
    final step = state.step;
    if (step == null) {
      if (state.complete) {
        return _shell(theme,
            child: Text(
              l10n.gymSessionComplete,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.exerciseName.isEmpty ? '—' : step.exerciseName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.gymSessionStep(
                        step.exerciseName,
                        state.currentIndex + 1,
                        state.total,
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.gymSessionTarget,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmtTarget(l10n, step),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              _SetPip(entered: state.entered, targetHit: state.targetHit),
            ],
          ),
          if (state.restRemainingS > 0) ...[
            const SizedBox(height: 6),
            Text(
              l10n.gymSessionRestRemaining(state.restRemainingS),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.currentIndex == 0 ? null : onRewind,
                  icon: const Icon(Icons.skip_previous, size: 16),
                  label: Text(l10n.gymSessionRewind),
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
                  label: Text(l10n.gymSessionSkipSet),
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
                  label: Text(l10n.gymSessionAbandon),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onComplete,
            icon: const Icon(Icons.check, size: 18),
            label: Text(l10n.gymSessionLogSet),
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

  String _fmtTarget(AppLocalizations l10n, GymRunnerStep step) {
    final parts = <String>[];
    final lo = step.targetRepsMin;
    if (lo != null) {
      final hi = step.targetRepsMax;
      parts.add(hi != null && hi != lo ? '$lo–$hi' : '$lo');
    }
    final kg = step.targetWeightKg;
    if (kg != null) {
      parts.add(WeightFormat.format(kg, activeWeightUnit));
    }
    final repWeight = parts.join(' × ');
    final dur = step.targetDurationS;
    if (dur != null && dur > 0) {
      final durLabel = l10n.gymDurationValue('$dur');
      return repWeight.isEmpty ? durLabel : '$repWeight · $durLabel';
    }
    return repWeight.isEmpty ? l10n.gymSessionTarget : repWeight;
  }
}

class _SetPip extends StatelessWidget {
  final bool entered;
  final bool targetHit;
  const _SetPip({required this.entered, required this.targetHit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = !entered
        ? (theme.colorScheme.outline, Icons.radio_button_unchecked)
        : targetHit
            ? (Colors.green, Icons.check_circle)
            : (Colors.amber, Icons.error_outline);
    return Icon(color: color, size: 22, icon);
  }
}
