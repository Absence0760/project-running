import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../local_gym_store.dart';
import '../preferences.dart';

/// Open the gym-workout composer as a fullscreen dialog. Pass [existing] to
/// edit a stored workout in place; omit for a new one. Resolves `true` when
/// a workout was created or updated (so the caller can kick a sync), null
/// when the user backed out.
///
/// Flutter twin of web `GymEditor.svelte` — a free-text exercise name with
/// history autocomplete plus inline sets (reps / weight / RPE). Writes
/// through [LocalGymStore] so logging a lift works offline.
Future<bool?> showGymComposeSheet({
  required BuildContext context,
  required LocalGymStore store,
  StoredGymWorkout? existing,
  List<String> suggestions = const [],
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          title: Text(existing == null
              ? AppLocalizations.of(ctx).gymEditorNewTitle
              : AppLocalizations.of(ctx).gymEditorEditTitle),
        ),
        body: SafeArea(
          child: GymComposeSheet(
            store: store,
            existing: existing,
            suggestions: suggestions,
          ),
        ),
      ),
    ),
  );
}

class GymComposeSheet extends StatefulWidget {
  final LocalGymStore store;
  final StoredGymWorkout? existing;
  final List<String> suggestions;
  const GymComposeSheet({
    super.key,
    required this.store,
    this.existing,
    this.suggestions = const [],
  });

  @override
  State<GymComposeSheet> createState() => _GymComposeSheetState();
}

