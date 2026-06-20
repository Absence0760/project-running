import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../backend_timeout.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_gym_store.dart';
import '../local_routine_store.dart';
import '../preferences.dart';
import '../social_service.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';
import 'routine_detail_screen.dart';

/// Public gym-routine library — browse + search routines published as public
/// templates that any signed-in user can adopt (migration 20270224_001).
/// Mirrors web `/gym/routines/library`. Tapping a routine opens a preview with
/// an adopt (clone) action. Reached from the Library action on
/// [RoutineLibraryScreen].
class RoutinePublicLibraryScreen extends StatefulWidget {
  final ApiClient? api;

  /// The caller's own routine store — the adopt path hydrates the new personal
  /// routine into it so the routine detail renders offline-first.
  final LocalRoutineStore store;
  final LocalGymStore gymStore;

  /// Forwarded to [RoutineDetailScreen] so an adopted routine's detail can
  /// still offer the publish controls.
  final SocialService? social;

  const RoutinePublicLibraryScreen({
    super.key,
    required this.api,
    required this.store,
    required this.gymStore,
    this.social,
  });

  @override
  State<RoutinePublicLibraryScreen> createState() =>
      _RoutinePublicLibraryScreenState();
}

class _RoutinePublicLibraryScreenState
    extends State<RoutinePublicLibraryScreen> {
  List<({GymRoutineRow routine, String? authorHandle})> _routines = const [];
  bool _loading = true;
  bool _error = false;
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null) {
      setState(() {
        _error = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final routines = await api
          .fetchPublicGymRoutineLibrary(query: _query)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _routines = routines;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _onSearch(String v) {
    _query = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  void _open(({GymRoutineRow routine, String? authorHandle}) entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutinePublicPreviewScreen(
          api: widget.api,
          store: widget.store,
          gymStore: widget.gymStore,
          social: widget.social,
          entry: entry,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.gymLibraryTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.gymLibrarySearchHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onSearch,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error
                    ? ErrorState(
                        message: l10n.gymLibraryLoadError, onRetry: _load)
                    : _routines.isEmpty
                        ? Center(
                            child: Text(
                              _query.trim().isEmpty
                                  ? l10n.gymLibraryEmpty
                                  : l10n.gymLibraryEmptySearch(_query),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _routines.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final e = _routines[i];
                                final author =
                                    e.authorHandle ?? l10n.gymLibraryAnonymous;
                                return Card(
                                  margin: EdgeInsets.zero,
                                  child: ListTile(
                                    onTap: () => _open(e),
                                    title: Text(e.routine.title,
                                        style: theme.textTheme.titleMedium),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(l10n.gymLibraryByAuthor(author)),
                                          const SizedBox(height: 4),
                                          Text(
                                            l10n.gymRoutineExerciseCount(
                                                e.routine.exerciseCount),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                    color: theme
                                                        .colorScheme.outline),
                                          ),
                                        ],
                                      ),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// Preview of one public-library routine + an adopt (clone) action. Fetches the
/// routine's exercises + planned sets via [ApiClient.fetchGymRoutineDetail]
/// (RLS exposes a public template to any signed-in viewer) and clones it into
/// the caller's library on adopt. Mirrors web `/gym/routines/library/[id]`.
class RoutinePublicPreviewScreen extends StatefulWidget {
  final ApiClient? api;
  final LocalRoutineStore store;
  final LocalGymStore gymStore;
  final SocialService? social;
  final ({GymRoutineRow routine, String? authorHandle}) entry;

  const RoutinePublicPreviewScreen({
    super.key,
    required this.api,
    required this.store,
    required this.gymStore,
    required this.entry,
    this.social,
  });

  @override
  State<RoutinePublicPreviewScreen> createState() =>
      _RoutinePublicPreviewScreenState();
}

class _RoutinePublicPreviewScreenState
    extends State<RoutinePublicPreviewScreen> {
  List<({GymRoutineExerciseRow exercise, List<GymRoutineSetRow> sets})>
      _exercises = const [];
  bool _loading = true;
  bool _adopting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final detail = await api
          .fetchGymRoutineDetail(widget.entry.routine.id)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _exercises = detail?.exercises ?? const [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _adopt() async {
    final api = widget.api;
    if (api == null || _adopting) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _adopting = true);
    try {
      final newId = await api
          .cloneGymRoutineTemplate(widget.entry.routine.id)
          .timeout(kBackendLoadTimeout);
      // The clone lands as a personal routine server-side; hydrate it into the
      // caller's store so the detail renders offline-first (mirrors the club
      // Adopt path in club_detail_screen).
      await widget.store.syncWithServer(api);
      final detail = await api.fetchGymRoutineDetail(newId);
      if (detail != null) {
        await widget.store.replaceFromServer([
          (
            routine: detail.routine.toJson(),
            exercises: [
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
                      : const <String, dynamic>{},
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
          ),
        ]);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RoutineDetailScreen(
            api: api,
            store: widget.store,
            gymStore: widget.gymStore,
            routineId: newId,
            social: widget.social,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _adopting = false);
      showTopBanner(context, l10n.gymLibraryAdoptFailed);
    }
  }

  String _repLabel(GymRoutineSetRow s) {
    final lo = s.targetRepsMin;
    if (lo == null) return '—';
    final hi = s.targetRepsMax;
    if (hi != null && hi != lo) return '$lo–$hi';
    return '$lo';
  }

  String _targetLabel(
      String modality, GymRoutineSetRow s, AppLocalizations l10n) {
    if (modality == 'time') {
      return s.targetDurationS == null
          ? '—'
          : l10n.gymDurationValue('${s.targetDurationS}');
    }
    if (modality == 'distance') {
      return s.targetDistanceM == null ? '—' : '${s.targetDistanceM} m';
    }
    final reps = _repLabel(s);
    if (modality == 'bodyweight_reps') return reps;
    final weight = s.targetWeightKg == null
        ? '—'
        : WeightFormat.format(s.targetWeightKg!, activeWeightUnit);
    return '$reps × $weight';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final r = widget.entry.routine;
    final author = widget.entry.authorHandle ?? l10n.gymLibraryAnonymous;
    return Scaffold(
      appBar: AppBar(title: Text(r.title)),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _adopting ? null : _adopt,
              icon: _adopting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.library_add),
              label: Text(
                  _adopting ? l10n.gymLibraryAdopting : l10n.gymLibraryAdopt),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(l10n.gymLibraryByAuthor(author),
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  l10n.gymRoutineExerciseCount(r.exerciseCount),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                if ((r.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(r.notes!.trim(), style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 16),
                for (final ex in _exercises)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ex.exercise.exerciseName.isEmpty
                                ? '—'
                                : ex.exercise.exerciseName,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          for (final s in ex.sets)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                _targetLabel(ex.exercise.modality, s, l10n),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
