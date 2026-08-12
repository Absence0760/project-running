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
import '../typed_decimal.dart';
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
typedef _EnteredSet = ({
  int? reps,
  double? weightKg,
  double? rpe,
  int? durationS,
  double? distanceM,
});

class GymSessionScreen extends StatefulWidget {
  final ApiClient? api;
  final StoredRoutine routine;
  final LocalGymStore gymStore;

  /// A previously persisted draft to restore the runner from — the row the
  /// gym screen's resume card found. Null starts a fresh session.
  final StoredGymWorkout? resumeDraft;

  const GymSessionScreen({
    super.key,
    required this.api,
    required this.routine,
    required this.gymStore,
    this.resumeDraft,
  });

  @override
  State<GymSessionScreen> createState() => _GymSessionScreenState();
}

/// The user's choice at the leave-session prompt (system back, the AppBar
/// back button, or the band's Abandon control). Mirrors the run screen's
/// `_ResumeChoice` shape: stay, exit keeping the recoverable state, or
/// destroy it.
enum _LeaveChoice { keep, leave, discard }

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
  final _duration = TextEditingController();
  final _distance = TextEditingController();

  Timer? _restTimer;
  Timer? _saveTimer;
  int _restRemaining = 0;
  // Wall-clock anchored: derive remaining from real elapsed, not a per-tick
  // counter, so a backgrounded / throttled timer can't drift the rest pause.
  DateTime? _restStartWall;
  int _restTotal = 0;
  // Re-anchored on a draft resume so elapsed continues from the last durable
  // save instead of counting the time the app was gone.
  DateTime _startedAt = DateTime.now().toUtc();

  // What the athlete entered, keyed by expanded-step index — mirrors web
  // GymSessionRunner's sparse `outcomes` so a rewind re-surfaces the prior edit
  // rather than the prescription. A skip drops the step's entry, matching web's
  // `{kind: 'skipped'}` reading back through `enteredFor` as all-nulls.
  final Map<int, _EnteredSet> _enteredByStep = {};

  // The draft's stable id — minted once so the periodic durable save updates a
  // single row rather than appending. Null until the first save creates it.
  String? _draftId;
  bool _finished = false;
  bool _abandoned = false;
  bool _saving = false;
  bool _confirmingLeave = false;

  @override
  void initState() {
    super.initState();
    _steps = _buildSteps();
    _runner = GymWorkoutRunner(steps: _steps, routineId: widget.routine.id);
    final resumed = _restoreFromDraft();
    _events = _runner.events.listen(_onEvent);
    if (!resumed) {
      _runner.start();
    } else {
      if (_runner.isComplete) _finished = true;
      _seedInputs();
    }
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
    _duration.dispose();
    _distance.dispose();
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
                  targetDistanceM: r.exercises[p].sets[i].targetDistanceM,
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
            targetDistanceM: s.targetDistanceM?.toDouble(),
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
    final prior = _enteredByStep[_runner.currentStepIndex];
    _reps.text = (prior?.reps ?? step?.targetRepsMin)?.toString() ?? '';
    final weightKg = prior?.weightKg ?? step?.targetWeightKg;
    _weight.text =
        weightKg == null ? '' : WeightFormat.value(weightKg, activeWeightUnit);
    _rpe.text = rpeInputString(prior?.rpe ?? step?.targetRpe);
    // Deliberately NOT seeded from the target: what gets logged has to be
    // what the athlete actually did, and a pre-filled target would be
    // indistinguishable from a recorded one.
    _duration.text = prior?.durationS?.toString() ?? '';
    _distance.text = prior?.distanceM?.toString() ?? '';
  }

  _EnteredSet _entered() {
    final reps = int.tryParse(_reps.text.trim());
    final weightKg = WeightFormat.parseToKg(_weight.text, activeWeightUnit);
    final rpe = parseTypedDecimal(_rpe.text);
    return (
      reps: reps,
      weightKg: weightKg,
      rpe: rpe,
      durationS: int.tryParse(_duration.text.trim()),
      distanceM: parseTypedDecimal(_distance.text),
    );
  }

  void _publishBand() {
    final step = _runner.currentStep;
    final e = _entered();
    final entered = e.reps != null ||
        e.weightKg != null ||
        e.durationS != null ||
        e.distanceM != null;
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

  bool _targetHit(GymRunnerStep? step, _EnteredSet e) {
    if (step == null) return false;
    final repsOk = step.targetRepsMin == null ||
        (e.reps != null && e.reps! >= step.targetRepsMin!);
    final weightOk = step.targetWeightKg == null ||
        (e.weightKg != null && e.weightKg! >= step.targetWeightKg!);
    final durationOk = step.targetDurationS == null ||
        (e.durationS != null && e.durationS! >= step.targetDurationS!);
    final distanceOk = step.targetDistanceM == null ||
        (e.distanceM != null && e.distanceM! >= step.targetDistanceM!);
    return repsOk && weightOk && durationOk && distanceOk;
  }

  void _onComplete() {
    final step = _runner.currentStep;
    if (step == null) return;
    final e = _entered();
    _enteredByStep[_runner.currentStepIndex] = e;
    _runner.completeSet(
      reps: e.reps,
      weightKg: e.weightKg,
      rpe: e.rpe,
      durationS: e.durationS,
      distanceM: e.distanceM,
    );
  }

  void _onSkip() {
    _enteredByStep.remove(_runner.currentStepIndex);
    _runner.skipStep();
  }

  void _onRewind() => _runner.rewindStep();

  // Derived from the runner's results, the same source `_metadataTrio` reads,
  // so a rewind can't leave the flat set rows disagreeing with
  // `gym_step_results`. Distance has no `gym_sets` column, so a distance-only
  // set legitimately writes no flat row — it is carried (and graded) through
  // the metadata step-results instead. Mirrors web GymSessionRunner.buildSets.
  List<GymSetInput> _buildSets() => [
        for (final r in _runner.snapshotResults())
          if (r.status == GymRunnerStepStatus.completed &&
              (r.actualReps != null ||
                  r.actualWeightKg != null ||
                  r.actualDurationS != null))
            (
              exerciseName: r.step.exerciseName,
              reps: r.actualReps,
              weightKg: r.actualWeightKg,
              rpe: r.actualRpe,
              setType: r.step.setType,
              durationS: r.actualDurationS,
              // Routine steps bind to logged sets by normalised name, not a
              // catalogue id, so a routine-run set logs free-text.
              exerciseId: null,
            ),
      ];

  // True while there's session state a plain pop would strand: logged sets,
  // an already-persisted draft, or a finished-but-unsaved run of steps.
  bool get _dirty =>
      _draftId != null || _finished || _buildSets().isNotEmpty;

  Future<_LeaveChoice> _confirmLeave() async {
    final l10n = AppLocalizations.of(context);
    return await showDialog<_LeaveChoice>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.gymSessionLeaveTitle),
            content: Text(l10n.gymSessionLeaveBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, _LeaveChoice.discard),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error),
                child: Text(l10n.gymSessionDiscardConfirm),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, _LeaveChoice.leave),
                child: Text(l10n.gymSessionLeaveDraft),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, _LeaveChoice.keep),
                child: Text(l10n.gymSessionKeepGoing),
              ),
            ],
          ),
        ) ??
        _LeaveChoice.keep;
  }

  Future<void> _applyLeaveChoice(_LeaveChoice choice) async {
    final navigator = Navigator.of(context);
    switch (choice) {
      case _LeaveChoice.keep:
        return;
      case _LeaveChoice.leave:
        final saved = await _durableSave(force: true);
        if (!mounted) return;
        // Popping on a failed write is how a whole session disappears: the
        // runner asked to KEEP the draft, so staying put with the sets still
        // in memory is the only answer that doesn't throw their work away.
        // They can retry, keep going, or discard on purpose.
        if (!saved) {
          showTopBanner(
              context, AppLocalizations.of(context).gymSessionLeaveSaveFailed);
          return;
        }
        navigator.pop();
      case _LeaveChoice.discard:
        _runner.abandon();
        await _discardDraft();
        if (mounted) navigator.pop();
    }
  }

  Future<void> _onAbandon() async {
    final choice = await _confirmLeave();
    await _applyLeaveChoice(choice);
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
        .asMap()
        .entries
        .map((e) => PlannedSetRef(
              exerciseKey: e.value.exerciseKey,
              stepIndex: e.key,
              setIndex: e.value.setIndex,
              setType: e.value.setType,
              targetRepsMin: e.value.targetRepsMin,
              targetRepsMax: e.value.targetRepsMax,
              targetWeightKg: e.value.targetWeightKg,
              targetDurationS: e.value.targetDurationS,
              targetDistanceM: e.value.targetDistanceM,
            ))
        .toList();
    final actual = <ActualSetRef>[];
    for (final entry in _runner.snapshotResults().asMap().entries) {
      final r = entry.value;
      if (r.status != GymRunnerStepStatus.completed) continue;
      actual.add(ActualSetRef(
        exerciseKey: r.step.exerciseKey,
        stepIndex: entry.key,
        setIndex: r.step.setIndex,
        reps: r.actualReps,
        weightKg: r.actualWeightKg,
        durationS: r.actualDurationS,
        distanceM: r.actualDistanceM,
      ));
    }
    final adherence = computeRoutineAdherence(planned, actual);
    final plannedByKey = {
      for (final p in planned) refKey(p.exerciseKey, p.stepIndex): p,
    };
    final actualByKey = {
      for (final a in actual) refKey(a.exerciseKey, a.stepIndex): a,
    };
    final stepResults = adherence.sets.map((s) {
      final key = refKey(s.exerciseKey, s.stepIndex);
      final p = plannedByKey[key];
      final a = actualByKey[key];
      return {
        'exercise_key': s.exerciseKey,
        'step_index': s.stepIndex,
        'set_index': s.setIndex,
        'status': s.status.name,
        'reps_delta': s.repsDelta,
        'weight_delta_kg': s.weightDeltaKg,
        'target_reps_min': p?.targetRepsMin,
        'target_reps_max': p?.targetRepsMax,
        'target_weight_kg': p?.targetWeightKg,
        'target_duration_s': p?.targetDurationS,
        'target_distance_m': p?.targetDistanceM,
        'actual_reps': a?.reps,
        'actual_weight_kg': a?.weightKg,
        'actual_duration_s': a?.durationS,
        'actual_distance_m': a?.distanceM,
      };
    }).toList();
    return {
      MetadataKeys.routineId: widget.routine.id,
      MetadataKeys.gymStepResults: stepResults,
      MetadataKeys.gymAdherence: adherence.verdict.name,
    };
  }

  // Rebuild the runner from a persisted draft by replaying its ordered
  // per-step outcomes through the public runner API — the current step is
  // derived, never stored, so an edited routine degrades to "replay what
  // still fits" instead of landing on a phantom step. Runs before the event
  // subscription exists, so replayed transitions and rest starts are dropped
  // rather than ticking timers. Best-effort: an unreadable snapshot falls
  // back to a fresh start (still onto the same draft row, so the next
  // durable save can't fork a duplicate).
  bool _restoreFromDraft() {
    final draft = widget.resumeDraft;
    if (draft == null) return false;
    _draftId = draft.id;
    try {
      final meta = draft.row['metadata'];
      final snap = meta is Map ? meta[MetadataKeys.gymSessionDraft] : null;
      if (snap is! Map) return false;
      _runner.start();
      final results = snap['results'];
      if (results is List) {
        for (final r in results) {
          if (r is! Map || _runner.isComplete) continue;
          if (r['status'] == 'completed') {
            final entered = (
              reps: (r['reps'] as num?)?.toInt(),
              weightKg: (r['weight_kg'] as num?)?.toDouble(),
              rpe: (r['rpe'] as num?)?.toDouble(),
              durationS: (r['duration_s'] as num?)?.toInt(),
              distanceM: (r['distance_m'] as num?)?.toDouble(),
            );
            _enteredByStep[_runner.currentStepIndex] = entered;
            _runner.completeSet(
              reps: entered.reps,
              weightKg: entered.weightKg,
              rpe: entered.rpe,
              durationS: entered.durationS,
              distanceM: entered.distanceM,
            );
          } else {
            _runner.skipStep();
          }
        }
      }
      final savedS = (draft.row['duration_s'] as num?)?.toInt();
      if (savedS != null && savedS > 0) {
        _startedAt =
            DateTime.now().toUtc().subtract(Duration(seconds: savedS));
      }
      return true;
    } catch (e) {
      debugPrint('gym session draft restore failed: $e');
      return false;
    }
  }

  // The runner's ordered per-step outcomes, without snapshotResults()'s
  // synthetic not-yet-done entry for the current step (its stepIndex equals
  // currentStepIndex; every real outcome sits strictly before it).
  List<Map<String, dynamic>> _draftResults() => [
        for (final r in _runner.snapshotResults())
          if (r.stepIndex < _runner.currentStepIndex)
            {
              'step_index': r.stepIndex,
              'status': r.status == GymRunnerStepStatus.completed
                  ? 'completed'
                  : 'skipped',
              'reps': r.actualReps,
              'weight_kg': r.actualWeightKg,
              'rpe': r.actualRpe,
              'duration_s': r.actualDurationS,
              'distance_m': r.actualDistanceM,
            },
      ];

  Map<String, dynamic> _draftMetadata() => {
        MetadataKeys.routineId: widget.routine.id,
        MetadataKeys.gymSessionDraft: {
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'results': _draftResults(),
        },
      };

  // Crash-safe incremental persistence — keep the entered sets in a single
  // draft workout so a force-kill mid-session is recoverable. Mirrors
  // run_screen._saveInProgress. The draft metadata carries the runner
  // snapshot the gym screen's resume card restores from. Best-effort: a
  // write failure leaves the in-memory state intact for the next tick / the
  // final save. [force] lets the leave-with-draft path persist a finished-
  // but-unsaved session; the periodic tick must NOT write after finish, or
  // it could race _finishAndSave and clobber the final metadata trio.
  /// Returns whether the write landed. The best-effort swallow is only
  /// correct for the periodic tick; when the runner has explicitly ASKED to
  /// keep the draft and walk away, a swallowed failure loses the whole
  /// session silently, so that caller checks the result.
  Future<bool> _durableSave({bool force = false}) async {
    if (_abandoned || (_finished && !force)) return true;
    final sets = _buildSets();
    if (sets.isEmpty && _draftId == null) return true;
    try {
      if (_draftId == null) {
        final stored = await widget.gymStore.createLocal(
          title: widget.routine.title,
          startedAt: _startedAt,
          durationS: _durationS(),
          sets: sets,
          metadata: _draftMetadata(),
        );
        _draftId = stored.id;
      } else {
        await widget.gymStore.updateLocal(
          _draftId!,
          durationS: _durationS(),
          sets: sets,
          metadata: _draftMetadata(),
        );
      }
      return true;
    } catch (e) {
      debugPrint('gym session durable save failed: $e');
      return false;
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
      final sets = _buildSets();
      if (_draftId == null) {
        final stored = await widget.gymStore.createLocal(
          title: widget.routine.title,
          startedAt: _startedAt,
          durationS: _durationS(),
          sets: sets,
          metadata: metadata,
        );
        _draftId = stored.id;
      } else {
        await widget.gymStore.updateLocal(
          _draftId!,
          durationS: _durationS(),
          sets: sets,
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

  // Pop-time guard, mirroring DiscardGuard's shape — but not DiscardGuard
  // itself: this isn't a form and the choice isn't binary. Leaving a live
  // session has a third, non-destructive outcome (keep the draft and come
  // back through the gym screen's resume card), so the pop routes through
  // the same three-way dialog the Abandon control uses. Explicit
  // `Navigator.pop` calls (finish-save, the dialog's own leave/discard)
  // bypass the guard by design.
  Future<void> _onPopAttempt(Object? result) async {
    if (_confirmingLeave || _saving) return;
    final navigator = Navigator.of(context);
    if (_abandoned || !_dirty) {
      navigator.pop(result);
      return;
    }
    _confirmingLeave = true;
    final choice = await _confirmLeave();
    _confirmingLeave = false;
    if (mounted) await _applyLeaveChoice(choice);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = widget.routine.title.trim();
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onPopAttempt(result);
      },
      child: _buildScaffold(l10n, title),
    );
  }

  Widget _buildScaffold(AppLocalizations l10n, String title) {
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
            if (_runner.currentStep?.targetDurationS != null) ...[
              const SizedBox(width: 12),
              Expanded(child: _field(_duration, l10n.gymDuration, false)),
            ],
            if (_runner.currentStep?.targetDistanceM != null) ...[
              const SizedBox(width: 12),
              Expanded(child: _field(_distance, l10n.gymDistance, true)),
            ],
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
      ),
    );
  }

  // Counts every set the athlete logged a value for, including a distance-only
  // one — which `_buildSets` legitimately omits because it has no `gym_sets`
  // column. Mirrors web GymSessionRunner's `loggedCount`.
  int _completedSetCount() => _runner
      .snapshotResults()
      .where((r) =>
          r.status == GymRunnerStepStatus.completed &&
          (r.actualReps != null ||
              r.actualWeightKg != null ||
              r.actualDurationS != null ||
              r.actualDistanceM != null))
      .length;

  Widget _finishView(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.flag_outlined, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            l10n.gymSessionSetProgress(_completedSetCount(), _steps.length),
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
