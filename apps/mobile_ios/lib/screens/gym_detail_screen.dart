import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../gym_prs.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_gym_store.dart';
import '../preferences.dart';
import '../widgets/gym_compose_sheet.dart';
import 'gym_screen.dart' show gymExerciseSuggestions;

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

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChange);
    _ensureLoaded();
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
                style: TextButton.styleFrom(foregroundColor: Colors.red),
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
    return parts.join(' × ');
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
    final notes = w.workout.notes?.trim();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (started != null)
          Text(
            formatDateMed(started.toLocal(), tag),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        const SizedBox(height: 16),
        for (final block in _blocks(w))
          _exerciseBlock(block, prByExercise, theme, l10n),
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
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final prs = prByExercise[normaliseExerciseName(block.name)] ?? const [];
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
          ),
        ),
      );

  static String _numStr(num v) {
    if (v is int) return v.toString();
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }
}
