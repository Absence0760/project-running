import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:run_recorder/run_recorder.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../gym_adherence.dart';
import '../gym_progression.dart';
import '../gym_routine.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_gym_store.dart';
import '../local_routine_store.dart';
import '../preferences.dart';
import '../progression_prefill.dart';
import '../widgets/gym_execution_band.dart';
import '../widgets/top_banner.dart';

/// Guided gym session — drives a [GymWorkoutRunner] over a routine's expanded
/// per-set steps. The user enters reps / weight / RPE per set, then Complete
/// (logs + advances, starting a rest countdown when the next step carries one),
/// Skip, Previous, or Abandon. On finish the accumulated set results persist as
/// a [StoredGymWorkout] carrying the `{routine_id, gym_step_results,
/// gym_adherence}` metadata trio so the session is reviewable.
///
/// Mirrors web `GymSessionRunner.svelte`. The rest countdown ticks off the
/// setState path through a [ValueNotifier], matching `run_screen`'s live-stats
/// publisher; step transitions go through setState (low cadence). A periodic
/// durable save mirrors `run_screen._saveInProgress` so a force-kill mid-session
/// doesn't lose entered sets.
class GymSessionScreen extends StatefulWidget {
  final ApiClient? api;
  final StoredRoutine routine;
  final LocalGymStore gymStore;

  const GymSessionScreen({
    super.key,
    required this.api,
    required this.routine,
    required this.gymStore,
  });

  @override
  State<GymSessionScreen> createState() => _GymSessionScreenState();
}

class _GymSessionScreenState extends State<GymSessionScreen> {
  static const _saveInterval = Duration(seconds: 10);

  late final GymWorkoutRunner _runner;
  late final List<GymRunnerStep> _steps;
  StreamSubscription<GymExecEvent>? _events;

  final ValueNotifier<GymBandState> _band =
      ValueNotifier<GymBandState>(GymBandState.empty);

  final _reps = TextEditingController();
  final _weight = TextEditingController();
  final _rpe = TextEditingController();

  Timer? _restTimer;
  Timer? _saveTimer;
  int _restRemaining = 0;
  // Wall-clock anchored: derive remaining from real elapsed, not a per-tick
  // counter, so a backgrounded / throttled timer can't drift the rest pause.
  DateTime? _restStartWall;
  int _restTotal = 0;
  final DateTime _startedAt = DateTime.now().toUtc();

  // The accumulated logged sets (Complete + Skip), kept so the durable save and
  // the final write share one source of truth. A skipped set contributes no row.
  final List<GymSetInput> _loggedSets = [];

