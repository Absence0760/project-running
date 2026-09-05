import 'package:flutter/material.dart';

import '../gym_prs.dart' show normaliseExerciseName;
import '../l10n/gen/app_localizations.dart';
import '../local_routine_store.dart';
import '../preferences.dart';
import '../routine_editor_build.dart';
import '../typed_decimal.dart';
import 'full_screen_form.dart';

/// Open the routine builder as a fullscreen dialog. Pass [seedExercises] /
/// [seedTitle] to prefill it (e.g. the output of `routineFromWorkout` for a
/// "Save as routine" promotion). Resolves the created routine's id when saved,
/// null when the user backed out.
///
/// Flutter twin of web `RoutineEditor.svelte`: a free-text exercise name with
/// history autocomplete, a per-exercise modality picker that swaps the target
/// field, a superset toggle that brackets adjacent exercises into a group, a
/// progression scheme + params selector, and per-set set-type + rest. Writes
/// through [LocalRoutineStore] so building a routine works offline.
Future<String?> showRoutineBuilderSheet({
  required BuildContext context,
  required LocalRoutineStore store,
  List<RoutineSeedExercise>? seedExercises,
  String seedTitle = '',
  List<String> suggestions = const [],
}) {
  final l10n = AppLocalizations.of(context);
  final formKey = GlobalKey<_RoutineBuilderSheetState>();
  return showFullScreenForm<String>(
    context,
    title: l10n.gymRoutineEditorNewTitle,
    isDirty: () => formKey.currentState?.isDirty ?? false,
    builder: (ctx) => RoutineBuilderSheet(
      key: formKey,
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

const _setTypes = <String>[
  'warmup',
  'working',
  'dropset',
  'amrap',
  'failure',
  'backoff',
];
const _modalities = <String>[
  'weight_reps',
  'time',
  'distance',
  'bodyweight_reps',
];
const _schemes = <String>[
  'none',
  'linear',
  'double_progression',
  'five_by_five',
  'percent_cycle',
  'rpe_autoreg',
];

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
  // Per-field validation state (sign_up_screen idiom): the title error
  // renders on the title field, the need-exercise flag on the
  // (necessarily all-empty) exercise-name fields. _error stays for save
  // FAILURES only.
  String? _titleError;
  bool _needExercise = false;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtl = TextEditingController(text: widget.seedTitle);
    _notesCtl = TextEditingController();
    _exercises = _initExercises(widget.seedExercises);
    _initialSnapshot = _snapshot();
  }

  late final String _initialSnapshot;

  // Serialises every raw input so the guard fires on anything typed, and a
  // seeded baseline reads clean until actually touched.
  String _snapshot() {
    final b = StringBuffer()
      ..write(_titleCtl.text)
      ..write('\u0000')
      ..write(_notesCtl.text);
    for (final ex in _exercises) {
      b
        ..write('\u0001')
        ..write(ex.name.text)
        ..write('\u0000')
        ..write(ex.modality)
        ..write('\u0000')
        ..write(ex.progression)
        ..write('\u0000')
        ..write(ex.supersetWithNext)
        ..write('\u0000')
        ..write(ex.increment.text)
        ..write('\u0000')
        ..write(ex.percent.text)
        ..write('\u0000')
        ..write(ex.oneRm.text)
        ..write('\u0000')
        ..write(ex.targetRpe.text);
      for (final s in ex.sets) {
        b
          ..write('\u0002')
          ..write(s.setType)
          ..write('\u0000')
          ..write(s.reps.text)
          ..write('\u0000')
          ..write(s.repsMax.text)
          ..write('\u0000')
          ..write(s.weight.text)
          ..write('\u0000')
          ..write(s.rest.text)
          ..write('\u0000')
          ..write(s.duration.text)
          ..write('\u0000')
          ..write(s.distance.text)
          ..write('\u0000')
          ..write(s.rpe.text);
      }
    }
    return b.toString();
  }

  bool get isDirty => _snapshot() != _initialSnapshot;

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

  Map<String, dynamic> _progressionParams(_EditExercise ex) {
    final params = <String, dynamic>{};
    final inc = WeightFormat.parseToKg(ex.increment.text, activeWeightUnit);
    if (inc != null) params['incrementKg'] = inc;
    if (ex.progression == 'percent_cycle') {
      final pct = parseTypedDecimal(ex.percent.text);
      final oneRm = WeightFormat.parseToKg(ex.oneRm.text, activeWeightUnit);
      if (pct != null) params['percent'] = pct / 100;
      if (oneRm != null) params['oneRmKg'] = oneRm;
    }
    if (ex.progression == 'rpe_autoreg') {
      final rpe = parseTypedDecimal(ex.targetRpe.text);
      if (rpe != null) params['targetRpe'] = rpe;
    }
    return params;
  }

  List<StoredRoutineExercise> _buildExercises() {
    // Drop blank-named exercises first so superset linking only sees real rows
    // (a blank row between two flagged blocks must not bridge them).
    final named = _exercises.where((e) => e.name.text.trim().isNotEmpty).toList();
    if (named.isEmpty) return const [];
    final groups = assignSupersetGroups([for (final e in named) e.supersetWithNext]);

    final out = <StoredRoutineExercise>[];
    for (var i = 0; i < named.length; i++) {
      final ex = named[i];
      final name = ex.name.text.trim();
      final isRepModality =
          ex.modality == 'weight_reps' || ex.modality == 'bodyweight_reps';
      out.add(StoredRoutineExercise(
        exerciseName: name,
        exerciseKey: normaliseExerciseName(name),
        supersetGroup: groups[i].supersetGroup,
        supersetOrder: groups[i].supersetOrder,
        modality: ex.modality,
        progression: ex.progression,
        progressionParams: _progressionParams(ex),
        sets: [
          for (final s in ex.sets)
            StoredRoutineSet(
              setType: s.setType,
              targetRepsMin: isRepModality ? int.tryParse(s.reps.text.trim()) : null,
              targetRepsMax:
                  isRepModality ? int.tryParse(s.repsMax.text.trim()) : null,
              // Entry is in the display unit; store canonical kg.
              targetWeightKg: ex.modality == 'weight_reps'
                  ? WeightFormat.parseToKg(s.weight.text, activeWeightUnit)
                  : null,
              targetRpe: parseTypedDecimal(s.rpe.text),
              restS: int.tryParse(s.rest.text.trim()),
              targetDurationS:
                  ex.modality == 'time' ? int.tryParse(s.duration.text.trim()) : null,
              targetDistanceM: ex.modality == 'distance'
                  ? parseTypedDecimal(s.distance.text)
                  : null,
            ),
        ],
      ));
    }
    return out;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final title = _titleCtl.text.trim();
    final exercises = _buildExercises();
    // Validate both in one pass so each invalid field is flagged inline
    // at once (sign_up_screen idiom).
    setState(() {
      _titleError = title.isEmpty ? l10n.gymRoutineEditorNeedTitle : null;
      _needExercise = exercises.isEmpty;
    });
    if (title.isEmpty || exercises.isEmpty) return;
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
            hintText: l10n.gymRoutineEditorTitlePlaceholder,
            errorText: _titleError,
          ),
          onChanged: (_) {
            if (_titleError != null) setState(() => _titleError = null);
          },
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
        Semantics(
          label: l10n.gymRoutineEditorNotesLabel,
          child: TextField(
            controller: _notesCtl,
            maxLines: 2,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
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
              onPressed: _saving ? null : () => Navigator.maybePop(context),
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

  String _modalityLabel(String m, AppLocalizations l10n) {
    switch (m) {
      case 'weight_reps':
        return l10n.gymRoutineModalityWeightReps;
      case 'time':
        return l10n.gymRoutineModalityTime;
      case 'distance':
        return l10n.gymRoutineModalityDistance;
      case 'bodyweight_reps':
        return l10n.gymRoutineModalityBodyweightReps;
    }
    return m;
  }

  String _schemeLabel(String s, AppLocalizations l10n) {
    switch (s) {
      case 'none':
        return l10n.gymRoutineProgressionNone;
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
    return s;
  }

  Widget _exerciseCard(
      _EditExercise ex, int i, ThemeData theme, AppLocalizations l10n) {
    final isRep =
        ex.modality == 'weight_reps' || ex.modality == 'bodyweight_reps';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
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
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DropdownButtonFormField<String>(
                initialValue: ex.modality,
                isDense: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: l10n.gymRoutineModality,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  for (final m in _modalities)
                    DropdownMenuItem(value: m, child: Text(_modalityLabel(m, l10n))),
                ],
                onChanged: (v) =>
                    setState(() => ex.modality = v ?? ex.modality),
              ),
            ),
            const SizedBox(height: 8),
            for (var si = 0; si < ex.sets.length; si++)
              _setRow(ex, ex.sets[si], si, isRep, theme, l10n),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _addSet(ex),
                child: Text(l10n.gymEditorAddSet),
              ),
            ),
            if (i != _exercises.length - 1)
              SwitchListTile(
                value: ex.supersetWithNext,
                onChanged: (v) => setState(() => ex.supersetWithNext = v),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.gymRoutineSupersetToggle,
                    style: theme.textTheme.bodySmall),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(l10n.gymRoutineAdvanced, style: theme.textTheme.bodySmall),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [_advancedBody(ex, theme, l10n)],
            ),
          ],
        ),
      ),
    );
  }

  Widget _setRow(_EditExercise ex, _EditSet s, int si, bool isRep,
      ThemeData theme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: DropdownButtonFormField<String>(
              initialValue: s.setType,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              ),
              items: [
                for (final t in _setTypes)
                  DropdownMenuItem(
                    value: t,
                    child: Text(_setTypeLabel(t, l10n),
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => s.setType = v ?? s.setType),
            ),
          ),
          const SizedBox(width: 6),
          if (isRep) ...[
            Expanded(
              child: _numField(s.reps, l10n.gymRoutineTargetReps, false),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _numField(s.repsMax, l10n.gymRoutineTargetRepsMax, false),
            ),
          ] else if (ex.modality == 'time')
            Expanded(
              child: _numField(s.duration, l10n.gymRoutineTargetDuration, false),
            )
          else
            Expanded(
              child: _numField(s.distance, l10n.gymRoutineTargetDistance, true),
            ),
          if (ex.modality == 'weight_reps') ...[
            const SizedBox(width: 4),
            Expanded(
              child: _numField(
                  s.weight, WeightFormat.label(activeWeightUnit), true),
            ),
          ],
          const SizedBox(width: 4),
          SizedBox(
            width: 60,
            child: _numField(s.rest, l10n.gymRoutineRestLabel, false),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 56,
            child: _numField(s.rpe, l10n.gymRpe, true),
          ),
          IconButton(
            tooltip: l10n.gymEditorRemoveSet,
            icon: const Icon(Icons.close, size: 18),
            color: theme.colorScheme.outline,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => _removeSet(ex, si),
          ),
        ],
      ),
    );
  }

  Widget _advancedBody(
      _EditExercise ex, ThemeData theme, AppLocalizations l10n) {
    final unit = WeightFormat.label(activeWeightUnit);
    final scheme = ex.progression;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: scheme,
          isDense: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: l10n.gymRoutineProgression,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            for (final s in _schemes)
              DropdownMenuItem(value: s, child: Text(_schemeLabel(s, l10n))),
          ],
          onChanged: (v) => setState(() => ex.progression = v ?? ex.progression),
        ),
        if (scheme == 'linear' ||
            scheme == 'double_progression' ||
            scheme == 'five_by_five' ||
            scheme == 'rpe_autoreg') ...[
          const SizedBox(height: 8),
          _numField(
              ex.increment, l10n.gymRoutineProgressionIncrementLabel(unit), true),
        ],
        if (scheme == 'percent_cycle') ...[
          const SizedBox(height: 8),
          _numField(ex.percent, l10n.gymRoutineProgressionPercentLabel, true),
          const SizedBox(height: 8),
          _numField(ex.oneRm, l10n.gymRoutineProgressionOneRmLabel(unit), true),
        ],
        if (scheme == 'rpe_autoreg') ...[
          const SizedBox(height: 8),
          _numField(
              ex.targetRpe, l10n.gymRoutineProgressionTargetRpeLabel, true),
        ],
      ],
    );
  }

  Widget _nameField(_EditExercise ex, AppLocalizations l10n) {
    InputDecoration deco() => InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          hintText: l10n.gymEditorExercisePlaceholder,
          errorText: _needExercise && ex.name.text.trim().isEmpty
              ? l10n.gymRoutineEditorNeedExercise
              : null,
        );
    void clearNeedExercise(String _) {
      if (_needExercise) setState(() => _needExercise = false);
    }

    if (widget.suggestions.isEmpty) {
      return Semantics(
        label: l10n.gymEditorExercisePlaceholder,
        child: TextField(
          controller: ex.name,
          focusNode: ex.nameFocus,
          textCapitalization: TextCapitalization.words,
          decoration: deco(),
          onChanged: clearNeedExercise,
        ),
      );
    }
    return RawAutocomplete<String>(
      textEditingController: ex.name,
      focusNode: ex.nameFocus,
      optionsBuilder: (value) {
        final q = normaliseExerciseName(value.text);
        if (q.isEmpty) return const Iterable<String>.empty();
        return widget.suggestions
            .where((s) => normaliseExerciseName(s).contains(q))
            .take(6);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => Semantics(
        label: l10n.gymEditorExercisePlaceholder,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: deco(),
          onChanged: clearNeedExercise,
          onSubmitted: (_) => onSubmit(),
        ),
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

  Widget _numField(
      TextEditingController controller, String hint, bool decimal) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
  String setType;
  final TextEditingController reps;
  final TextEditingController repsMax;
  final TextEditingController weight;
  final TextEditingController rest;
  final TextEditingController duration;
  final TextEditingController distance;
  final TextEditingController rpe;
  _EditSet({String reps = '', String weight = ''})
      : setType = 'working',
        reps = TextEditingController(text: reps),
        repsMax = TextEditingController(),
        weight = TextEditingController(text: weight),
        rest = TextEditingController(),
        duration = TextEditingController(),
        distance = TextEditingController(),
        rpe = TextEditingController();
  void dispose() {
    reps.dispose();
    repsMax.dispose();
    weight.dispose();
    rest.dispose();
    duration.dispose();
    distance.dispose();
    rpe.dispose();
  }
}

class _EditExercise {
  final TextEditingController name;
  final FocusNode nameFocus;
  final List<_EditSet> sets;
  String modality;
  String progression;
  bool supersetWithNext;
  final TextEditingController increment;
  final TextEditingController percent;
  final TextEditingController oneRm;
  final TextEditingController targetRpe;
  _EditExercise({String name = '', List<_EditSet>? sets})
      : name = TextEditingController(text: name),
        nameFocus = FocusNode(),
        sets = sets ?? [_EditSet()],
        modality = 'weight_reps',
        progression = 'none',
        supersetWithNext = false,
        increment = TextEditingController(),
        percent = TextEditingController(),
        oneRm = TextEditingController(),
        targetRpe = TextEditingController();
  void dispose() {
    name.dispose();
    nameFocus.dispose();
    increment.dispose();
    percent.dispose();
    oneRm.dispose();
    targetRpe.dispose();
    for (final s in sets) {
      s.dispose();
    }
  }
}
