import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../catalogue_browse.dart' show compareFoldedNames;
import '../gym_prs.dart';
import '../l10n/gen/app_localizations.dart';
import 'gym_compose_sheet.dart';
import 'top_banner.dart';

/// Browse / search / filter the exercise catalogue (migration 20270222_001,
/// decisions §176) and pick an entry. Flutter twin of web
/// ExerciseCataloguePicker.svelte. Picking pops the screen with the chosen
/// [GymCatalogueEntry]; the composer fills the name from it so the existing
/// normalised-key path binds gym_sets.exercise_id at save. When no entry
/// matches the search and an [api] is available, a create-custom affordance
/// adds an owner entry and picks it in one step.
class ExerciseCataloguePickerScreen extends StatefulWidget {
  final List<GymCatalogueEntry> catalogue;

  /// Online API client; null offline / signed-out — then the create-custom
  /// affordance is hidden and browse stays read-only.
  final ApiClient? api;

  /// Invoked with a freshly-created owner custom so the host merges it into its
  /// own catalogue copy (binding the id without a reload).
  final void Function(GymCatalogueEntry created)? onCreated;

  const ExerciseCataloguePickerScreen({
    super.key,
    required this.catalogue,
    this.api,
    this.onCreated,
  });

  @override
  State<ExerciseCataloguePickerScreen> createState() =>
      _ExerciseCataloguePickerScreenState();
}

/// The catalogue categories (exercises.category CHECK, migration 20270222_001),
/// in the filter-dropdown order. 'all' is a UI-only sentinel.
const List<String> _kCategories = [
  'chest',
  'back',
  'shoulders',
  'legs',
  'arms',
  'core',
  'cardio',
  'full_body',
  'other',
];

/// Localised label for a category id (or the 'all' sentinel).
String categoryLabel(AppLocalizations l10n, String category) {
  switch (category) {
    case 'all':
      return l10n.gymCatalogueCategoryAll;
    case 'chest':
      return l10n.gymCatalogueCategoryChest;
    case 'back':
      return l10n.gymCatalogueCategoryBack;
    case 'shoulders':
      return l10n.gymCatalogueCategoryShoulders;
    case 'legs':
      return l10n.gymCatalogueCategoryLegs;
    case 'arms':
      return l10n.gymCatalogueCategoryArms;
    case 'core':
      return l10n.gymCatalogueCategoryCore;
    case 'cardio':
      return l10n.gymCatalogueCategoryCardio;
    case 'full_body':
      return l10n.gymCatalogueCategoryFullBody;
    default:
      return l10n.gymCatalogueCategoryOther;
  }
}

/// Total order on catalogue display names.
///
/// Compares DIACRITIC-FOLDED display names, not the normalised exercise KEY.
/// Ordering a human-facing list is not keying it (decisions § 1276), and the
/// key comparison this replaces was a UTF-16 code-unit compare that filed
/// every accented name after "z": measured over `['Ab Wheel', 'Bench Press',
/// 'Élévation latérale', 'Overhead Press', 'Row', 'Überzug', 'źcisk',
/// 'Zercher Squat']` it put all three accented names behind `Zercher Squat`
/// and diverged from the web picker's list at position 2.
///
/// Dart's core library ships no collator, so this cannot BE web's
/// `localeCompare`; [fold] — the generated Unicode diacritic strip
/// `catalogue_browse` already uses for exactly this reason (§ 852) — is the
/// closest instrument this platform has, and it puts each of those three names
/// where a reader expects it. What remains is the letters Unicode gives no
/// canonical decomposition (`ø`, `đ`, `ł`, `ß`, `æ`), which a collation
/// interleaves and a folded compare still files after `z`.
///
/// Ties break on `id`, so the answer does not depend on sort stability —
/// Dart's `List.sort` is not stable, and the folded compare calls two
/// spellings of one name equal.
int _byName(GymCatalogueEntry a, GymCatalogueEntry b) =>
    compareFoldedNames(a.name, a.id, b.name, b.id);

