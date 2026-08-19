/// Browse shaping for the free-standing famous-segment catalogue
/// (decisions §233). Dart twin of
/// `apps/web/src/lib/segments/catalogue_browse.ts` — keep the two in
/// lockstep; the `shared-library-syncer` agent watches the pair.
///
/// Filtering is client-side because the curated v1 catalogue is bounded by
/// the 500-row scoring limit and already fetched whole — a server round-trip
/// per keystroke would buy nothing.
///
/// Pure module — no Supabase, no Flutter, no localisation.
library;

/// The `routes.surface` / `global_segments.surface` vocabulary, in the
/// canonical order the route builder offers it. Mirrors
/// `ENUM_VOCABULARIES.routeSurface`; both must stay in lockstep with the CHECK
/// constraint that owns the domain.
const List<String> kRouteSurfaceVocabulary = <String>['road', 'trail', 'mixed'];

/// The catalogue fields the browse surface reads.
///
/// `distanceM` / `elevationM` are nullable `num` because the numeric guard
/// treats an absent and an unusable value identically — see [sortCatalogue].
/// Web widens the same two fields to `number | string`, because PostgREST may
/// hand a `numeric` column over as a JSON string; on this side
/// `GlobalSegmentRow.fromJson` has already coerced through `as num` at its own
/// boundary, so the honest input type here is the narrower one.
class CatalogueSegment {
  const CatalogueSegment({
    required this.id,
    required this.name,
    required this.surface,
    this.region,
    this.distanceM,
    this.elevationM,
  });

  final String id;
  final String name;
  final String surface;
  final String? region;
  final num? distanceM;
  final num? elevationM;
}

/// Display orders the browse surface offers. Web's `CatalogueSort` string
/// union reads as an enum here — an idiomatic shape difference, not a
/// divergence.
enum CatalogueSort { name, shortest, longest, climb }

/// Base letter for every precomposed Latin letter whose Unicode canonical
/// decomposition is `base + combining mark`, keyed by that base.
///
/// Web folds by decomposing to NFD and dropping the combining marks. Dart has
/// no normalisation in its core library, so the same class is spelled out here
/// rather than left to a runtime that cannot do it — the discipline
/// `gym_prs.dart`'s `kExerciseWhitespace` follows.
///
/// Letters with NO canonical decomposition are deliberately absent, because web
/// keeps them too: the stroke and ligature letters (`ø`, `đ`, `ħ`, `ł`, `ŧ`,
/// `æ`, `œ`, `ð`, `þ`, `ß`, `ı`) are base letters in their own right, and
/// folding them would invent an equivalence NFD does not have.
const Map<String, String> _foldGroups = <String, String>{
  'a': 'àáâãäåāăą',
  'c': 'çćĉċč',
  'd': 'ď',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥ',
  'i': 'ìíîïĩīĭį',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľ',
  'n': 'ñńņň',
  'o': 'òóôõöōŏő',
  'r': 'ŕŗř',
  's': 'śŝşš',
  't': 'ţť',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
};

final Map<int, int> _foldMap = <int, int>{
  for (final entry in _foldGroups.entries)
    for (final unit in entry.value.codeUnits) unit: entry.key.codeUnitAt(0),
};

/// Whether [unit] is a combining mark, i.e. what an already-decomposed name
/// carries where a precomposed one carries a single letter. Dropping these is
/// the other half of web's NFD-then-strip, so both spellings of the same place
/// fold to the same key.
bool _isCombiningMark(int unit) =>
    (unit >= 0x0300 && unit <= 0x036f) ||
    (unit >= 0x1ab0 && unit <= 0x1aff) ||
    (unit >= 0x1dc0 && unit <= 0x1dff) ||
    (unit >= 0x20d0 && unit <= 0x20f0) ||
    (unit >= 0xfe20 && unit <= 0xfe2f);

/// Case- and diacritic-insensitive search key. Applied to BOTH sides of every
/// comparison, so it can only ever widen a match: anything that matched on the
/// raw strings still matches on the folded ones. That is what lets a reader
/// type "champs-elysees" and reach "Champs-Élysées" without a keyboard that has
/// the accent.
String fold(String value) {
  final lower = value.toLowerCase();
  final out = <int>[];
  for (final unit in lower.codeUnits) {
    if (_isCombiningMark(unit)) continue;
    out.add(_foldMap[unit] ?? unit);
  }
  return String.fromCharCodes(out);
}

/// Finite numeric value of a possibly-absent column, else null.
num? _num(num? value) {
  if (value == null) return null;
  return value.isFinite ? value : null;
}

