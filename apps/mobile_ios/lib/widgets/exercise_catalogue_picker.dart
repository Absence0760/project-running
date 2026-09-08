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

  /// Whether [catalogue] is known to be the whole catalogue. A THIRD state
  /// rather than a synonym for empty: every decision below is a claim about
  /// what the catalogue does NOT hold, and a list that failed to load — or has
  /// not answered yet — supports none of them.
  final bool unavailable;

  /// Invoked with a freshly-created owner custom so the host merges it into its
  /// own catalogue copy (binding the id without a reload).
  final void Function(GymCatalogueEntry created)? onCreated;

  const ExerciseCataloguePickerScreen({
    super.key,
    required this.catalogue,
    this.api,
    this.unavailable = false,
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
  bool _creating = false;

  /// Read off `widget` rather than snapshotted in `initState`: the host fills
  /// its catalogue from an async read, and a snapshot is a claim about what
  /// exists taken before the read had answered.
  List<GymCatalogueEntry> get _entries => widget.catalogue;

  @override
  void initState() {
    super.initState();
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

  /// Every catalogue entry the query names EXACTLY, category filter ignored,
  /// in the same order the result list would show them.
  ///
  /// Scanning the whole catalogue is what [_canCreate] needs: `exercises` is
  /// keyed on the folded name, so a second row under a key the catalogue
  /// already holds is a duplicate whichever category it claims. Narrowing this
  /// to the visible set would trade the dead end below for a duplicate write.
  ///
  /// It can hold MORE THAN ONE row, and that is by design rather than by
  /// accident: `exercises`' two uniques are partial, so an owner custom may
  /// shadow a seeded global under one folded key (`api_database.md`). Ordering
  /// them here rather than reading the catalogue's own order is what makes
  /// [_hiddenExact] name the same entry every time — the fetch orders by
  /// `(name, id)` on this platform and by `name` alone on web, where two rows
  /// spelled identically are then an unspecified tie.
  List<GymCatalogueEntry> get _exact {
    final key = normaliseExerciseName(_query);
    if (key.isEmpty) return const [];
    final out = _entries
        .where((e) => normaliseExerciseName(e.name) == key)
        .toList(growable: false);
    out.sort(_byName);
    return out;
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

  /// Blank on the KEY, as [_exact] already is: `exercises.name_key` carries
  /// `length(...) between 1 and 120`, so an affordance offered on one test and
  /// an insert attempted on the other is a 23514 the reader cannot act on
  /// (decisions 1367).
  ///
  /// False whenever the catalogue is [ExerciseCataloguePickerScreen.unavailable]
  /// too. The test is "the catalogue does not hold this name", and a list that
  /// failed to load is evidence of nothing: the insert then either mints a
  /// shadow the reader did not ask for — against a seeded global, which the
  /// author's partial unique cannot see — or 23505s against their own custom,
  /// after the affordance said the name was free.
  bool get _canCreate =>
      widget.api != null &&
      !widget.unavailable &&
      namesAnExercise(_query) &&
      _exact.isEmpty &&
      !_creating;

  Future<void> _create() async {
    final api = widget.api;
    // The name is bound before it is judged, so the blankness test and the
    // value sent to the insert are one expression rather than two reads of a
    // getter that could drift apart — and so the source scan that bans a
    // decision taken on the display SPELLING can see this call site at all
    // (§ 1573; the web twin's create path has the same shape for the same
    // reason).
    final name = _query;
    if (api == null ||
        widget.unavailable ||
        !namesAnExercise(name) ||
        _creating) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _creating = true);
    final made = await api.createCustomExercise(
      name: name,
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
      nameKey: made.nameKey,
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
          if (widget.unavailable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.gymCatalogueUnavailable,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
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
                // "No exercises match" is a claim about the catalogue, so while
                // it is unavailable the notice above is the only honest thing
                // to say and the centre stays blank.
                ? (hiddenExact == null && widget.unavailable
                    ? const SizedBox.shrink()
                    : Center(
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
                  ))
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
