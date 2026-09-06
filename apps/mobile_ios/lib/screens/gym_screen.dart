import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show MetadataKeys;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../adaptive_width.dart';
import '../exercise_records.dart';
import '../gym_prs.dart';
import '../gym_session_draft.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_gym_store.dart';
import '../local_routine_store.dart';
import '../preferences.dart';
import '../social_service.dart';
import '../widgets/gym_compose_sheet.dart';
import '../widgets/pending_sync_banner.dart';
import '../widgets/surface_peer_strip.dart';
import '../widgets/top_banner.dart';
import 'gym_detail_screen.dart';
import 'gym_records_screen.dart';
import 'gym_session_screen.dart';
import 'routine_library_screen.dart';
import 'sessions_screen.dart';

/// Total working volume (Σ reps·weight, rounded) for a stored workout — the
/// list-row stat. Sets missing reps or weight contribute nothing.
int gymWorkoutVolume(StoredGymWorkout w) {
  var v = 0.0;
  for (final s in w.sets) {
    final reps = s['reps'] as num?;
    final weight = s['weight_kg'] as num?;
    if (reps != null && weight != null) v += reps * weight;
  }
  return v.round();
}

/// Distinct exercises in a stored workout, bucketed by the canonical grouping
/// key — the same one the PR engine and the server-stamped `exercise_key` use.
int gymExerciseCount(StoredGymWorkout w) => distinctExerciseCount(
      [for (final s in w.sets) (s['exercise_name'] as String?) ?? ''],
    );

List<GymSetLike> _setsToLikes(StoredGymWorkout w) => [
      for (final s in w.sets)
        GymSetLike(
          exerciseName: (s['exercise_name'] as String?) ?? '',
          reps: s['reps'] as num?,
          weightKg: s['weight_kg'] as num?,
        ),
    ];

/// Flatten every stored workout's sets into the dated set list the records
/// + progression surfaces consume (mirrors web `fetchGymSetHistory`). Each
/// set inherits its workout's id + started_at so the roll-up can group by
/// session and date.
List<DatedGymSet> gymSetHistory(List<StoredGymWorkout> workouts) {
  final out = <DatedGymSet>[];
  for (final w in workouts) {
    final startedAt = w.row['started_at'] as String? ?? '';
    for (final s in w.sets) {
      out.add(DatedGymSet(
        workoutId: w.id,
        startedAt: startedAt,
        exerciseName: (s['exercise_name'] as String?) ?? '',
        reps: s['reps'] as num?,
        weightKg: s['weight_kg'] as num?,
      ));
    }
  }
  return out;
}