/// Total order on names. Compares folded names, ties breaking on `id` so the
/// result never depends on sort stability — which matters more here than on
/// web, because Dart's `List.sort` is not stable where JS's is.
int _byName(CatalogueSegment a, CatalogueSegment b) {
  final c = fold(a.name).compareTo(fold(b.name));
  if (c != 0) return c < 0 ? -1 : 1;
  final byId = a.id.compareTo(b.id);
  return byId == 0 ? 0 : (byId < 0 ? -1 : 1);
}

/// The identity [catalogueRegions] dedupes on AND [filterCatalogue] compares
/// against — one function for both, because they are one decision. The dropdown
/// collapses "Zürich, CH" and "zurich, ch" onto a single offered spelling, so a
/// filter matching the raw string would return half the rows its own option
/// claims to cover.
///
/// Regions are free-text curator input, which is why they fold. `surface` is a
/// CHECK-constrained identifier, so [catalogueSurfaces] does not fold-dedupe
/// and the surface filter compares verbatim — folding a database token would be
/// inventing equivalences the database does not have.
String? _regionKey(String? region) {
  final trimmed = region?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : fold(trimmed);
}

/// Distinct non-blank regions present in the catalogue, in display order.
List<String> catalogueRegions(List<CatalogueSegment> segments) {
  final seen = <String, String>{};
  for (final s in segments) {
    final key = _regionKey(s.region);
    if (key == null) continue;
    seen.putIfAbsent(key, () => s.region!.trim());
  }
  final keys = seen.keys.toList()..sort();
  return [for (final k in keys) seen[k]!];
}

/// Distinct surfaces present in the catalogue, in the canonical
/// [kRouteSurfaceVocabulary] order rather than alphabetically. A value outside
/// the vocabulary (this client older than the database) is kept and sorted
/// after the known ones, so it stays selectable instead of silently vanishing
/// from the filter while its segments remain in the list.
List<String> catalogueSurfaces(List<CatalogueSegment> segments) {
  final present = <String>{};
  for (final s in segments) {
    final surface = s.surface.trim();
    if (surface.isNotEmpty) present.add(surface);
  }
  final inOrder = [
    for (final s in kRouteSurfaceVocabulary)
      if (present.contains(s)) s,
  ];
  final unknown = [
    for (final s in present)
      if (!kRouteSurfaceVocabulary.contains(s)) s,
  ]..sort((a, b) => fold(a).compareTo(fold(b)));
  return [...inOrder, ...unknown];
}

/// Narrows the catalogue to the rows matching every supplied filter. The text
/// query matches a segment's name OR its region, so "Berlin" and "Tiergarten"
/// both find the same row. Region and surface are whole-value matches against
/// what [catalogueRegions] / [catalogueSurfaces] offered — region through
/// [_regionKey] (see there for why one folds and the other does not), surface
/// verbatim.
///
/// Returns a new list.
List<CatalogueSegment> filterCatalogue(
  List<CatalogueSegment> segments, {
  String? query,
  String? region,
  String? surface,
}) {
  final q = fold(query?.trim() ?? '');
  final r = _regionKey(region);
  final trimmed = surface?.trim();
  final s = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  return [
    for (final seg in segments)
      if (_matches(seg, q, r, s)) seg,
  ];
}

bool _matches(
  CatalogueSegment seg,
  String query,
  String? region,
  String? surface,
) {
  if (region != null && _regionKey(seg.region) != region) return false;
  if (surface != null && seg.surface != surface) return false;
  if (query.isEmpty) return true;
  return fold(seg.name).contains(query) ||
      fold(seg.region ?? '').contains(query);
}

/// Orders the catalogue for display. Returns a new list.
///
/// A segment whose distance / elevation is absent or non-finite sorts LAST
/// under every numeric order, including the descending ones — an unknown climb
/// must never be presented as the biggest climb.
List<CatalogueSegment> sortCatalogue(
  List<CatalogueSegment> segments,
  CatalogueSort sort,
) {
  final out = List<CatalogueSegment>.of(segments);
  switch (sort) {
    case CatalogueSort.shortest:
      out.sort((a, b) {
        final c = _compareNumeric(_num(a.distanceM), _num(b.distanceM), 1);
        return c != 0 ? c : _byName(a, b);
      });
    case CatalogueSort.longest:
      out.sort((a, b) {
        final c = _compareNumeric(_num(a.distanceM), _num(b.distanceM), -1);
        return c != 0 ? c : _byName(a, b);
      });
    case CatalogueSort.climb:
      out.sort((a, b) {
        final c = _compareNumeric(_num(a.elevationM), _num(b.elevationM), -1);
        return c != 0 ? c : _byName(a, b);
      });
    case CatalogueSort.name:
      out.sort(_byName);
  }
  return out;
}

/// [direction] is 1 for ascending, -1 for descending. Nulls always sort last.
int _compareNumeric(num? a, num? b, int direction) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  if (a == b) return 0;
  return a < b ? -direction : direction;
}
