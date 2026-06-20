import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../exercise_records.dart';
import '../gym_prs.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_gym_store.dart';
import '../local_routine_store.dart';
import '../preferences.dart';
import '../social_service.dart';
import '../widgets/gym_compose_sheet.dart';
import 'gym_detail_screen.dart';
import 'gym_records_screen.dart';
import 'routine_library_screen.dart';

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

/// Distinct exercise names (case-insensitive) in a stored workout.
int gymExerciseCount(StoredGymWorkout w) {
  final names = <String>{};
  for (final s in w.sets) {
    final n = ((s['exercise_name'] as String?) ?? '').trim().toLowerCase();
    if (n.isNotEmpty) names.add(n);
  }
  return names.length;
}

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

/// Which workouts set at least one PR. Walk oldest→newest accumulating prior
/// sets so each workout is judged against everything logged before it —
/// mirrors web `/gym`'s `prWorkoutIds`.
Set<String> gymPrWorkoutIds(List<StoredGymWorkout> workouts) {
  final ids = <String>{};
  final ordered = [...workouts]..sort((a, b) {
      final at = a.startedAt;
      final bt = b.startedAt;
      if (at == null || bt == null) return 0;
      return at.compareTo(bt);
    });
  final prior = <GymSetLike>[];
  for (final w in ordered) {
    final mine = _setsToLikes(w);
    if (workoutPrs(prior, mine).isNotEmpty) ids.add(w.id);
    prior.addAll(mine);
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
      if (raw.isEmpty) continue;
      final key = raw.toLowerCase();
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

  const GymScreen({
    super.key,
    required this.api,
    required this.store,
    this.social,
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
  final LocalRoutineStore _routineStore = LocalRoutineStore();
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
    try {
      await _routineStore.init();
    } catch (e) {
      debugPrint('gym_screen: routine store init failed: $e');
    }
    if (mounted) setState(() => _routineStoreReady = true);
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
        _catalogue = [for (final e in cat) (name: e.name, id: e.id)];
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
  }

  Future<void> _create() async {
    final saved = await showGymComposeSheet(
      context: context,
      store: widget.store,
      suggestions: gymExerciseSuggestions(widget.store.workouts),
      catalogue: _catalogue,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final workouts = widget.store.workouts;
    final pending = widget.store.hasPending;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gymTitle),
        actions: [
          if (_routineStoreReady)
            IconButton(
              tooltip: l10n.gymRoutineTitle,
              icon: const Icon(Icons.list_alt),
              onPressed: _openRoutines,
            ),
          if (exerciseRecords(gymSetHistory(workouts)).isNotEmpty)
            IconButton(
              tooltip: l10n.gymRecordsTitle,
              icon: const Icon(Icons.emoji_events_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GymRecordsScreen(
                    api: widget.api,
                    store: widget.store,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: l10n.gymLog,
            icon: const Icon(Icons.add),
            onPressed: _refreshing ? null : _create,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isOnline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHigh,
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pending ? l10n.gymOfflineQueued : l10n.gymOfflineCached,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: workouts.isEmpty
                  ? _emptyState(theme, l10n)
                  : _list(workouts, theme, l10n),
            ),
          ),
        ],
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
                                ?.copyWith(color: theme.colorScheme.outline),
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
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                      if (volume > 0)
                        Text(
                          // Volume is summed in canonical kg; show it in the
                          // user's weight unit (rounded — it's an aggregate).
                          '${WeightFormat.toDisplay(volume.toDouble(), activeWeightUnit).round()} ${WeightFormat.label(activeWeightUnit)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
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

  Widget _emptyState(ThemeData theme, AppLocalizations l10n) => ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.fitness_center,
                        size: 64, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(l10n.gymEmptyTitle,
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(
                      l10n.gymEmptyBody,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(l10n.gymLog),
                      onPressed: _create,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}