class _GymComposeSheetState extends State<GymComposeSheet> {
  late final TextEditingController _titleCtl;
  late bool _isPublic;
  late List<_EditExercise> _exercises;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleCtl =
        TextEditingController(text: existing?.workout.title ?? '');
    _isPublic = existing?.workout.isPublic ?? false;
    _exercises = _initExercises(existing);
  }

  /// Rebuild exercise blocks from a stored workout. Sets arrive in
  /// `set_index` order grouped by exercise (that's how the composer writes
  /// them), so a consecutive run of the same `exercise_name` rebuilds a
  /// block. An empty / missing workout seeds one blank exercise + set.
  List<_EditExercise> _initExercises(StoredGymWorkout? src) {
    final sets = src?.sets ?? const [];
    if (sets.isEmpty) {
      return [_EditExercise()];
    }
    final blocks = <_EditExercise>[];
    for (final s in sets) {
      final name = (s['exercise_name'] as String?) ?? '';
      // Stored canonical kg -> display unit for the entry field. Round to
      // 1 decimal so an lbs conversion doesn't render a long float tail.
      final kg = (s['weight_kg'] as num?)?.toDouble();
      final display = kg == null
          ? null
          : (WeightFormat.toDisplay(kg, activeWeightUnit) * 10).round() / 10;
      final row = _EditSet(
        reps: _numStr(s['reps'] as num?),
        weight: _numStr(display),
        rpe: _numStr(s['rpe'] as num?),
      );
      final last = blocks.isEmpty ? null : blocks.last;
      if (last != null && last.name.text == name) {
        last.sets.add(row);
      } else {
        blocks.add(_EditExercise(name: name, sets: [row]));
      }
    }
    return blocks;
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    for (final ex in _exercises) {
      ex.dispose();
    }
    super.dispose();
  }

  void _addExercise() => setState(() => _exercises.add(_EditExercise()));

  void _removeExercise(int i) {
    setState(() {
      _exercises.removeAt(i).dispose();
      if (_exercises.isEmpty) _exercises.add(_EditExercise());
    });
  }

  void _addSet(_EditExercise ex) => setState(() => ex.sets.add(_EditSet()));

  void _removeSet(_EditExercise ex, int si) {
    setState(() {
      ex.sets.removeAt(si).dispose();
      if (ex.sets.isEmpty) ex.sets.add(_EditSet());
    });
  }

  List<GymSetInput> _buildSets() {
    final out = <GymSetInput>[];
    for (final ex in _exercises) {
      final name = ex.name.text.trim();
      if (name.isEmpty) continue;
      for (final s in ex.sets) {
        out.add((
          exerciseName: name,
          reps: int.tryParse(s.reps.text.trim()),
          // Entry is in the user's display unit; store canonical kg.
          weightKg: WeightFormat.parseToKg(s.weight.text, activeWeightUnit),
          rpe: double.tryParse(s.rpe.text.trim()),
        ));
      }
    }
    return out;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final sets = _buildSets();
    if (sets.isEmpty) {
      setState(() => _error = l10n.gymEditorNeedExercise);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final title = _titleCtl.text.trim();
    try {
      final existing = widget.existing;
      if (existing != null) {
        await widget.store.updateLocal(
          existing.id,
          title: title,
          isPublic: _isPublic,
          sets: sets,
        );
      } else {
        await widget.store.createLocal(
          title: title.isEmpty ? null : title,
          startedAt: DateTime.now(),
          isPublic: _isPublic,
          sets: sets,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('gym_compose_sheet: save failed: $e');
      if (mounted) {
        setState(() {
          _error = l10n.gymSaveFailed;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final mq = MediaQuery.of(context);
    final bottomInset =
        mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.viewPadding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionLabel(theme, l10n.gymEditorTitleLabel),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: const OutlineInputBorder(),
                hintText: l10n.gymEditorTitlePlaceholder,
              ),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < _exercises.length; i++)
              _exerciseCard(_exercises[i], i, theme, l10n),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addExercise,
                icon: const Icon(Icons.add),
                label: Text(l10n.gymEditorAddExercise),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              title: Text(l10n.gymEditorShare),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context),
                  child: Text(l10n.gymEditorCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(l10n.gymEditorSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _exerciseCard(
      _EditExercise ex, int i, ThemeData theme, AppLocalizations l10n) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _nameField(ex, l10n)),
                IconButton(
                  tooltip: l10n.gymEditorRemoveExercise,
                  icon: const Icon(Icons.delete_outline),
                  color: theme.colorScheme.outline,
                  onPressed: () => _removeExercise(i),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (var si = 0; si < ex.sets.length; si++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        l10n.gymSetN(si + 1),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                    Expanded(
                      child: _setNumberField(
                        ex.sets[si].reps,
                        l10n.gymReps,
                        const TextInputType.numberWithOptions(decimal: false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _setNumberField(
                        ex.sets[si].weight,
                        WeightFormat.label(activeWeightUnit),
                        const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _setNumberField(
                        ex.sets[si].rpe,
                        l10n.gymRpe,
                        const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.gymEditorRemoveSet,
                      icon: const Icon(Icons.close, size: 18),
                      color: theme.colorScheme.outline,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeSet(ex, si),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _addSet(ex),
                child: Text(l10n.gymEditorAddSet),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nameField(_EditExercise ex, AppLocalizations l10n) {
    InputDecoration deco() => InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: const OutlineInputBorder(),
          hintText: l10n.gymEditorExercisePlaceholder,
        );
    if (widget.suggestions.isEmpty) {
      return TextField(
        controller: ex.name,
        focusNode: ex.nameFocus,
        textCapitalization: TextCapitalization.words,
        decoration: deco(),
      );
    }
    return RawAutocomplete<String>(
      textEditingController: ex.name,
      focusNode: ex.nameFocus,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return widget.suggestions
            .where((s) => s.toLowerCase().contains(q))
            .take(6);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
        controller: controller,
        focusNode: focusNode,
        textCapitalization: TextCapitalization.words,
        decoration: deco(),
        onSubmitted: (_) => onSubmit(),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(
                    dense: true,
                    title: Text(o),
                    onTap: () => onSelected(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _setNumberField(
      TextEditingController controller, String hint, TextInputType keyboard) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: const OutlineInputBorder(),
        hintText: hint,
      ),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  /// Render a stored numeric back into an input string: integral values drop
  /// the `.0` (100, not 100.0) so a round-trip through the composer doesn't
  /// gratuitously add decimals.
  static String _numStr(num? v) {
    if (v == null) return '';
    if (v is int) return v.toString();
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }
}

class _EditSet {
  final TextEditingController reps;
  final TextEditingController weight;
  final TextEditingController rpe;
  _EditSet({String reps = '', String weight = '', String rpe = ''})
      : reps = TextEditingController(text: reps),
        weight = TextEditingController(text: weight),
        rpe = TextEditingController(text: rpe);
  void dispose() {
    reps.dispose();
    weight.dispose();
    rpe.dispose();
  }
}

class _EditExercise {
  final TextEditingController name;
  final FocusNode nameFocus;
  final List<_EditSet> sets;
  _EditExercise({String name = '', List<_EditSet>? sets})
      : name = TextEditingController(text: name),
        nameFocus = FocusNode(),
        sets = sets ?? [_EditSet()];
  void dispose() {
    name.dispose();
    nameFocus.dispose();
    for (final s in sets) {
      s.dispose();
    }
  }
}
