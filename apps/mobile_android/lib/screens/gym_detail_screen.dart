import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../exercise_history.dart';
import '../gym_prs.dart';
import '../gym_routine.dart' as routine_helper;
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_gym_store.dart';
import '../local_routine_store.dart';
import '../preferences.dart';
import '../widgets/gym_compose_sheet.dart';
import '../widgets/routine_builder_sheet.dart';
import '../widgets/top_banner.dart';
import 'gym_exercise_screen.dart';
import 'gym_screen.dart' show gymExerciseSuggestions, gymSetHistory;

typedef _SetRef = ({int index, Map<String, dynamic> set});
typedef _Block = ({String name, List<_SetRef> sets});

/// Detail view for a single gym workout — mirrors web `/gym/[id]`. Exercise
/// blocks with per-exercise PR chips, each set's reps × weight + RPE, notes,
/// and owner edit / delete. Reads from [LocalGymStore] (offline-first); the
/// store only holds the signed-in user's own workouts, so edit / delete are
/// always available.
class GymDetailScreen extends StatefulWidget {
  final ApiClient? api;
  final LocalGymStore store;
  final String workoutId;

  const GymDetailScreen({
    super.key,
    required this.api,
    required this.store,
    required this.workoutId,
  });

  @override
  State<GymDetailScreen> createState() => _GymDetailScreenState();
}

class _GymDetailScreenState extends State<GymDetailScreen> {
  bool _isOnline = true;