  // The draft's stable id — minted once so the periodic durable save updates a
  // single row rather than appending. Null until the first save creates it.
  String? _draftId;
  bool _finished = false;
  bool _abandoned = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _steps = _buildSteps();
    _runner = GymWorkoutRunner(steps: _steps, routineId: widget.routine.id);
    _events = _runner.events.listen(_onEvent);
    _runner.start();
    _publishBand();
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint('gym session wakelock enable failed: $e');
    }
    _saveTimer = Timer.periodic(_saveInterval, (_) => _durableSave());
  }

  @override
  void dispose() {
    _events?.cancel();
    _restTimer?.cancel();
    _saveTimer?.cancel();
    _runner.dispose();
    _band.dispose();
    _reps.dispose();
    _weight.dispose();
    _rpe.dispose();
    try {
      WakelockPlus.disable();
    } catch (e) {
      debugPrint('gym session wakelock disable failed: $e');
    }
    super.dispose();
  }

  List<GymRunnerStep> _buildSteps() {
    final r = widget.routine;
    final planned = PlannedRoutine(
      title: r.title,
      exercises: [
        for (var p = 0; p < r.exercises.length; p++)
          PlannedExercise(
            exerciseName: r.exercises[p].exerciseName,
            position: p,
            supersetGroup: r.exercises[p].supersetGroup,
            supersetOrder: r.exercises[p].supersetOrder,
            sets: [
              for (var i = 0; i < r.exercises[p].sets.length; i++)
                PlannedSet(
                  setIndex: i,
                  targetRepsMin: r.exercises[p].sets[i].targetRepsMin,
                  targetRepsMax: r.exercises[p].sets[i].targetRepsMax,
                  targetWeightKg: r.exercises[p].sets[i].targetWeightKg,
                  targetRpe: r.exercises[p].sets[i].targetRpe,
                  setType: r.exercises[p].sets[i].setType,
                  restS: r.exercises[p].sets[i].restS,
                  targetDurationS: r.exercises[p].sets[i].targetDurationS,
                ),
            ],
          ),
      ],
    );
    final expanded = expandRoutineSteps(planned).steps;
    final suggestions = _prefillSuggestions(r);
    return [
      for (final s in expanded)
        () {
          final sug = suggestions[s.exerciseKey];
          return GymRunnerStep(
            exerciseName: s.exerciseName,
            exerciseKey: s.exerciseKey,
            setIndex: s.setIndex,
            setType: s.setType,
            targetRepsMin: (sug?.suggestedRepsMin ?? s.targetRepsMin)?.toInt(),
            targetRepsMax: (sug?.suggestedRepsMax ?? s.targetRepsMax)?.toInt(),
            targetWeightKg:
                (sug?.suggestedWeightKg ?? s.targetWeightKg)?.toDouble(),
            targetRpe: s.targetRpe?.toDouble(),
            restS: s.restS?.toInt(),
            targetDurationS: s.targetDurationS?.toInt(),
            supersetGroup: s.supersetGroup,
          );
        }(),
    ];
  }

  static ProgressionScheme _schemeFromString(String s) {
    switch (s) {
      case 'linear':
        return ProgressionScheme.linear;
      case 'double_progression':
        return ProgressionScheme.doubleProgression;
      case 'five_by_five':
        return ProgressionScheme.fiveByFive;
      case 'percent_cycle':
        return ProgressionScheme.percentCycle;
      case 'rpe_autoreg':
        return ProgressionScheme.rpeAutoreg;
    }
    return ProgressionScheme.none;
  }

  // P4: for each routine exercise carrying a progression scheme, suggest the
  // next targets from its logged history (read from the local gym store) and
  // prefill them onto the expanded steps — still editable in the band. The
  // prescriber only suggests; the runner never auto-logs. Best-effort: a read
  // failure leaves the routine's own targets in place.
  Map<String, ProgressionSuggestion> _prefillSuggestions(StoredRoutine r) {
    final out = <String, ProgressionSuggestion>{};
    try {
      final schemed =
          r.exercises.where((e) => e.progression != 'none').toList();
      if (schemed.isEmpty) return out;
      final history = <DatedLoggedSet>[
        for (final w in widget.gymStore.workouts)
          for (final s in w.sets)
            DatedLoggedSet(
              workoutId: w.id,
              startedAt: w.row['started_at'] as String? ?? '',
              exerciseName: (s['exercise_name'] as String?) ?? '',
              reps: s['reps'] as num?,
              weightKg: s['weight_kg'] as num?,
              rpe: s['rpe'] as num?,
            ),
      ];
      for (final ex in schemed) {
        final last = lastSessionSets(history, ex.exerciseName);
        if (last == null) continue;
        final firstSet = ex.sets.isNotEmpty ? ex.sets.first : null;
        final sug = nextPrescription(ProgressionInput(
          scheme: _schemeFromString(ex.progression),
          lastSets: last,
          targetRepsMin: firstSet?.targetRepsMin,
          targetRepsMax: firstSet?.targetRepsMax,
          params: ex.progressionParams,
        ));
        if (sug.reason == ProgressionReason.none) continue;
        out[ex.exerciseKey] = sug;
      }
    } catch (e) {
      debugPrint('gym session progression prefill failed: $e');
    }
    return out;
  }

  void _onEvent(GymExecEvent e) {
    switch (e) {
      case GymRestStartedEvent(:final restS):
        _startRest(restS);
      case GymStepTransitionEvent():
        _restTimer?.cancel();
        _restRemaining = 0;
        _seedInputs();
        setState(_publishBand);
      case GymWorkoutCompleteEvent():
        _restTimer?.cancel();
        setState(() {
          _finished = true;
          _publishBand();
        });
      case GymWorkoutAbandonedEvent():
        _restTimer?.cancel();
        setState(() {
          _abandoned = true;
          _publishBand();
        });
    }
  }

  void _startRest(int seconds) {
    _restTotal = seconds;
    _restStartWall = DateTime.now();
    _restRemaining = seconds;
    _publishBand();
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final start = _restStartWall;
      if (start == null) {
        t.cancel();
        return;
      }
      final remaining =
          (_restTotal - DateTime.now().difference(start).inSeconds)
              .clamp(0, _restTotal);
      _restRemaining = remaining;
      if (remaining <= 0) {
        _restRemaining = 0;
        t.cancel();
      }
      _publishBand();
    });
  }

  void _seedInputs() {
    final step = _runner.currentStep;
    _reps.text = step?.targetRepsMin?.toString() ?? '';
    _weight.text = step?.targetWeightKg == null
        ? ''
        : WeightFormat.value(step!.targetWeightKg!, activeWeightUnit);
    _rpe.text = step?.targetRpe?.toString() ?? '';
  }

  ({int? reps, double? weightKg, double? rpe, int? durationS}) _entered() {
    final step = _runner.currentStep;
    final reps = int.tryParse(_reps.text.trim());
    final weightKg = WeightFormat.parseToKg(_weight.text, activeWeightUnit);
    final rpe = double.tryParse(_rpe.text.trim().replaceAll(',', '.'));
    return (
      reps: reps,
      weightKg: weightKg,
      rpe: rpe,
      durationS: step?.targetDurationS,
    );
  }

  void _publishBand() {
    final step = _runner.currentStep;
    final e = _entered();
    final entered =
        e.reps != null || e.weightKg != null || e.durationS != null;
    _band.value = GymBandState(
      step: step,
      total: _steps.length,
      currentIndex: _runner.currentStepIndex,
      restRemainingS: _restRemaining,
      entered: entered,
      targetHit: _targetHit(step, e),
      complete: _finished,
      abandoned: _abandoned,
    );
  }

  bool _targetHit(
    GymRunnerStep? step,
    ({int? reps, double? weightKg, double? rpe, int? durationS}) e,
  ) {
    if (step == null) return false;
    final repsOk = step.targetRepsMin == null ||
        (e.reps != null && e.reps! >= step.targetRepsMin!);
    final weightOk = step.targetWeightKg == null ||
        (e.weightKg != null && e.weightKg! >= step.targetWeightKg!);
    final durationOk = step.targetDurationS == null ||
        (e.durationS != null && e.durationS! >= step.targetDurationS!);
    return repsOk && weightOk && durationOk;
  }

  void _onComplete() {
    final step = _runner.currentStep;
    if (step == null) return;
    final e = _entered();
    if (e.reps != null || e.weightKg != null || e.durationS != null) {
      _loggedSets.add((
        exerciseName: step.exerciseName,
        reps: e.reps,
        weightKg: e.weightKg,
        rpe: e.rpe,
        durationS: e.durationS,
      ));
    }
    _runner.completeSet(
      reps: e.reps,
      weightKg: e.weightKg,
      rpe: e.rpe,
      durationS: e.durationS,
    );
  }

  void _onSkip() => _runner.skipStep();

  void _onRewind() {
    if (_runner.rewindStep()) {
      if (_loggedSets.isNotEmpty) _loggedSets.removeLast();
    }
  }

  Future<void> _onAbandon() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.gymSessionDiscardTitle),
            content: Text(l10n.gymSessionDiscardBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.gymRoutineEditorCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(l10n.gymSessionDiscardConfirm),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    _runner.abandon();
    await _discardDraft();
    if (mounted) Navigator.pop(context);
  }

  int _durationS() =>
      DateTime.now().toUtc().difference(_startedAt).inSeconds.clamp(1, 1 << 30);

  // The stored trio mirrors web GymSessionRunner.buildMetadata byte-for-byte:
  // gym_step_results carries the adherence-shaped rows (status hit/partial/
  // missed/extra + deltas + targets + actuals) and gym_adherence the
  // computeRoutineAdherence verdict — so a session logged on either platform
  // reads identically in the web /gym/[id] review panel.
  Map<String, dynamic> _metadataTrio() {
    final planned = _steps
        .map((s) => PlannedSetRef(
              exerciseKey: s.exerciseKey,
              setIndex: s.setIndex,
              setType: s.setType,
              targetRepsMin: s.targetRepsMin,
              targetRepsMax: s.targetRepsMax,
              targetWeightKg: s.targetWeightKg,
              targetDurationS: s.targetDurationS,
            ))
        .toList();
    final actual = <ActualSetRef>[];
    for (final r in _runner.snapshotResults()) {
      if (r.status != GymRunnerStepStatus.completed) continue;
      actual.add(ActualSetRef(
        exerciseKey: r.step.exerciseKey,
        setIndex: r.step.setIndex,
        reps: r.actualReps,
        weightKg: r.actualWeightKg,
        durationS: r.actualDurationS,
      ));
    }
    final adherence = computeRoutineAdherence(planned, actual);
    final plannedByKey = {
      for (final p in planned) '${p.exerciseKey} ${p.setIndex}': p,
    };
    final actualByKey = {
      for (final a in actual) '${a.exerciseKey} ${a.setIndex}': a,
    };
    final stepResults = adherence.sets.map((s) {
      final key = '${s.exerciseKey} ${s.setIndex}';
      final p = plannedByKey[key];
      final a = actualByKey[key];
      return {
        'exercise_key': s.exerciseKey,
        'set_index': s.setIndex,
        'status': s.status.name,
        'reps_delta': s.repsDelta,
        'weight_delta_kg': s.weightDeltaKg,
        'target_reps_min': p?.targetRepsMin,
        'target_reps_max': p?.targetRepsMax,
        'target_weight_kg': p?.targetWeightKg,
        'target_duration_s': p?.targetDurationS,
        'actual_reps': a?.reps,
        'actual_weight_kg': a?.weightKg,
        'actual_duration_s': a?.durationS,
      };
    }).toList();
    return {
      MetadataKeys.routineId: widget.routine.id,
      MetadataKeys.gymStepResults: stepResults,
      MetadataKeys.gymAdherence: adherence.verdict.name,
    };
  }

  // Crash-safe incremental persistence — keep the entered sets in a single
  // draft workout so a force-kill mid-session is recoverable. Mirrors
  // run_screen._saveInProgress. Best-effort: a write failure leaves the
  // in-memory state intact for the next tick / the final save.
  Future<void> _durableSave() async {
    if (_finished || _abandoned || _loggedSets.isEmpty) return;
    try {
      if (_draftId == null) {
        final stored = await widget.gymStore.createLocal(
          title: widget.routine.title,
          startedAt: _startedAt,
          durationS: _durationS(),
          sets: List.of(_loggedSets),
        );
        _draftId = stored.id;
      } else {
        await widget.gymStore.updateLocal(
          _draftId!,
          durationS: _durationS(),
          sets: List.of(_loggedSets),
        );
      }
    } catch (e) {
      debugPrint('gym session durable save failed: $e');
    }
  }

  Future<void> _discardDraft() async {
    final id = _draftId;
    if (id == null) return;
    try {
      await widget.gymStore.deleteLocal(id);
    } catch (e) {
      debugPrint('gym session draft discard failed: $e');
    }
  }

  Future<void> _finishAndSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      final metadata = _metadataTrio();
      if (_draftId == null) {
        final stored = await widget.gymStore.createLocal(
          title: widget.routine.title,
          startedAt: _startedAt,
          durationS: _durationS(),
          sets: List.of(_loggedSets),
          metadata: metadata,
        );
        _draftId = stored.id;
      } else {
        await widget.gymStore.updateLocal(
          _draftId!,
          durationS: _durationS(),
          sets: List.of(_loggedSets),
          metadata: metadata,
        );
      }
      final api = widget.api;
      if (api != null) await widget.gymStore.syncWithServer(api);
      if (mounted) {
        showTopBanner(context, l10n.gymSessionSaved);
        Navigator.pop(context, _draftId);
      }
    } catch (e) {
      debugPrint('gym session finish save failed: $e');
      if (mounted) {
        setState(() => _saving = false);
        showTopBanner(context, l10n.gymSessionSaveFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = widget.routine.title.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(title.isEmpty ? l10n.gymRoutineTitle : title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            GymExecutionBand(
              state: _band,
              onComplete: _onComplete,
              onSkip: _onSkip,
              onRewind: _onRewind,
              onAbandon: _onAbandon,
            ),
            Expanded(
              child: _finished
                  ? _finishView(l10n)
                  : (_abandoned
                      ? const SizedBox.shrink()
                      : _entryView(l10n)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryView(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Expanded(child: _field(_reps, l10n.gymReps, false)),
            const SizedBox(width: 12),
            Expanded(
              child: _field(_weight, WeightFormat.label(activeWeightUnit), true),
            ),
            const SizedBox(width: 12),
            Expanded(child: _field(_rpe, l10n.gymRpe, true)),
          ],
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, bool decimal) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      textAlign: TextAlign.center,
      onChanged: (_) => _publishBand(),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _finishView(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.flag, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            l10n.gymSessionSetProgress(_loggedSets.length, _steps.length),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _onAbandon,
                  child: Text(l10n.gymSessionAbandon),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _finishAndSave,
                  child: Text(l10n.gymSessionFinish),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
