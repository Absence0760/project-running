import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../gym_prs.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_gym_store.dart';
import '../widgets/gym_compose_sheet.dart';
import 'gym_detail_screen.dart';

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

  const GymScreen({super.key, required this.api, required this.store});

  @override
  State<GymScreen> createState() => _GymScreenState();
}

class _GymScreenState extends State<GymScreen> {
  bool _refreshing = false;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
    _refresh();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChange);
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
      await widget.store.replaceFromServer(fresh);
      if (widget.store.hasPending) {
        await widget.store.syncWithServer(api);
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
    );
    if (saved == true) await _maybeSync();
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
                          l10n.gymVolumeShort(volume),
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
