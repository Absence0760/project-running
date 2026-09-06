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

import 'catalogue_fold_table.dart';

/// The `routes.surface` / `global_segments.surface` vocabulary, in the
/// canonical order the route builder offers it. Mirrors
/// `ENUM_VOCABULARIES.routeSurface`; both must stay in lockstep with the CHECK
/// constraint that owns the domain.
const List<String> kRouteSurfaceVocabulary = <String>['road', 'trail', 'mixed'];

/// The catalogue fields the browse surface reads.
///
/// `distanceM` / `elevationM` are nullable `num` because the numeric guard
/// treats an absent and an unusable value identically — see [sortCatalogue].
/// Web widens the same two fields to `number | string`, because Postgres
/// renders a `numeric` value JSON has no literal for as a JSON string; on this
/// side `GlobalSegmentRow.fromJson` coerces that string at its own boundary
/// (decisions § 985), so the honest input type here is the narrower one — a
/// non-finite `double` still arrives, which is what [sortCatalogue] screens.
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

/// Case- and diacritic-insensitive search key. Applied to BOTH sides of every
/// comparison, so it can only ever widen a match: anything that matched on the
/// raw strings still matches on the folded ones. That is what lets a reader
/// type "champs-elysees" and reach "Champs-Élysées" without a keyboard that has
/// the accent.
///
/// Must answer exactly as web's `fold` — NFD, drop every code point carrying
/// the Unicode `Diacritic` property, lowercase, collapse the Greek final sigma.
/// Dart's core library has none of those, so the answer is READ from
/// [kCatalogueFoldKeys] / [kCatalogueFoldValues], generated from Unicode's own
/// data by `scripts/gen_catalogue_fold_table.mjs`. The table it replaced was
/// hand-written and reached only as far as Latin Extended-A, which left 14,719
/// code points folding differently from web — every Vietnamese letter, all of
/// Greek, 57 Cyrillic, the pinyin tone letters, every Hangul syllable and the
/// CJK compatibility ideographs (decisions § 852).
///
/// The table carries the case mapping too, rather than composing with
/// [String.toLowerCase]. Dart's case tables are older than the web's — 466 code
/// points, among them the Georgian Mtavruli capitals, Cherokee, Osage and
/// Adlam, lowercase on web and stay uppercase here — so a fold that leaned on
/// them would keep importing that gap. Reading the whole answer from generated
/// data makes this side independent of the runtime's Unicode version.
///
/// Letters with NO canonical decomposition stay unfolded, because web keeps
/// them too: the stroke and ligature letters (`ø`, `đ`, `ħ`, `ł`, `ŧ`, `æ`,
/// `œ`, `ð`, `þ`, `ß`, `ı`) are base letters in their own right, and folding
/// them would invent an equivalence Unicode does not have.
///
/// The one deliberate residual is canonical REORDERING. NFD sorts a run of
/// combining marks by combining class; this walks the runes in the order they
/// arrive. The two can only disagree on a string carrying two adjacent marks
/// that BOTH survive the diacritic strip, in non-canonical order — which no
/// normalised text (NFC or NFD alike, both canonically ordered) can be.
String fold(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    final index = _foldIndex(rune);
    if (index >= 0) {
      out.write(kCatalogueFoldValues[index]);
      continue;
    }
    if (_writeHangulJamo(out, rune)) continue;
    out.writeCharCode(rune);
  }
  return out.toString();
}

/// Position of [rune] in [kCatalogueFoldKeys], or -1. The keys are ascending,
/// so this is a binary search — the alternative, materialising a 4,400-entry
/// map on first use, allocates on a path a keystroke runs.
int _foldIndex(int rune) {
  var lo = 0;
  var hi = kCatalogueFoldKeys.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final key = kCatalogueFoldKeys[mid];
    if (key == rune) return mid;
    if (key < rune) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return -1;
}

/// Writes [rune]'s Hangul jamo to [out], reporting whether it was a syllable.
///
/// UAX #15 decomposes the 11,172 syllables arithmetically rather than by table,
/// and none of the jamo carries a diacritic or a case, so the decomposition IS
/// the fold. The generator asserts this reproduces NFD for every syllable, so
/// the 11,172 rows it saves cost nothing in fidelity.
bool _writeHangulJamo(StringBuffer out, int rune) {
  final index = rune - kHangulSyllableBase;
  if (index < 0 || index >= kHangulSyllableCount) return false;
  final trail = index % kHangulTrailCount;
  out.writeCharCode(kHangulLeadBase + index ~/ kHangulVowelTrailCount);
  out.writeCharCode(
    kHangulVowelBase + (index % kHangulVowelTrailCount) ~/ kHangulTrailCount,
  );
  if (trail != 0) out.writeCharCode(kHangulTrailBase + trail);
  return true;
}

/// Finite numeric value of a possibly-absent column, else null.
num? _num(num? value) {
  if (value == null) return null;
  return value.isFinite ? value : null;
}

/// Total order on a pair of named, identified rows. Compares FOLDED names,
/// ties breaking on `id` so the result never depends on sort stability — which
/// matters more here than on web, because Dart's `List.sort` is not stable
/// where JS's is.
///
/// Neither platform's built-in ordering is used, and that is the point. Web
/// has `localeCompare`, a collation whose answer depends on the host's ICU
/// data; Dart has no collation at all, only [String.compareTo], which is
/// UTF-16 code-unit order. Measured over the 145,672 Unicode letters as
/// single-character names, the two disagree about **31.75 % of all pairs**,
/// and every one of those code points is ordered differently against at least
/// one other; over just the Latin/Greek/Cyrillic alphabet a name realistically
/// holds, 17.38 % of 344,035 pairs still disagree. A collation puts `Å` beside
/// `A` where a code-unit order puts it after `Z` — two different orderings,
/// not two roundings of one (decisions § 1337).
///
/// Folding first and comparing the folded keys is decided one code point at a
/// time from [kCatalogueFoldKeys] / [kCatalogueFoldValues], which is the only
/// shape both platforms can hold exactly.
int compareFoldedNames(String aName, String aId, String bName, String bId) {
  final c = fold(aName).compareTo(fold(bName));
  if (c != 0) return c < 0 ? -1 : 1;
  final byId = aId.compareTo(bId);
  return byId == 0 ? 0 : (byId < 0 ? -1 : 1);
}

int _byName(CatalogueSegment a, CatalogueSegment b) =>
    compareFoldedNames(a.name, a.id, b.name, b.id);

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
