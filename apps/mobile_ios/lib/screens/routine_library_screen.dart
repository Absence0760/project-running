import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_gym_store.dart';
import '../local_routine_store.dart';
import '../social_service.dart';
import '../widgets/routine_builder_sheet.dart';
import 'gym_screen.dart' show gymExerciseSuggestions;
import 'routine_detail_screen.dart';

/// The routine library — mirrors web `/gym/routines`. Authored routines,
/// most-recently-modified first; tap → detail. The `New routine` action opens
/// the builder. Self-hiding empty state matches web (no library row in the gym
/// screen until a routine exists; the screen itself is reached from the gym
/// AppBar's Routines action only once one is created OR via the builder).
///
/// Reads + writes route through [LocalRoutineStore] (offline-first); a
/// best-effort server fetch overlays the latest routines on mount and pending
/// writes drain on the next online refresh.
class RoutineLibraryScreen extends StatefulWidget {
  final ApiClient? api;
  final LocalRoutineStore store;

  /// The gym store backs the builder's exercise-name autocomplete (history,
  /// not a database) — mirrors web feeding `fetchGymExerciseNames`.
  final LocalGymStore gymStore;

  /// Optional. Forwarded to [RoutineDetailScreen] so the routine detail can
  /// offer the publish-as-club-template control. Omitting it hides publishing.
  final SocialService? social;

  const RoutineLibraryScreen({
    super.key,
    required this.api,
    required this.store,
    required this.gymStore,
    this.social,
  });

  @override
  State<RoutineLibraryScreen> createState() => _RoutineLibraryScreenState();
}

class _RoutineLibraryScreenState extends State<RoutineLibraryScreen> {
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
      final fresh = await api.fetchGymRoutines(limit: 100);
      final hydrated =
          <({Map<String, dynamic> routine, List<StoredRoutineExercise> exercises})>[];
      for (final r in fresh) {
        final detail = await api.fetchGymRoutineDetail(r.id);
        hydrated.add((
          routine: r.toJson(),
          exercises: detail == null
              ? const []
              : [
                  for (final e in detail.exercises)
                    StoredRoutineExercise(
                      exerciseName: e.exercise.exerciseName,
                      exerciseKey: e.exercise.exerciseKey,
                      supersetGroup: e.exercise.supersetGroup,
                      supersetOrder: e.exercise.supersetOrder,
                      modality: e.exercise.modality,
                      progression: e.exercise.progression,
                      progressionParams: e.exercise.progressionParams is Map
                          ? Map<String, dynamic>.from(
                              e.exercise.progressionParams as Map)
                          : const {},
                      sets: [
                        for (final s in e.sets)
                          StoredRoutineSet(
                            setType: s.setType,
                            targetRepsMin: s.targetRepsMin,
                            targetRepsMax: s.targetRepsMax,
                            targetWeightKg: s.targetWeightKg,
                            targetRpe: s.targetRpe,
                            restS: s.restS,
                            targetDurationS: s.targetDurationS,
                            targetDistanceM: s.targetDistanceM,
                          ),
                      ],
                    ),
                ],
        ));
      }
      await widget.store.replaceFromServer(hydrated);
      if (widget.store.hasPending) {
        await widget.store.syncWithServer(api);
      }
      _isOnline = true;
    } catch (e) {
      _isOnline = false;
      debugPrint('routine_library_screen: refresh failed, using cache: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _create() async {
    final id = await showRoutineBuilderSheet(
      context: context,
      store: widget.store,
      suggestions: gymExerciseSuggestions(widget.gymStore.workouts),
    );
    if (id != null) {
      final api = widget.api;
      if (api != null && _isOnline) await widget.store.syncWithServer(api);
      if (mounted) _open(id);
    }
  }

  void _open(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutineDetailScreen(
          api: widget.api,
          store: widget.store,
          gymStore: widget.gymStore,
          routineId: id,
          social: widget.social,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final routines = widget.store.routines;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gymRoutineTitle),
        actions: [
          IconButton(
            tooltip: l10n.gymRoutineNew,
            icon: const Icon(Icons.add),
            onPressed: _refreshing ? null : _create,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: routines.isEmpty
            ? _emptyState(theme, l10n)
            : _list(routines, theme, l10n),
      ),
    );
  }

  Widget _list(
      List<StoredRoutine> routines, ThemeData theme, AppLocalizations l10n) {
    final tag = localeToTag(Localizations.localeOf(context));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: routines.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = routines[i];
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => _open(r.id),
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
                          r.title.isEmpty ? l10n.gymUntitled : r.title,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          formatDateMed(r.lastModifiedAt.toLocal(), tag),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    l10n.gymRoutineExerciseCount(r.exerciseCount),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
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
                    Icon(Icons.list_alt,
                        size: 64, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(l10n.gymRoutineEmptyTitle,
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(
                      l10n.gymRoutineEmptyBody,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(l10n.gymRoutineNew),
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
