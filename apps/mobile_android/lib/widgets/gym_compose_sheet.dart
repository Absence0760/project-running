import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../gym_prs.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_gym_store.dart';
import '../preferences.dart';
import 'exercise_catalogue_picker.dart';
import 'full_screen_form.dart';

/// One exercise-catalogue entry surfaced to the composer (migration
/// 20270222_001): the display name plus the catalogue row id that gets bound to
/// a logged set when the typed name matches by normalised key. [category] is
/// the muscle-group bucket the browse/picker groups + filters by; [authorId]
/// is null for a seeded global, set for an owner custom.
typedef GymCatalogueEntry = ({
  String name,
  String id,
  String category,
  String? authorId,
});

/// The logged-set role vocabulary (DB CHECK union, migration 20270224_001),
/// shared verbatim with the routine builder.
const _gymSetTypes = <String>[
  'warmup',
  'working',
  'dropset',
  'amrap',
  'failure',
  'backoff',
];

String _gymSetTypeLabel(String s, AppLocalizations l10n) {
  switch (s) {
    case 'warmup':
      return l10n.gymRoutineSetTypeWarmup;
    case 'dropset':
      return l10n.gymRoutineSetTypeDropset;
    case 'amrap':
      return l10n.gymRoutineSetTypeAmrap;
    case 'failure':
      return l10n.gymRoutineSetTypeFailure;
    case 'backoff':
      return l10n.gymRoutineSetTypeBackoff;
    case 'working':
    default:
      return l10n.gymRoutineSetTypeWorking;
  }
}

/// Open the gym-workout composer as a fullscreen dialog. Pass [existing] to
/// edit a stored workout in place; omit for a new one. Pass [seedSets] /
/// [seedTitle] to prefill a NEW log (still the create path) — the "Start
/// routine" / "Repeat last" entry seeds the composer with a routine's planned
/// targets (or a prior session's sets) as the new session's actuals, mirroring
/// web's `prefillFromRoutine` → GymEditor seed. Resolves `true` when a workout
/// was created or updated (so the caller can kick a sync), null when the user
/// backed out.
///
/// Flutter twin of web `GymEditor.svelte` — a free-text exercise name with
/// history autocomplete plus inline sets (reps / weight / RPE). Writes
/// through [LocalGymStore] so logging a lift works offline. Presentation
/// goes through [showFullScreenForm], the shared create/edit-entity wrapper.
Future<bool?> showGymComposeSheet({
  required BuildContext context,
  required LocalGymStore store,
  StoredGymWorkout? existing,
  List<GymSetInput>? seedSets,
  String? seedTitle,
  List<String> suggestions = const [],
  List<GymCatalogueEntry> catalogue = const [],
  String? prefillTitle,
  ApiClient? api,
}) {
  final l10n = AppLocalizations.of(context);
  return showFullScreenForm<bool>(
    context,
    title: existing == null ? l10n.gymEditorNewTitle : l10n.gymEditorEditTitle,
    builder: (ctx) => GymComposeSheet(
      store: store,
      existing: existing,
      seedSets: seedSets,
      seedTitle: seedTitle,
      suggestions: suggestions,
      catalogue: catalogue,
      prefillTitle: prefillTitle,
      api: api,
    ),
  );
}

class GymComposeSheet extends StatefulWidget {
  final LocalGymStore store;
  final StoredGymWorkout? existing;

  /// Prefill a NEW log with these sets (the create path, not an edit). Ignored
  /// when [existing] is non-null.
  final List<GymSetInput>? seedSets;
  final String? seedTitle;
  final List<String> suggestions;

  /// Exercise catalogue (seeded globals + the user's customs, migration
  /// 20270222_001). Names are merged into the autocomplete; a typed name that
  /// matches a catalogue entry by normalised key binds its id onto the set.
  final List<GymCatalogueEntry> catalogue;

  /// Seed for a NEW workout (the class -> gym seam). Pre-fills the title; sets
  /// stay empty for the user to fill. Ignored when [existing] is set.
  final String? prefillTitle;

