import 'package:flutter/material.dart';

import '../gym_prs.dart' show normaliseExerciseName;
import '../l10n/gen/app_localizations.dart';
import '../local_routine_store.dart';
import '../preferences.dart';
import 'full_screen_form.dart';

/// Open the routine builder as a fullscreen dialog. Pass [seedExercises] /
/// [seedTitle] to prefill it (e.g. the output of `routineFromWorkout` for a
/// "Save as routine" promotion). Resolves the created routine's id when saved,
/// null when the user backed out.
///
/// Flutter twin of web `RoutineEditor.svelte` (+ the `gym_compose_sheet.dart`
/// idiom): a free-text exercise name with history autocomplete plus inline
/// planned sets (target reps / weight). Writes through [LocalRoutineStore] so
/// building a routine works offline. P1 is build / save only — no execution
/// loop, no supersets, no progression.
Future<String?> showRoutineBuilderSheet({
  required BuildContext context,
  required LocalRoutineStore store,
  List<RoutineSeedExercise>? seedExercises,
  String seedTitle = '',
  List<String> suggestions = const [],
}) {
  final l10n = AppLocalizations.of(context);
  return showFullScreenForm<String>(
    context,
    title: l10n.gymRoutineEditorNewTitle,
    builder: (ctx) => RoutineBuilderSheet(
      store: store,
      seedExercises: seedExercises,
      seedTitle: seedTitle,
      suggestions: suggestions,
    ),
  );
}

/// One prefilled exercise block for the builder. Weight is kept as canonical
/// kg; the builder formats it into the display unit for the entry field. Reps
/// / RPE arrive as display strings (mirrors web `PrefillExercise`).
class RoutineSeedExercise {
  RoutineSeedExercise({required this.name, required this.sets});
  final String name;
  final List<RoutineSeedSet> sets;
}

class RoutineSeedSet {
  RoutineSeedSet({this.reps = '', this.weightKg, this.rpe = ''});
  final String reps;
  final double? weightKg;
  final String rpe;
}

class RoutineBuilderSheet extends StatefulWidget {
  final LocalRoutineStore store;
  final List<RoutineSeedExercise>? seedExercises;
  final String seedTitle;
  final List<String> suggestions;
  const RoutineBuilderSheet({
    super.key,
    required this.store,
    this.seedExercises,
    this.seedTitle = '',
    this.suggestions = const [],
  });

  @override
  State<RoutineBuilderSheet> createState() => _RoutineBuilderSheetState();
}

class _RoutineBuilderSheetState extends State<RoutineBuilderSheet> {
  late final TextEditingController _titleCtl;
  late final TextEditingController _notesCtl;
  late List<_EditExercise> _exercises;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtl = TextEditingController(text: widget.seedTitle);
    _notesCtl = TextEditingController();
    _exercises = _initExercises(widget.seedExercises);
  }

  List<_EditExercise> _initExercises(List<RoutineSeedExercise>? src) {
    if (src == null || src.isEmpty) return [_EditExercise()];
    return [
      for (final ex in src)
        _EditExercise(
          name: ex.name,
          sets: ex.sets.isEmpty
              ? [_EditSet()]
              : [
                  for (final s in ex.sets)
                    _EditSet(
                      reps: s.reps,
                      // Canonical kg -> display unit for the entry field.
                      weight: s.weightKg == null
                          ? ''
                          : _displayStr(
                              WeightFormat.toDisplay(s.weightKg!, activeWeightUnit)),
                    ),
                ],
        ),
    ];
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _notesCtl.dispose();
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

  List<StoredRoutineExercise> _buildExercises() {
    final out = <StoredRoutineExercise>[];
    for (final ex in _exercises) {
      final name = ex.name.text.trim();
      if (name.isEmpty) continue;
      out.add(StoredRoutineExercise(
        exerciseName: name,
        exerciseKey: normaliseExerciseName(name),
        sets: [
          for (final s in ex.sets)
            StoredRoutineSet(
              targetRepsMin: int.tryParse(s.reps.text.trim()),
              targetRepsMax: null,
              // Entry is in the display unit; store canonical kg.
              targetWeightKg:
                  WeightFormat.parseToKg(s.weight.text, activeWeightUnit),
              targetRpe: null,
            ),
        ],
      ));
    }
    return out;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final title = _titleCtl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = l10n.gymRoutineEditorNeedTitle);
      return;
    }
    final exercises = _buildExercises();
    if (exercises.isEmpty) {
      setState(() => _error = l10n.gymRoutineEditorNeedExercise);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final notes = _notesCtl.text.trim();
      final stored = await widget.store.createLocal(
        title: title,
        notes: notes.isEmpty ? null : notes,
        exercises: exercises,
      );
      if (mounted) Navigator.pop(context, stored.id);
    } catch (e) {
      debugPrint('routine_builder_sheet: save failed: $e');
      if (mounted) {
        setState(() {
          _error = l10n.gymRoutineSaveFailed;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return FullScreenFormBody(
      children: [
        FormSectionLabel(l10n.gymRoutineEditorTitleLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _titleCtl,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: const OutlineInputBorder(),
            hintText: l10n.gymRoutineEditorTitlePlaceholder,
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
        const SizedBox(height: 12),
        FormSectionLabel(l10n.gymRoutineEditorNotesLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtl,
          maxLines: 2,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(),
          ),
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
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: Text(l10n.gymRoutineEditorCancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.gymRoutineEditorSave),
            ),
          ],
        ),
      ],
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
            Row(
              children: [
                const SizedBox(width: 44),
                Expanded(
                  child: Text(
                    l10n.gymRoutineTargetReps,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.gymRoutineTargetWeight(
                        WeightFormat.label(activeWeightUnit)),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                const SizedBox(width: 40),
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
                        l10n.gymRoutineTargetReps,
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

  /// Render a display-unit weight into an input string, dropping a gratuitous
  /// `.0` (round to 1 decimal so an lbs conversion doesn't show a long tail).
  static String _displayStr(double v) {
    final r = (v * 10).round() / 10;
    if (r == r.roundToDouble()) return r.toInt().toString();
    return r.toString();
  }
}

class _EditSet {
  final TextEditingController reps;
  final TextEditingController weight;
  _EditSet({String reps = '', String weight = ''})
      : reps = TextEditingController(text: reps),
        weight = TextEditingController(text: weight);
  void dispose() {
    reps.dispose();
    weight.dispose();
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