  // Self-owned routine store so "Save as routine" works wherever the detail
  // screen is reached from (gym list, history, dashboard) without threading a
  // store through every call site — same lazily-init'd, per-surface ownership
  // as the gym/food stores (decisions §122). gym_programming.md P1.
  final LocalRoutineStore _routineStore = LocalRoutineStore();
  bool _routineStoreReady = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
    _ensureLoaded();
    _initRoutines();
  }

  Future<void> _initRoutines() async {
    try {
      await _routineStore.init();
    } catch (e) {
      debugPrint('gym_detail_screen: routine store init failed: $e');
    }
    if (mounted) setState(() => _routineStoreReady = true);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChange);
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  /// When reached via a deep link (G5 future) the store may be empty — pull
  /// the user's workouts once so this one (and the PR history) hydrate. The
  /// list screen already does this, so the common path is a no-op.
  Future<void> _ensureLoaded() async {
    final api = widget.api;
    if (api == null || api.userId == null) {
      if (mounted) setState(() => _isOnline = false);
      return;
    }
    if (widget.store.byId(widget.workoutId) != null) return;
    try {
      final fresh = await api.fetchGymWorkoutsWithSets(limit: 100);
      await widget.store.replaceFromServer(fresh);
    } catch (e) {
      _isOnline = false;
      debugPrint('gym_detail_screen: load failed: $e');
    }
  }

  Future<void> _maybeSync() async {
    final api = widget.api;
    if (api == null || !_isOnline) return;
    await widget.store.syncWithServer(api);
  }

  Future<void> _edit(StoredGymWorkout w) async {
    final saved = await showGymComposeSheet(
      context: context,
      store: widget.store,
      existing: w,
      suggestions: gymExerciseSuggestions(widget.store.workouts),
    );
    if (saved == true) await _maybeSync();
  }

  /// "Save as routine" — promote this logged session's grouped sets into a
  /// routine draft (gym_routine.dart#routineFromWorkout), then open the routine
  /// builder seeded with it. Mirrors web's openSaveAsRoutine. The builder owns
  /// the create + sync.
  Future<void> _saveAsRoutine(StoredGymWorkout w) async {
    final draft = routine_helper.routineFromWorkout(
      w.workout.title,
      [
        for (final s in w.sets)
          routine_helper.LoggedSet(
            exerciseName: (s['exercise_name'] as String?) ?? '',
            reps: s['reps'] as num?,
            weightKg: s['weight_kg'] as num?,
            rpe: s['rpe'] as num?,
          ),
      ],
    );
    // Reuse prefillFromRoutine so the builder's seed matches web's path
    // exactly (ordered blocks, single-value rep prefill).
    final blocks = routine_helper.prefillFromRoutine(
      routine_helper.PlannedRoutine(
        title: draft.title,
        exercises: [
          for (final e in draft.exercises)
            routine_helper.PlannedExercise(
              exerciseName: e.exerciseName,
              position: e.position,
              sets: [
                for (final st in e.sets)
                  routine_helper.PlannedSet(
                    setIndex: st.setIndex,
                    targetRepsMin: st.targetRepsMin?.toInt(),
                    targetRepsMax: st.targetRepsMax?.toInt(),
                    targetWeightKg: st.targetWeightKg?.toDouble(),
                    targetRpe: st.targetRpe?.toDouble(),
                  ),
              ],
            ),
        ],
      ),
    );
    final seed = [
      for (final b in blocks)
        RoutineSeedExercise(
          name: b.name,
          sets: [
            for (final s in b.sets)
              RoutineSeedSet(reps: s.reps, weightKg: s.weightKg?.toDouble(), rpe: s.rpe),
          ],
        ),
    ];
    final id = await showRoutineBuilderSheet(
      context: context,
      store: _routineStore,
      seedExercises: seed,
      seedTitle: draft.title,
      suggestions: gymExerciseSuggestions(widget.store.workouts),
    );
    if (id != null) {
      final api = widget.api;
      if (api != null && _isOnline) await _routineStore.syncWithServer(api);
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).gymRoutineCreated);
      }
    }
  }

  /// "Repeat last" — instantiate this session's sets into a fresh gym log (no
  /// saved routine required). Mirrors web's openRepeat → GymEditor seed.
  Future<void> _repeatLast(StoredGymWorkout w) async {
    final seed = <GymSetInput>[
      for (final s in w.sets)
        (
          exerciseName: (s['exercise_name'] as String?) ?? '',
          reps: (s['reps'] as num?)?.toInt(),
          weightKg: (s['weight_kg'] as num?)?.toDouble(),
          rpe: (s['rpe'] as num?)?.toDouble(),
          durationS: (s['duration_s'] as num?)?.toInt(),
        ),
    ];
    final saved = await showGymComposeSheet(
      context: context,
      store: widget.store,
      seedSets: seed,
      seedTitle: w.workout.title,
      suggestions: gymExerciseSuggestions(widget.store.workouts),
    );
    if (saved == true) await _maybeSync();
  }

  /// Flip the workout's visibility (public ↔ private). Offline-first: the
  /// local store write (pendingUpdate) is durable + drains on the next sync,
  /// mirroring web's setGymWorkoutPublic + the route-detail toggle.
  Future<void> _toggleVisibility(StoredGymWorkout w) async {
    final next = !w.workout.isPublic;
    try {
      await widget.store.updateLocal(w.id, isPublic: next);
      await _maybeSync();
    } catch (e) {
      debugPrint('gym_detail_screen: visibility toggle failed: $e');
      if (mounted) {
        showTopBanner(
          context,
          AppLocalizations.of(context).gymVisibilityFailed('$e'),
        );
      }
    }
  }

  Future<void> _delete(StoredGymWorkout w) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.gymDeleteConfirmTitle),
            content: Text(l10n.gymDeleteConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.gymEditorCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(l10n.gymDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await widget.store.deleteLocal(w.id);
    await _maybeSync();
    if (mounted) Navigator.pop(context);
  }

  List<GymSetLike> _setsToLikes(StoredGymWorkout w) => [
        for (final s in w.sets)
          GymSetLike(
            exerciseName: (s['exercise_name'] as String?) ?? '',
            reps: s['reps'] as num?,
            weightKg: s['weight_kg'] as num?,
          ),
      ];

  /// PR kinds this workout achieved, per (normalised) exercise, judged
  /// against every set the user logged in an earlier workout.
  Map<String, List<PrKind>> _prByExercise(StoredGymWorkout w) {
    final startedAt = w.startedAt;
    final prior = <GymSetLike>[];
    for (final o in widget.store.workouts) {
      if (o.id == w.id) continue;
      final ot = o.startedAt;
      if (startedAt != null && ot != null && !ot.isBefore(startedAt)) continue;
      prior.addAll(_setsToLikes(o));
    }
    final out = <String, List<PrKind>>{};
    for (final r in workoutPrs(prior, _setsToLikes(w))) {
      out[normaliseExerciseName(r.exerciseName)] = r.kinds;
    }
    return out;
  }

  /// "vs last time" per exercise: the previous weighted session of this
  /// exercise (before this workout) + how this session's heaviest set compares
  /// to it — the progressive-overload cue the all-time PR chips can't give.
  /// Keyed by normalised exercise name.
  Map<String, ({ExerciseSession prev, double? deltaKg})> _prevByExercise(
    StoredGymWorkout w,
    List<_Block> blocks,
  ) {
    final out = <String, ({ExerciseSession prev, double? deltaKg})>{};
    final startedAt = w.row['started_at'] as String? ?? '';
    if (startedAt.isEmpty) return out;
    final history = gymSetHistory(widget.store.workouts);
    for (final block in blocks) {
      final key = normaliseExerciseName(block.name);
      if (key == '' || out.containsKey(key)) continue;
      final prev = previousExerciseSession(history, block.name, startedAt);
      if (prev == null) continue;
      double? thisTop;
      for (final ref in block.sets) {
        final weight = (ref.set['weight_kg'] as num?)?.toDouble();
        if (weight != null && weight > 0 && (thisTop == null || weight > thisTop)) {
          thisTop = weight;
        }
      }
      final deltaKg =
          thisTop != null ? (thisTop - prev.topWeightKg) * 10 : null;
      out[key] = (
        prev: prev,
        deltaKg: deltaKg == null ? null : deltaKg.roundToDouble() / 10,
      );
    }
    return out;
  }

  List<_Block> _blocks(StoredGymWorkout w) {
    final blocks = <_Block>[];
    for (var i = 0; i < w.sets.length; i++) {
      final s = w.sets[i];
      final name = (s['exercise_name'] as String?) ?? '';
      if (blocks.isNotEmpty && blocks.last.name == name) {
        blocks.last.sets.add((index: i, set: s));
      } else {
        blocks.add((name: name, sets: [(index: i, set: s)]));
      }
    }
    return blocks;
  }

  String _setSummary(Map<String, dynamic> s, AppLocalizations l10n) {
    final parts = <String>[];
    final reps = s['reps'] as num?;
    final weight = s['weight_kg'] as num?;
    if (reps != null) parts.add(_numStr(reps));
    // Stored canonical kg -> the user's display unit.
    if (weight != null) {
      parts.add(WeightFormat.format(weight.toDouble(), activeWeightUnit));
    }
    final repWeight = parts.join(' × ');
    final duration = s['duration_s'] as num?;
    if (duration != null) {
      final dur = l10n.gymDurationValue(_numStr(duration));
      return repWeight.isEmpty ? dur : '$repWeight · $dur';
    }
    return repWeight;
  }

  String _prLabel(PrKind kind, AppLocalizations l10n) {
    switch (kind) {
      case PrKind.weight:
        return l10n.gymPrWeight;
      case PrKind.volume:
        return l10n.gymPrVolume;
      case PrKind.e1rm:
        return l10n.gymPrE1rm;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final w = widget.store.byId(widget.workoutId);
    final title = w?.workout.title?.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title == null || title.isEmpty ? l10n.gymTitle : title,
        ),
        actions: w == null
            ? null
            : [
                IconButton(
                  tooltip:
                      w.workout.isPublic ? l10n.gymMakePrivate : l10n.gymMakePublic,
                  icon: Icon(w.workout.isPublic ? Icons.public : Icons.public_off),
                  onPressed: () => _toggleVisibility(w),
                ),
                IconButton(
                  tooltip: l10n.gymRoutineRepeatLast,
                  icon: const Icon(Icons.replay),
                  onPressed: () => _repeatLast(w),
                ),
                if (_routineStoreReady)
                  IconButton(
                    tooltip: l10n.gymRoutineSaveAsRoutine,
                    icon: const Icon(Icons.list_alt),
                    onPressed: () => _saveAsRoutine(w),
                  ),
                IconButton(
                  tooltip: l10n.gymEdit,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(w),
                ),
                IconButton(
                  tooltip: l10n.gymDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(w),
                ),
              ],
      ),
      body: w == null
          ? Center(
              child: Text(
                l10n.gymNotFound,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            )
          : _body(w, theme, l10n),
    );
  }

  Widget _body(StoredGymWorkout w, ThemeData theme, AppLocalizations l10n) {
    final tag = localeToTag(Localizations.localeOf(context));
    final started = w.startedAt;
    final prByExercise = _prByExercise(w);
    final blocks = _blocks(w);
    final prevByExercise = _prevByExercise(w, blocks);
    final notes = w.workout.notes?.trim();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            if (started != null)
              Text(
                formatDateMed(started.toLocal(), tag),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            if (started != null) const SizedBox(width: 8),
            _visibilityChip(w, theme, l10n),
          ],
        ),
        const SizedBox(height: 16),
        for (final block in blocks)
          _exerciseBlock(block, prByExercise, prevByExercise, theme, l10n),
        if (notes != null && notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            l10n.gymNotes.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(notes, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }

  Widget _exerciseBlock(
    _Block block,
    Map<String, List<PrKind>> prByExercise,
    Map<String, ({ExerciseSession prev, double? deltaKg})> prevByExercise,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final key = normaliseExerciseName(block.name);
    final prs = prByExercise[key] ?? const [];
    final lastTime = prevByExercise[key];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  block.name.isEmpty ? '—' : block.name,
                  style: theme.textTheme.titleSmall,
                ),
                for (final kind in prs) _prChip(kind, theme, l10n),
              ],
            ),
            if (lastTime != null) ...[
              const SizedBox(height: 6),
              _lastTimeHint(block.name, lastTime, theme, l10n),
            ],
            const SizedBox(height: 8),
            for (final ref in block.sets)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        l10n.gymSetN(ref.index + 1),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        () {
                          final s = _setSummary(ref.set, l10n);
                          return s.isEmpty ? '—' : s;
                        }(),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (ref.set['rpe'] != null)
                      Text(
                        '${l10n.gymRpe} ${_numStr(ref.set['rpe'] as num)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _lastTimeHint(
    String exerciseName,
    ({ExerciseSession prev, double? deltaKg}) lt,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final tag = localeToTag(Localizations.localeOf(context));
    final dt = DateTime.tryParse(lt.prev.startedAt);
    final dateText = dt == null ? lt.prev.startedAt : formatDateMed(dt.toLocal(), tag);
    final prevSet = _topSetLine(lt.prev);
    final delta = lt.deltaKg;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GymExerciseScreen(
            api: widget.api,
            store: widget.store,
            exerciseName: exerciseName,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Flexible(
              child: Text(
                '${l10n.gymDetailLastTime(dateText)}: $prevSet',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (delta != null && delta != 0) ...[
              const SizedBox(width: 6),
              Icon(
                delta > 0 ? Icons.trending_up : Icons.trending_down,
                size: 14,
                color: delta > 0
                    ? Color.alphaBlend(
                        Colors.green.withValues(alpha: 0.5),
                        theme.colorScheme.onSurface,
                      )
                    : theme.colorScheme.outline,
              ),
              Text(
                _deltaText(delta),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: delta > 0
                      ? Color.alphaBlend(
                          Colors.green.withValues(alpha: 0.5),
                          theme.colorScheme.onSurface,
                        )
                      : theme.colorScheme.outline,
                ),
              ),
            ],
            Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }

  String _topSetLine(ExerciseSession prev) {
    final w = WeightFormat.format(prev.topWeightKg, activeWeightUnit);
    return prev.topWeightReps != null
        ? '$w × ${_numStr(prev.topWeightReps!)}'
        : w;
  }

  String _deltaText(double delta) {
    final mag = WeightFormat.format(delta.abs(), activeWeightUnit);
    return '${delta > 0 ? '+' : '−'}$mag';
  }

  Widget _visibilityChip(
    StoredGymWorkout w,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final isPublic = w.workout.isPublic;
    final fg = isPublic ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPublic ? Icons.public : Icons.lock, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            isPublic ? l10n.gymPublic : l10n.gymPrivate,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _prChip(PrKind kind, ThemeData theme, AppLocalizations l10n) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _prLabel(kind, l10n),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );

  static String _numStr(num v) {
    if (v is int) return v.toString();
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }
}