class _ExerciseCataloguePickerScreenState
    extends State<ExerciseCataloguePickerScreen> {
  final TextEditingController _search = TextEditingController();
  String _category = 'all';
  late List<GymCatalogueEntry> _entries;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _entries = [...widget.catalogue];
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim();

  bool _inCategory(GymCatalogueEntry e) =>
      _category == 'all' || e.category == _category;

  List<GymCatalogueEntry> get _filtered {
    final q = normaliseExerciseName(_query);
    final out = _entries
        .where(_inCategory)
        .where((e) => q.isEmpty || normaliseExerciseName(e.name).contains(q))
        .toList();
    out.sort(_byName);
    return out;
  }

  /// Every catalogue entry the query names EXACTLY, category filter ignored.
  ///
  /// Scanning the whole catalogue is what [_canCreate] needs: `exercises` is
  /// keyed on the folded name, so a second row under a key the catalogue
  /// already holds is a duplicate whichever category it claims. Narrowing this
  /// to the visible set would trade the dead end below for a duplicate write.
  List<GymCatalogueEntry> get _exact {
    final key = normaliseExerciseName(_query);
    if (key.isEmpty) return const [];
    return _entries
        .where((e) => normaliseExerciseName(e.name) == key)
        .toList(growable: false);
  }

  /// The entry the query names exactly while the category filter hides it,
  /// else null.
  ///
  /// Without this the state had no honest rendering: the list is empty and
  /// [_canCreate] is false, which used to resolve to a bare "No exercises
  /// match." beside no create button and no explanation — the exercise
  /// existed, was not shown, and could not be added (decisions § 1276's
  /// residual half). Always null under 'all', where a key EQUAL to the query
  /// necessarily contains it and the entry is therefore listed.
  GymCatalogueEntry? get _hiddenExact {
    final exact = _exact;
    if (exact.isEmpty) return null;
    return exact.any(_inCategory) ? null : exact.first;
  }

  bool get _canCreate =>
      widget.api != null && _query.isNotEmpty && _exact.isEmpty && !_creating;

  Future<void> _create() async {
    final api = widget.api;
    if (api == null || _query.isEmpty || _creating) return;
    final l10n = AppLocalizations.of(context);
    final name = _query;
    setState(() => _creating = true);
    final made = await api.createCustomExercise(
      name: name,
      nameKey: normaliseExerciseName(name),
      category: _category == 'all' ? 'other' : _category,
    );
    if (!mounted) return;
    setState(() => _creating = false);
    if (made == null) {
      showTopBanner(context, l10n.gymCatalogueCreateFailed);
      return;
    }
    final entry = (
      name: made.name,
      id: made.id,
      category: made.category,
      authorId: made.authorId,
    );
    widget.onCreated?.call(entry);
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final filtered = _filtered;
    final hiddenExact = _hiddenExact;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gymCatalogueTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.gymCatalogueSearchPlaceholder,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      l10n.gymCatalogueCategoryLabel,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _category,
                        onChanged: (v) =>
                            setState(() => _category = v ?? 'all'),
                        items: [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text(categoryLabel(l10n, 'all')),
                          ),
                          for (final c in _kCategories)
                            DropdownMenuItem(
                              value: c,
                              child: Text(categoryLabel(l10n, c)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_canCreate)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _creating ? null : _create,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.gymCatalogueCreate(_query)),
                ),
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        hiddenExact == null
                            ? l10n.gymCatalogueEmpty
                            : l10n.gymCatalogueOtherCategory(
                                hiddenExact.name,
                                categoryLabel(l10n, hiddenExact.category),
                              ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final e = filtered[i];
                      return ListTile(
                        title: Text(e.name),
                        subtitle: Text(categoryLabel(l10n, e.category)),
                        trailing: e.authorId != null
                            ? Chip(
                                label: Text(l10n.gymCatalogueCustomBadge),
                                visualDensity: VisualDensity.compact,
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