/// Which workouts set at least one PR. Walk oldest→newest with one running PR
/// tracker so each workout is judged against everything logged before it in a
/// single O(total sets) pass — mirrors web `/gym`'s `prWorkoutIds`.
Set<String> gymPrWorkoutIds(List<StoredGymWorkout> workouts) {
  final ids = <String>{};
  // A workout whose started_at is missing or unparseable sorts last: comparing
  // it equal to every dated workout would make the comparator non-transitive,
  // so it could land anywhere and be judged "prior" to a dated one.
  final ordered = [...workouts]..sort((a, b) {
      final at = a.startedAt;
      final bt = b.startedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
  final tracker = RunningPrTracker();
  for (final w in ordered) {
    if (tracker.judge(_setsToLikes(w)).isNotEmpty) ids.add(w.id);
  }
  return ids;
}

/// Distinct exercise names across all workouts, most-used first — the
/// composer's autocomplete source (history, not a database). The original
/// spelling of the first occurrence is kept for display.
List<String> gymExerciseSuggestions(List<StoredGymWorkout> workouts) {
  final counts = <String, int>{};
  final display = <String, String>{};
  for (final w in workouts) {
    for (final s in w.sets) {
      final raw = ((s['exercise_name'] as String?) ?? '').trim();
      final key = normaliseExerciseName(raw);
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      display.putIfAbsent(key, () => raw);
    }
  }
  final keys = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [for (final k in keys) display[k]!];
}

/// Phase 4 multi-modal Gym (decisions §63). Workout list + PR badges + a
/// log-workout composer, mirroring web `/gym`. Reads + writes route through
/// [LocalGymStore] so logging a lift works offline; a best-effort server
/// fetch overlays the latest workouts on mount and pending writes drain on
/// the next online refresh.
///
/// A labelled peer strip `Log · Routines · Sessions · Records` sits above the
/// list, mirroring web `/gym`'s header links — the gym's planning surfaces
/// (routines, session plans) are named destinations rather than tooltip-only
/// AppBar glyphs (decisions § 488).
class GymScreen extends StatefulWidget {
  /// Optional. When null (no Supabase env vars OR signed-out) the screen
  /// reads + writes exclusively to [LocalGymStore]; the pending queue
  /// drains on the next mount that does have an api.
  final ApiClient? api;
  final LocalGymStore store;

  /// Optional. Forwarded to the routine library → routine detail so a routine
  /// author can publish a personal routine as a club template. Omitting it
  /// hides publishing; reading / adopting club templates never needs it.
  final SocialService? social;

  /// Optional, for tests: an already-initialised routine store. When null the
  /// screen owns (and initialises) its own, as before.
  final LocalRoutineStore? routineStore;

  const GymScreen({
    super.key,
    required this.api,
    required this.store,
    this.social,
    this.routineStore,
  });

  @override
  State<GymScreen> createState() => _GymScreenState();
}

class _GymScreenState extends State<GymScreen> {
  bool _refreshing = false;
  bool _isOnline = true;

  // Exercise catalogue (seeded globals + the user's customs, migration
  // 20270222_001), fetched best-effort on refresh and merged into the
  // composer's autocomplete. Empty offline / signed-out — the composer falls
  // back to history-only suggestions and logs free-text, exactly as before.
  List<GymCatalogueEntry> _catalogue = const [];

  // Routines (gym_programming.md P1) are a parallel planning surface owned by
  // this screen — the same "each surface owns its store" precedent the gym /
  // food stores follow (decisions §122). Lazily init'd; re-hydrates from disk.
  late final LocalRoutineStore _routineStore =
      widget.routineStore ?? LocalRoutineStore();
  bool _routineStoreReady = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
    _routineStore.addListener(_onStoreChange);
    _initRoutines();
    _refresh();
  }

  Future<void> _initRoutines() async {
    if (widget.routineStore == null) {
      try {
        await _routineStore.init();
      } catch (e) {
        debugPrint('gym_screen: routine store init failed: $e');
      }
    }
    // `dir`, not the absence of a throw: a failed init leaves the store
    // resident but directoryless, and every write to it then refuses (§ 660).
    // Offering the Routines peer over one is offering a surface that cannot
    // save anything.
    if (mounted) {
      setState(() => _routineStoreReady = _routineStore.dir != null);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChange);
    _routineStore.removeListener(_onStoreChange);
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    final api = widget.api;
    if (api == null || api.userId == null) {
      if (mounted) setState(() => _isOnline = false);
      return;
    }
    setState(() => _refreshing = true);
    try {
      final fresh = await api.fetchGymWorkoutsWithSets(limit: 100);
      await widget.store.replaceFromServer(fresh, fetchLimit: 100);
      if (widget.store.hasPending) {
        await widget.store.syncWithServer(api);
      }
      // Best-effort catalogue fetch — a failure leaves the prior list / empty,
      // never blocks the workout list.
      try {
        final cat = await api.fetchExerciseCatalogue();
        _catalogue = [
          for (final e in cat)
            (name: e.name, id: e.id, category: e.category, authorId: e.authorId),
        ];
      } catch (e) {
        debugPrint('gym_screen: catalogue fetch failed: $e');
      }
      _isOnline = true;
    } catch (e) {
      _isOnline = false;
      debugPrint('gym_screen: refresh failed, using cache: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _maybeSync() async {
    final api = widget.api;
    if (api == null || !_isOnline) return;
    await widget.store.syncWithServer(api);
    if (mounted && widget.store.hasPending) setState(() {});
  }

  Future<void> _create() async {
    final saved = await showGymComposeSheet(
      context: context,
      store: widget.store,
      suggestions: gymExerciseSuggestions(widget.store.workouts),
      catalogue: _catalogue,
      api: widget.api,
    );
    if (saved == true) await _maybeSync();
  }

  void _openRoutines() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutineLibraryScreen(
          api: widget.api,
          store: _routineStore,
          gymStore: widget.store,
          social: widget.social,
        ),
      ),
    );
  }

  void _openSessions(ApiClient api) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionsScreen(api: api, gymStore: widget.store),
      ),
    );
  }

  void _openRecords() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GymRecordsScreen(api: widget.api, store: widget.store),
      ),
    );
  }

  /// `Log · Routines · Sessions · Records`. Routines waits on the routine
  /// store's disk hydration; Sessions reads the server, so it needs a
  /// signed-in client; Records is data-gated exactly as web's header link is.
  List<SurfacePeer> _peers(
      AppLocalizations l10n, List<StoredGymWorkout> workouts) {
    final api = widget.api;
    return [
      SurfacePeer(label: l10n.gymTabLog),
      if (_routineStoreReady)
        SurfacePeer(label: l10n.gymRoutineTitle, onTap: _openRoutines),
      if (api != null && api.userId != null)
        SurfacePeer(label: l10n.sessionTitle, onTap: () => _openSessions(api)),
      if (exerciseRecords(gymSetHistory(workouts)).isNotEmpty)
        SurfacePeer(label: l10n.gymTabRecords, onTap: _openRecords),
    ];
  }

  Future<void> _open(StoredGymWorkout w) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GymDetailScreen(
          api: widget.api,
          store: widget.store,
          workoutId: w.id,
        ),
      ),
    );
    // The detail screen may have drained / mutated; the store listener
    // already refreshed the list, so nothing more to do here.
  }

  // The newest in-flight guided-session draft whose routine still exists —
  // what the resume card offers to restore. L4 auxiliary read: a malformed
  // row or a broken routine store must degrade to "no card", never break
  // the gym list.
  ({StoredGymWorkout draft, StoredRoutine routine})? _resumableDraft() {
    try {
      if (!_routineStoreReady) return null;
      for (final w in widget.store.workouts) {
        final meta = w.row['metadata'];
        if (!hasGymSessionDraft(meta)) continue;
        final rid = (meta as Map)[MetadataKeys.routineId];
        final routine = rid is String ? _routineStore.byId(rid) : null;
        if (routine == null) continue;
        return (draft: w, routine: routine);
      }
    } catch (e) {
      debugPrint('gym_screen: draft scan failed: $e');
    }
    return null;
  }

  Future<void> _resumeDraft(
      ({StoredGymWorkout draft, StoredRoutine routine}) d) async {
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => GymSessionScreen(
          api: widget.api,
          routine: d.routine,
          gymStore: widget.store,
          resumeDraft: d.draft,
        ),
      ),
    );
    if (saved != null) await _maybeSync();
  }

  /// The run screen's "Finish" analogue: keep the logged sets as a plain
  /// workout without re-entering the runner. Strips the draft marker (no
  /// adherence verdict is claimed — the session never ran to completion).
  Future<void> _saveDraftAsIs(StoredGymWorkout draft) async {
    final l10n = AppLocalizations.of(context);
    try {
      final meta = Map<String, dynamic>.from(
          (draft.row['metadata'] as Map?) ?? const <String, dynamic>{});
      meta.remove(MetadataKeys.gymSessionDraft);
      await widget.store.updateLocal(draft.id, metadata: meta);
      await _maybeSync();
      if (mounted) showTopBanner(context, l10n.gymSessionSaved);
    } catch (e) {
      debugPrint('gym_screen: draft save-as-is failed: $e');
      if (mounted) showTopBanner(context, l10n.gymSessionSaveFailed);
    }
  }

  Future<void> _discardDraft(StoredGymWorkout draft) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.gymSessionDiscardTitle),
            content: Text(l10n.gymSessionDiscardBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.gymRoutineEditorCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error),
                child: Text(l10n.gymSessionDiscardConfirm),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await widget.store.deleteLocal(draft.id);
      await _maybeSync();
    } catch (e) {
      debugPrint('gym_screen: draft discard failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final workouts = widget.store.workouts;
    final pending = widget.store.hasPending || _routineStore.hasPending;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gymTitle),
        actions: [
          IconButton(
            tooltip: l10n.gymLog,
            icon: const Icon(Icons.add),
            onPressed: _refreshing ? null : _create,
          ),
        ],
      ),
      body: contentColumn(
        context,
        Column(
          children: [
            SurfacePeerStrip(
              label: l10n.gymSurfaceLabel,
              peers: _peers(l10n, workouts),
            ),
            if (!_isOnline && !pending)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: theme.colorScheme.surfaceContainerHigh,
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.gymOfflineCached,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            PendingSyncBanner(
              api: widget.api,
              isOnline: _isOnline,
              stores: [widget.store, _routineStore],
            ),
            if (_resumableDraft() case final d?) _draftCard(d, theme, l10n),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: workouts.isEmpty
                    ? EmptyState(
                        icon: Icons.fitness_center,
                        title: l10n.gymEmptyTitle,
                        body: l10n.gymEmptyBody,
                        ctaLabel: l10n.gymLog,
                        onCta: _create,
                      )
                    : _list(workouts, theme, l10n),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(
      List<StoredGymWorkout> workouts, ThemeData theme, AppLocalizations l10n) {
    final prIds = gymPrWorkoutIds(workouts);
    final tag = localeToTag(Localizations.localeOf(context));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: workouts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final w = workouts[i];
        final title = w.workout.title?.trim();
        final started = w.startedAt;
        final volume = gymWorkoutVolume(w);
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => _open(w),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title == null || title.isEmpty
                              ? l10n.gymUntitled
                              : title,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (started != null)
                          Text(
                            formatDateMed(started.toLocal(), tag),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                  if (prIds.contains(w.id)) ...[
                    _prBadge(theme, l10n),
                    const SizedBox(width: 8),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.gymExercisesShort(gymExerciseCount(w)),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                      ),
                      if (volume > 0)
                        Text(
                          // Volume is summed in canonical kg; show it in the
                          // user's weight unit (rounded — it's an aggregate).
                          '${WeightFormat.toDisplay(volume.toDouble(), activeWeightUnit).round()} ${WeightFormat.label(activeWeightUnit)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                  Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _draftCard(({StoredGymWorkout draft, StoredRoutine routine}) d,
      ThemeData theme, AppLocalizations l10n) {
    final title = d.routine.title.trim();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _resumeDraft(d),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.play_circle_outline,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.gymDraftTitle,
                            style: theme.textTheme.titleSmall),
                        Text(
                          '${title.isEmpty ? l10n.gymUntitled : title} · ${l10n.gymDraftSetCount(d.draft.sets.length)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _discardDraft(d.draft),
                      style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error),
                      child: Text(l10n.gymSessionDiscardConfirm),
                    ),
                    TextButton(
                      onPressed: () => _saveDraftAsIs(d.draft),
                      child: Text(l10n.gymDraftSave),
                    ),
                    FilledButton(
                      onPressed: () => _resumeDraft(d),
                      child: Text(l10n.gymDraftResume),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _prBadge(ThemeData theme, AppLocalizations l10n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          l10n.gymPrBadge,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );

}
