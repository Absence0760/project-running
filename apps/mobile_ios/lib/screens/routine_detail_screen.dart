import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../gym_routine.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_gym_store.dart';
import '../local_routine_store.dart';
import '../preferences.dart';
import '../social_service.dart';
import '../widgets/gym_compose_sheet.dart';
import '../widgets/top_banner.dart';
import 'gym_screen.dart' show gymExerciseSuggestions;
import 'gym_session_screen.dart';

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

  /// Optional. When supplied (and the viewer authors this personal routine
  /// with at least one admin club), the detail grows a publish-as-template
  /// control mirroring web `/gym/routines/[id]`'s publish-row. Omitting it
  /// just hides the control — older callers don't need to wire it.
  final SocialService? social;

  /// Test seam — overrides the Supabase auth uid the publish gate compares
  /// against the routine's author_id (mirrors plan_detail_screen).
  final String? viewerIdOverride;

  const RoutineDetailScreen({
    super.key,
    required this.api,
    required this.store,
    required this.gymStore,
    required this.routineId,
    this.social,
    this.viewerIdOverride,
  });

  @override
  State<RoutineDetailScreen> createState() => _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends State<RoutineDetailScreen> {
  bool _isOnline = true;
  bool _isOwner = false;
  List<ClubView> _adminClubs = const [];
  String _publishingTo = '';
  bool _publishBusy = false;
  bool _publicBusy = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
    _computeOwner();
    _loadAdminClubs();
  }

  /// Whether the viewer authors this personal (non-club) routine — gates the
  /// public publish/unpublish toggle. Independent of [_loadAdminClubs] (which
  /// additionally needs a SocialService for the club publish-row).
  void _computeOwner() {
    final r = widget.store.byId(widget.routineId);
    if (r == null || r.clubId != null) return;
    String? uid = widget.viewerIdOverride;
    if (uid == null) {
      try {
        uid = Supabase.instance.client.auth.currentUser?.id;
      } catch (_) {
        // Supabase not initialised (e.g. a widget test without the override).
        return;
      }
    }
    if (uid != null && r.row['author_id'] == uid) {
      _isOwner = true;
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChange);
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  /// Mirrors web's publish gate: only the author of a personal (non-club)
  /// routine with at least one admin club sees the publish control, so fetch
  /// the viewer's admin clubs up front. Best-effort — a failure leaves the
  /// control hidden, never blocks the screen.
  Future<void> _loadAdminClubs() async {
    final social = widget.social;
    final r = widget.store.byId(widget.routineId);
    if (social == null || r == null || r.clubId != null) return;
    final uid = widget.viewerIdOverride ??
        Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || r.row['author_id'] != uid) return;
    try {
      final clubs = await social.fetchMyClubs();
      if (!mounted) return;
      setState(() {
        _adminClubs = clubs.where((c) => c.isAdmin).toList();
      });
    } catch (_) {
      // Leave the control hidden on failure.
    }
  }

  Future<void> _publishToClub(StoredRoutine r) async {
    final social = widget.social;
    if (social == null || _publishingTo.isEmpty || _publishBusy) return;
    final api = widget.api;
    if (api == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _publishBusy = true);
    try {
      await api.publishGymRoutineAsTemplate(
        routineId: r.id,
        clubId: _publishingTo,
      );
      if (!mounted) return;
      setState(() => _publishingTo = '');
      showTopBanner(context, l10n.gymRoutinePublishSuccess);
    } catch (_) {
      if (!mounted) return;
      showTopBanner(context, l10n.gymRoutinePublishFailed);
    } finally {
      if (mounted) setState(() => _publishBusy = false);
    }
  }

  Future<void> _togglePublic(StoredRoutine r) async {
    final api = widget.api;
    if (api == null || _publicBusy) return;
    final l10n = AppLocalizations.of(context);
    final next = !r.isPublicTemplate;
    setState(() => _publicBusy = true);
    try {
      await api.setGymRoutinePublic(routineId: r.id, isPublic: next);
      await widget.store.setPublicLocal(r.id, next);
      if (!mounted) return;
      showTopBanner(
        context,
        next
            ? l10n.gymRoutinePublishPublicSuccess
            : l10n.gymRoutineUnpublishPublicSuccess,
      );
    } catch (_) {
      if (!mounted) return;
      showTopBanner(context, l10n.gymRoutinePublishPublicFailed);
    } finally {
      if (mounted) setState(() => _publicBusy = false);
    }
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
          durationS: null,
          exerciseId: null,
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
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'routine_start_session',
                  onPressed: () => _startSession(r),
                  icon: const Icon(Icons.fitness_center),
                  label: Text(l10n.gymSessionStart),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'routine_prefill',
                  onPressed: () => _start(r),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.gymRoutineStart),
                ),
              ],
            ),
    );
  }

  Future<void> _startSession(StoredRoutine r) async {
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => GymSessionScreen(
          api: widget.api,
          routine: r,
          gymStore: widget.gymStore,
        ),
      ),
    );
    if (saved != null && mounted) Navigator.pop(context);
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
        if (r.clubId != null) ...[
          const SizedBox(height: 12),
          _clubTemplateBadge(theme, l10n),
        ] else if (_adminClubs.isNotEmpty) ...[
          const SizedBox(height: 12),
          _publishRow(r, theme, l10n),
        ],
        if (_isOwner && r.clubId == null) ...[
          const SizedBox(height: 12),
          _publicRow(r, theme, l10n),
        ],
        const SizedBox(height: 16),
        for (final ex in r.exercises) _exerciseCard(ex, theme, l10n),
      ],
    );
  }

  Widget _clubTemplateBadge(ThemeData theme, AppLocalizations l10n) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            l10n.gymRoutineClubTemplateBadge,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      );

  Widget _publishRow(
      StoredRoutine r, ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.gymRoutinePublishLabel,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _publishingTo.isEmpty ? null : _publishingTo,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                hint: Text(l10n.gymRoutinePublishPick),
                items: [
                  for (final c in _adminClubs)
                    DropdownMenuItem<String>(
                      value: c.row.id,
                      child: Text(c.row.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _publishBusy
                    ? null
                    : (v) => setState(() => _publishingTo = v ?? ''),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: (_publishingTo.isEmpty || _publishBusy)
                  ? null
                  : () => _publishToClub(r),
              child: Text(l10n.gymRoutinePublish),
            ),
          ],
        ),
      ],
    );
  }

  Widget _publicRow(StoredRoutine r, ThemeData theme, AppLocalizations l10n) {
    final isPublic = r.isPublicTemplate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.gymRoutinePublishPublicLabel,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 4),
        if (isPublic)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.public, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                l10n.gymRoutinePublicBadge,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          )
        else
          Text(
            l10n.gymRoutinePublishPublicHint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _publicBusy ? null : () => _togglePublic(r),
          child: Text(isPublic
              ? l10n.gymRoutineUnpublishPublic
              : l10n.gymRoutinePublishPublic),
        ),
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
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  ex.exerciseName.isEmpty ? '—' : ex.exerciseName,
                  style: theme.textTheme.titleSmall,
                ),
                if (ex.supersetGroup != null)
                  _chip(
                    Icons.repeat,
                    l10n.gymRoutineSupersetBadge(ex.supersetGroup!),
                    theme.colorScheme.primary,
                    theme.colorScheme.primaryContainer,
                    theme,
                  ),
                if (ex.progression != 'none')
                  _chip(
                    Icons.trending_up,
                    _schemeLabel(ex.progression, l10n),
                    theme.colorScheme.onSurfaceVariant,
                    theme.colorScheme.surfaceContainerHighest,
                    theme,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.gymRoutineSetType,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.gymRoutineTargetReps,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.gymRoutineRestLabel,
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
                      child: Text(_setTypeLabel(s.setType, l10n),
                          style: theme.textTheme.bodyMedium),
                    ),
                    Expanded(
                      child: Text(_targetLabel(ex.modality, s, l10n),
                          style: theme.textTheme.bodyMedium),
                    ),
                    Expanded(
                      child: Text(
                        s.restS == null
                            ? '—'
                            : l10n.gymDurationValue('${s.restS}'),
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

  Widget _chip(IconData icon, String label, Color fg, Color bg,
          ThemeData theme) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

  String _repLabel(StoredRoutineSet s) {
    final lo = s.targetRepsMin;
    if (lo == null) return '—';
    final hi = s.targetRepsMax;
    if (hi != null && hi != lo) return '$lo–$hi';
    return '$lo';
  }

  String _targetLabel(
      String modality, StoredRoutineSet s, AppLocalizations l10n) {
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

  String _setTypeLabel(String s, AppLocalizations l10n) {
    switch (s) {
      case 'warmup':
        return l10n.gymRoutineSetTypeWarmup;
      case 'working':
        return l10n.gymRoutineSetTypeWorking;
      case 'dropset':
        return l10n.gymRoutineSetTypeDropset;
      case 'amrap':
        return l10n.gymRoutineSetTypeAmrap;
      case 'failure':
        return l10n.gymRoutineSetTypeFailure;
      case 'backoff':
        return l10n.gymRoutineSetTypeBackoff;
    }
    return s;
  }

  String _schemeLabel(String s, AppLocalizations l10n) {
    switch (s) {
      case 'linear':
        return l10n.gymRoutineProgressionLinear;
      case 'double_progression':
        return l10n.gymRoutineProgressionDoubleProgression;
      case 'five_by_five':
        return l10n.gymRoutineProgressionFiveByFive;
      case 'percent_cycle':
        return l10n.gymRoutineProgressionPercentCycle;
      case 'rpe_autoreg':
        return l10n.gymRoutineProgressionRpeAutoreg;
    }
    return l10n.gymRoutineProgressionNone;
  }
}