  /// Optional API client — present online, null offline / signed-out. Powers
  /// the catalogue browse/picker's create-custom path; the picker hides the
  /// create affordance when it's null.
  final ApiClient? api;
  const GymComposeSheet({
    super.key,
    required this.store,
    this.existing,
    this.seedSets,
    this.seedTitle,
    this.suggestions = const [],
    this.catalogue = const [],
    this.prefillTitle,
    this.api,
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

  /// Local, growable catalogue copy. Seeded from the prop; a custom created
  /// from the picker is appended so it binds + autocompletes immediately,
  /// without waiting for the host to reload from the server.
  late List<GymCatalogueEntry> _catalogue;

  /// normalised name -> catalogue id, for binding a typed name at save time.
  Map<String, String> get _catalogueByKey => {
        for (final e in _catalogue) normaliseExerciseName(e.name): e.id,
      };

  /// History suggestions ∪ catalogue names, de-duplicated by normalised key.
  List<String> get _datalistNames {
    final seenKeys = <String>{};
    return [
      for (final n in [
        ...widget.suggestions,
        ..._catalogue.map((e) => e.name),
      ])
        if (normaliseExerciseName(n).isNotEmpty &&
            seenKeys.add(normaliseExerciseName(n)))
          n,
    ];
  }

  @override
  void initState() {
    super.initState();
    _catalogue = [...widget.catalogue];
    final existing = widget.existing;
    _titleCtl = TextEditingController(
        text:
            existing?.workout.title ?? widget.seedTitle ?? widget.prefillTitle ?? '');
    _isPublic = existing?.workout.isPublic ?? false;
    // Edit path reads the stored workout's sets; the new-log seed path
    // (Start routine / Repeat last) reads the prefilled seed sets.
    _exercises = _initExercises(existing?.sets ??
        (widget.seedSets == null
            ? null
            : [
                for (final s in widget.seedSets!)
                  <String, dynamic>{
                    'exercise_name': s.exerciseName,
                    'reps': s.reps,
                    'weight_kg': s.weightKg,
                    'rpe': s.rpe,
                    'set_type': s.setType,
                  },
              ]));
  }

  /// Rebuild exercise blocks from a list of stored set maps. Sets arrive in
  /// order grouped by exercise (that's how the composer writes them), so a
  /// consecutive run of the same `exercise_name` rebuilds a block. An empty /
  /// missing list seeds one blank exercise + set.
  List<_EditExercise> _initExercises(List<Map<String, dynamic>>? src) {
    final sets = src ?? const <Map<String, dynamic>>[];
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
        duration: _numStr(s['duration_s'] as num?),
        setType: (s['set_type'] as String?) ?? 'working',
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

  /// Open the catalogue browse/picker for [ex]. A pick fills the block's name
  /// (the normalised key binds its exercise_id at save); a created custom is
  /// merged into the local catalogue so it binds without a reload.
  Future<void> _openPicker(_EditExercise ex) async {
    final picked = await Navigator.of(context).push<GymCatalogueEntry>(
      MaterialPageRoute<GymCatalogueEntry>(
        builder: (_) => ExerciseCataloguePickerScreen(
          catalogue: _catalogue,
          api: widget.api,
          onCreated: (created) {
            if (!_catalogue.any((e) => e.id == created.id)) {
              _catalogue = [..._catalogue, created];
            }
          },
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      ex.name.text = picked.name;
      if (_error != null) _error = null;
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
      // Bind to a catalogue entry when the typed name matches by normalised
      // key; otherwise stay free-text (exerciseId null).
      final exerciseId = _catalogueByKey[normaliseExerciseName(name)];
      for (final s in ex.sets) {
        final durationS = int.tryParse(s.duration.text.trim());
        out.add((
          exerciseName: name,
          reps: int.tryParse(s.reps.text.trim()),
          // Entry is in the user's display unit; store canonical kg.
          weightKg: WeightFormat.parseToKg(s.weight.text, activeWeightUnit),
          rpe: double.tryParse(s.rpe.text.trim()),
          setType: s.setType,
          // duration_s is a non-negative integer column; clamp a stray negative.
          durationS: durationS == null ? null : (durationS < 0 ? 0 : durationS),
          exerciseId: exerciseId,
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

    return FullScreenFormBody(
      children: [
        FormSectionLabel(l10n.gymEditorTitleLabel),
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
                if (_catalogue.isNotEmpty)
                  IconButton(
                    tooltip: l10n.gymCatalogueBrowse,
                    icon: const Icon(Icons.menu_book_outlined),
                    color: theme.colorScheme.primary,
                    onPressed: () => _openPicker(ex),
                  ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 44, bottom: 6),
                      child: DropdownButtonFormField<String>(
                        key: Key('gym-set-type-$i-$si'),
                        initialValue: ex.sets[si].setType,
                        isDense: true,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: l10n.gymRoutineSetType,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final t in _gymSetTypes)
                            DropdownMenuItem(
                                value: t, child: Text(_gymSetTypeLabel(t, l10n))),
                        ],
                        onChanged: (v) => setState(
                            () => ex.sets[si].setType = v ?? ex.sets[si].setType),
                      ),
                    ),
                    Row(
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: _setNumberField(
                        ex.sets[si].duration,
                        l10n.gymDuration,
                        const TextInputType.numberWithOptions(decimal: false),
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
    if (_datalistNames.isEmpty) {
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
        return _datalistNames
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
  final TextEditingController duration;

  /// Raw set_type string (DB CHECK union, migration 20270224_001); defaults to
  /// 'working'. Held as a plain field — it's a dropdown, not a text input.
  String setType;

  _EditSet(
      {String reps = '',
      String weight = '',
      String rpe = '',
      String duration = '',
      this.setType = 'working'})
      : reps = TextEditingController(text: reps),
        weight = TextEditingController(text: weight),
        rpe = TextEditingController(text: rpe),
        duration = TextEditingController(text: duration);
  void dispose() {
    reps.dispose();
    weight.dispose();
    rpe.dispose();
    duration.dispose();
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
