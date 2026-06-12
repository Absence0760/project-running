import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../gym_routine.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_gym_store.dart';
import '../local_routine_store.dart';
import '../preferences.dart';
import '../widgets/gym_compose_sheet.dart';
import '../widgets/top_banner.dart';
import 'gym_screen.dart' show gymExerciseSuggestions;

/// Detail view for a single routine — mirrors web `/gym/routines/[id]`.
/// Planned targets per exercise; primary `Start routine` (P1: prefill-only —
/// opens the gym composer seeded with the routine's targets as a new log's
/// actuals via `prefillFromRoutine`, no execution loop), plus Delete behind a
/// confirm dialog. Reads from [LocalRoutineStore] (offline-first).
class RoutineDetailScreen extends StatefulWidget {
  final ApiClient? api;
  final LocalRoutineStore store;
  final LocalGymStore gymStore;
  final String routineId;

  const RoutineDetailScreen({
    super.key,
    required this.api,
    required this.store,
    required this.gymStore,
    required this.routineId,
  });

  @override
  State<RoutineDetailScreen> createState() => _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends State<RoutineDetailScreen> {
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChange);
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  Future<void> _maybeSync() async {
    final api = widget.api;
    if (api == null || !_isOnline) return;
    await widget.store.syncWithServer(api);
  }

  /// "Start routine" (P1: prefill-only — no execution loop). Expand the saved
  /// plan into editable composer blocks via [prefillFromRoutine], then open a
  /// fresh gym log seeded with those targets as actuals. Mirrors web's
  /// startRoutine → GymEditor seed.
  Future<void> _start(StoredRoutine r) async {
    final planned = PlannedRoutine(
      title: r.title,
      exercises: [
        for (var p = 0; p < r.exercises.length; p++)
          PlannedExercise(
            exerciseName: r.exercises[p].exerciseName,
            position: p,
            sets: [
              for (var i = 0; i < r.exercises[p].sets.length; i++)
                PlannedSet(
                  setIndex: i,
                  targetRepsMin: r.exercises[p].sets[i].targetRepsMin,
                  targetRepsMax: r.exercises[p].sets[i].targetRepsMax,
                  targetWeightKg: r.exercises[p].sets[i].targetWeightKg,
                  targetRpe: r.exercises[p].sets[i].targetRpe,
                ),
            ],
          ),
      ],
    );
    final blocks = prefillFromRoutine(planned);
    final seed = <GymSetInput>[];
    for (final b in blocks) {
      if (b.name.trim().isEmpty) continue;
      for (final s in b.sets) {
        seed.add((
          exerciseName: b.name,
          reps: s.reps.isEmpty ? null : int.tryParse(s.reps),
          // prefillFromRoutine carries canonical kg in weightKg.
          weightKg: s.weightKg?.toDouble(),
          rpe: s.rpe.isEmpty ? null : double.tryParse(s.rpe),
        ));
      }
    }
    final saved = await showGymComposeSheet(
      context: context,
      store: widget.gymStore,
      seedSets: seed,
      seedTitle: r.title,
      suggestions: gymExerciseSuggestions(widget.gymStore.workouts),
    );
    if (saved == true) {
      final api = widget.api;
      if (api != null) await widget.gymStore.syncWithServer(api);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _delete(StoredRoutine r) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.gymRoutineDeleteConfirmTitle),
            content: Text(l10n.gymRoutineDeleteConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.gymRoutineEditorCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(l10n.gymRoutineDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await widget.store.deleteLocal(r.id);
    await _maybeSync();
    if (mounted) {
      showTopBanner(context, l10n.gymRoutineDeleted);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final r = widget.store.byId(widget.routineId);
    final title = r?.title.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title == null || title.isEmpty ? l10n.gymRoutineTitle : title,
        ),
        actions: r == null
            ? null
            : [
                IconButton(
                  tooltip: l10n.gymRoutineDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(r),
                ),
              ],
      ),
      body: r == null
          ? Center(
              child: Text(
                l10n.gymRoutineNotFound,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            )
          : _body(r, theme, l10n),
      floatingActionButton: r == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _start(r),
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.gymRoutineStart),
            ),
    );
  }

  Widget _body(StoredRoutine r, ThemeData theme, AppLocalizations l10n) {
    final notes = r.notes?.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          l10n.gymRoutineExerciseCount(r.exerciseCount),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        if (notes != null && notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(notes, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 16),
        for (final ex in r.exercises) _exerciseCard(ex, theme, l10n),
      ],
    );
  }

  Widget _exerciseCard(
      StoredRoutineExercise ex, ThemeData theme, AppLocalizations l10n) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ex.exerciseName.isEmpty ? '—' : ex.exerciseName,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.gymRoutineTargetReps,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.gymRoutineTargetWeight(
                        WeightFormat.label(activeWeightUnit)),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final s in ex.sets)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_repLabel(s),
                          style: theme.textTheme.bodyMedium),
                    ),
                    Expanded(
                      child: Text(
                        s.targetWeightKg == null
                            ? '—'
                            : WeightFormat.format(
                                s.targetWeightKg!, activeWeightUnit),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _repLabel(StoredRoutineSet s) {
    final lo = s.targetRepsMin;
    if (lo == null) return '—';
    final hi = s.targetRepsMax;
    if (hi != null && hi != lo) return '$lo–$hi';
    return '$lo';
  }
}
