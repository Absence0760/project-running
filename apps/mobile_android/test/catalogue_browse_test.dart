import 'package:flutter_test/flutter_test.dart';

import '../lib/catalogue_browse.dart';
import '../lib/catalogue_fold_table.dart';

/// Mirror suite for `apps/web/src/lib/segments/catalogue_browse.test.ts`.
/// 41 tests here against web's 42: the extra web case pins the PostgREST
/// stringly-`numeric` coercion, which `GlobalSegmentRow.fromJson` already
/// performs at this side's own boundary, so the Dart helper never sees a
/// string. Its sibling — a value that does not resolve to a finite number —
/// is covered below.
///
/// The `fold` group is the half that used to diverge: every case in it is one
/// the hand-written fold table answered differently from web (decisions § 852).
/// What binds the generated table to web's own `fold` is
/// `apps/web/src/lib/segments/catalogue_fold_table.test.ts`, which runs web's
/// implementation against this file's committed table.

CatalogueSegment seg(
  String id, {
  String? name,
  String surface = 'road',
  String? region,
  num? distanceM = 1000,
  num? elevationM = 10,
}) =>
    CatalogueSegment(
      id: id,
      name: name ?? 'Segment $id',
      surface: surface,
      region: region,
      distanceM: distanceM,
      elevationM: elevationM,
    );

final List<CatalogueSegment> catalogue = [
  seg(
    'a',
    name: 'Champs-Élysées Sprint',
    region: 'Paris, FR',
    surface: 'road',
    distanceM: 2135,
    elevationM: 0,
  ),
  seg(
    'b',
    name: 'Central Park — Harlem Hill',
    region: 'Central Park, New York',
    surface: 'road',
    distanceM: 857,
    elevationM: 18,
  ),
  seg(
    'c',
    name: 'Bondi to Bronte Coastal',
    region: 'Sydney, AU',
    surface: 'trail',
    distanceM: 1665,
    elevationM: 16,
  ),
  seg(
    'd',
    name: 'Golden Gate Bridge Span',
    region: 'San Francisco, US',
    surface: 'mixed',
    distanceM: 2520,
    elevationM: 13,
  ),
];

List<String> ids(List<CatalogueSegment> rows) => [for (final r in rows) r.id];

void main() {
  group('filterCatalogue', () {
    test('no filters returns everything, in input order', () {
      expect(ids(filterCatalogue(catalogue)), ['a', 'b', 'c', 'd']);
    });

    test('a blank or whitespace query does not filter', () {
      expect(ids(filterCatalogue(catalogue, query: '')), ['a', 'b', 'c', 'd']);
      expect(
          ids(filterCatalogue(catalogue, query: '   ')), ['a', 'b', 'c', 'd']);
    });

    test('name match is case-insensitive', () {
      expect(ids(filterCatalogue(catalogue, query: 'GOLDEN gate')), ['d']);
    });

    test('name match is diacritic-insensitive both ways', () {
      // The reason the fold exists: an ASCII keyboard must reach an accented
      // name.
      expect(ids(filterCatalogue(catalogue, query: 'champs-elysees')), ['a']);
      // And folding never LOSES a match — the accented query still finds it.
      expect(ids(filterCatalogue(catalogue, query: 'Élysées')), ['a']);
    });

    test('query also matches the region', () {
      expect(ids(filterCatalogue(catalogue, query: 'sydney')), ['c']);
      expect(ids(filterCatalogue(catalogue, query: 'park')), ['b']);
    });

    test('a segment with no region is still searchable by name', () {
      final rows = [seg('x', name: 'Nameless Hill')];
      expect(ids(filterCatalogue(rows, query: 'hill')), ['x']);
      expect(ids(filterCatalogue(rows, query: 'paris')), <String>[]);
    });

    test('region filter is a whole-value match, not a substring', () {
      expect(ids(filterCatalogue(catalogue, region: 'Paris, FR')), ['a']);
      expect(ids(filterCatalogue(catalogue, region: 'Paris')), <String>[]);
    });

    test('the region filter returns every row its own dropdown option covers',
        () {
      // The defect this pins: catalogueRegions dedupes case/accent variants
      // onto ONE offered spelling, so an exact unfolded comparison here
      // returned only the rows spelled that way — the filter silently lost
      // matches the list it was built from asserts exist.
      final rows = [
        seg('a', region: 'Zürich, CH'),
        seg('b', region: 'zurich, ch'),
        seg('c', region: 'Oslo, NO'),
      ];
      final offered = catalogueRegions(rows);
      expect(offered, ['Oslo, NO', 'Zürich, CH'],
          reason: 'the two spellings collapse to one option');
      expect(ids(filterCatalogue(rows, region: 'Zürich, CH')), ['a', 'b']);
      for (final region in offered) {
        expect(filterCatalogue(rows, region: region), isNotEmpty,
            reason: '$region matched nothing');
      }
    });

    test('surrounding whitespace on a region filter is not a different region',
        () {
      expect(ids(filterCatalogue(catalogue, region: '  Paris, FR  ')), ['a']);
    });

    test('the surface filter stays verbatim — a token is not free text', () {
      // Deliberate asymmetry with region: `surface` is a CHECK-constrained
      // identifier, and catalogueSurfaces does not fold-dedupe, so nothing
      // offers a spelling the database does not hold.
      expect(ids(filterCatalogue(catalogue, surface: 'ROAD')), <String>[]);
      expect(ids(filterCatalogue(catalogue, surface: 'road')), ['a', 'b']);
    });

    test('surface filter is an exact match', () {
      expect(ids(filterCatalogue(catalogue, surface: 'road')), ['a', 'b']);
      expect(ids(filterCatalogue(catalogue, surface: 'trail')), ['c']);
    });

    test('null / empty filter values mean "all", not "match empty"', () {
      expect(ids(filterCatalogue(catalogue, region: null, surface: '')),
          ['a', 'b', 'c', 'd']);
    });

    test('filters combine (AND), and a contradiction is empty', () {
      expect(ids(filterCatalogue(catalogue, query: 'park', surface: 'road')),
          ['b']);
      expect(ids(filterCatalogue(catalogue, query: 'park', surface: 'trail')),
          <String>[]);
    });

    test('does not mutate its input', () {
      final before = ids(catalogue);
      filterCatalogue(catalogue, query: 'park');
      expect(ids(catalogue), before);
    });
  });

  group('catalogueRegions', () {
    test('distinct, blank-free, and ordered', () {
      expect(catalogueRegions(catalogue), [
        'Central Park, New York',
        'Paris, FR',
        'San Francisco, US',
        'Sydney, AU',
      ]);
    });

    test('drops null and whitespace-only regions', () {
      final rows = [
        seg('a'),
        seg('b', region: '   '),
        seg('c', region: 'Oslo, NO'),
      ];
      expect(catalogueRegions(rows), ['Oslo, NO']);
    });

    test('dedupes case- and accent-variants onto the first spelling', () {
      // Two curators typing the same place differently must not produce two
      // dropdown rows that each filter out half the segments.
      final rows = [
        seg('a', region: 'Zürich, CH'),
        seg('b', region: 'zurich, ch'),
      ];
      expect(catalogueRegions(rows), ['Zürich, CH']);
    });
  });

  group('catalogueSurfaces', () {
    test('canonical RouteSurface order, not alphabetical', () {
      expect(catalogueSurfaces(catalogue), ['road', 'trail', 'mixed']);
    });

    test('only offers surfaces the catalogue actually has', () {
      final rows = [seg('a', surface: 'trail'), seg('b', surface: 'trail')];
      expect(catalogueSurfaces(rows), ['trail']);
    });

    test('an unknown surface stays selectable, after the known ones', () {
      final rows = [
        seg('a', surface: 'gravel'),
        seg('b', surface: 'road'),
        seg('c', surface: 'beach'),
      ];
      expect(catalogueSurfaces(rows), ['road', 'beach', 'gravel']);
    });
  });

  group('sortCatalogue', () {
    test('by name, accent-folded', () {
      expect(ids(sortCatalogue(catalogue, CatalogueSort.name)),
          ['c', 'b', 'a', 'd']);
    });

    test('shortest and longest are exact reverses on distinct lengths', () {
      expect(ids(sortCatalogue(catalogue, CatalogueSort.shortest)),
          ['b', 'c', 'a', 'd']);
      expect(ids(sortCatalogue(catalogue, CatalogueSort.longest)),
          ['d', 'a', 'c', 'b']);
    });

    test('most climb first', () {
      expect(ids(sortCatalogue(catalogue, CatalogueSort.climb)),
          ['b', 'c', 'd', 'a']);
    });

    test('equal values break the tie on name, so the order is stable', () {
      final rows = [
        seg('z', name: 'Zoo Loop', distanceM: 1000),
        seg('a', name: 'Abbey Climb', distanceM: 1000),
      ];
      expect(ids(sortCatalogue(rows, CatalogueSort.shortest)), ['a', 'z']);
      expect(ids(sortCatalogue(rows, CatalogueSort.longest)), ['a', 'z']);
    });

    test('an unknown elevation sorts last, never first, under most-climb', () {
      final rows = [
        seg('null', elevationM: null),
        seg('small', elevationM: 5),
        seg('big', elevationM: 400),
      ];
      expect(ids(sortCatalogue(rows, CatalogueSort.climb)),
          ['big', 'small', 'null']);
    });

    test('an unusable numeric sorts last under every numeric order', () {
      final rows = [
        seg('bad', distanceM: double.nan),
        seg('good', distanceM: 900),
      ];
      expect(ids(sortCatalogue(rows, CatalogueSort.shortest)), ['good', 'bad']);
      expect(ids(sortCatalogue(rows, CatalogueSort.longest)), ['good', 'bad']);
    });

    test('does not mutate its input', () {
      final before = ids(catalogue);
      sortCatalogue(catalogue, CatalogueSort.longest);
      expect(ids(catalogue), before);
    });
  });

  group('fold', () {
    // Every case below is one the hand-written table this pair used to carry
    // got wrong: it stopped at Latin Extended-A, so 14,719 code points folded
    // one way on web and another here (decisions § 852).

    test('Vietnamese: the tone marks fold, the barred D does not', () {
      // Latin Extended Additional, all 245 of which the old table missed. Đ is
      // the deliberate exception in the other direction: it has no canonical
      // decomposition, so web keeps it too.
      expect(fold('Đèo Hải Vân'), 'đeo hai van');
      expect(fold('Ơn Ưu'), 'on uu');
    });

    test('Greek: breathings, accents and both sigmas fold onto the letter', () {
      expect(fold('Ἀθήνα'), 'αθηνα');
      expect(fold('Ῥόδος'), 'ροδοσ');
    });

    test('the two sigmas fold together, so the search key is sigma-blind', () {
      // web's toLowerCase applies Unicode's Final_Sigma rule, which made ΟΔΟΣ
      // fold to a key the query "οδοσ" could not reach. Both sides now collapse
      // ς onto σ (decisions § 853).
      expect(fold('ΟΔΟΣ'), fold('οδος'));
      expect(fold('οδοσ'), fold('οδος'));
    });

    test('pinyin tone letters fold to the bare vowel', () {
      expect(fold('Huángshān Lǎodào'), 'huangshan laodao');
      expect(fold('ǎǐǒǔ'), 'aiou');
    });

    test('Cyrillic accents fold', () {
      expect(fold('Ё'), 'е');
      expect(fold('Ї'), 'і');
    });

    test('a spacing diacritic is deleted, not kept', () {
      // The seven inside Latin-1 itself, which web strips because they carry
      // the Diacritic property even though they stand alone.
      expect(fold('a´b'), 'ab');
      expect(fold('¨¯¸·`^'), '');
    });

    test('a combining mark is dropped wherever it sits in the block', () {
      // The old ranges covered five blocks; the property covers more.
      expect(fold('Xī̌ān'), 'xian');
    });

    test('a case mapping Dart itself does not know still folds', () {
      // Georgian Mtavruli. Dart's toLowerCase leaves 466 code points uppercase
      // that web lowercases, which is why the table carries the case mapping
      // rather than composing with String.toLowerCase.
      expect(fold('Ⴧ'), 'ⴧ');
    });

    test('a CJK compatibility ideograph folds to its unified form', () {
      expect(fold('\u{F900}'), '\u{8C48}');
    });

    test('a Hangul syllable decomposes to its jamo, as NFD does', () {
      expect(
        fold('북한산'),
        String.fromCharCodes(
          <int>[0x1107, 0x116E, 0x11A8, 0x1112, 0x1161, 0x11AB, 0x1109, 0x1161, 0x11AB],
        ),
      );
    });

    test('letters with no canonical decomposition stay unfolded', () {
      // Folding these would invent an equivalence Unicode does not have, and
      // web does not fold them either.
      expect(fold('Øst Đông Straße'), 'øst đong straße');
      expect(fold('ħŧæœðþı'), 'ħŧæœðþı');
    });

    test('folding only ever widens: an ASCII query reaches every variant', () {
      // The property the whole helper rests on — it is applied to BOTH sides of
      // every comparison, so anything that matched raw still matches folded.
      const names = <String>[
        'Đèo Hải Vân',
        'Champs-Élysées',
        'Huángshān',
        'Ἀθήνα',
      ];
      for (final name in names) {
        expect(fold(name).contains(fold(name)), isTrue);
        expect(fold(name.toUpperCase()).contains(fold(name)), isTrue);
      }
      expect(fold('Đèo Hải Vân').contains(fold('hai')), isTrue);
      expect(fold('Huángshān').contains(fold('huangshan')), isTrue);
    });

    test('the generated table is a well-formed parallel pair', () {
      expect(kCatalogueFoldKeys.length, kCatalogueFoldValues.length);
      expect(kCatalogueFoldKeys.length, greaterThan(4000));
      for (var i = 1; i < kCatalogueFoldKeys.length; i++) {
        expect(kCatalogueFoldKeys[i], greaterThan(kCatalogueFoldKeys[i - 1]),
            reason: 'keys must be ascending for the binary search');
      }
      // The search reaches the ends of the table, not just its middle.
      expect(fold(String.fromCharCode(kCatalogueFoldKeys.first)),
          kCatalogueFoldValues.first);
      expect(fold(String.fromCharCode(kCatalogueFoldKeys.last)),
          kCatalogueFoldValues.last);
    });

    test('a name outside the table passes through untouched', () {
      expect(fold(''), '');
      expect(fold('central park - harlem hill'), 'central park - harlem hill');
      expect(fold('東京 5K'), '東京 5k');
    });
  });

  // ── compareFoldedNames ──────────────────────────────────────────────
  //
  // The shared name order. Public because the routes list sorts through it
  // too: it used to call `toLowerCase().compareTo()` here and `localeCompare`
  // on the web, two orderings that disagree about 31.75 % of all pairs of
  // Unicode letters (decisions § 1337).
  group('compareFoldedNames', () {
    test('orders on the folded name, not on a collation or a code-unit order',
        () {
      // Web's `localeCompare` sorts Å beside A; this side's only primitive is
      // `String.compareTo`, a code-unit order that sorts it after Z because
      // U+00C5 > U+005A. The fold gives both platforms the same answer.
      expect(compareFoldedNames('Åre', 'a', 'Zaragoza', 'b'), -1);
      expect(compareFoldedNames('Zaragoza', 'b', 'Åre', 'a'), 1);
      // Pin the order it is NOT: raw code units put Zaragoza first.
      expect('Åre'.compareTo('Zaragoza') > 0, isTrue);
    });

    test('case and accent do not decide the order', () {
      // Folds equal, so the id breaks the tie rather than the spelling.
      expect(compareFoldedNames('ÉCOLE', 'a', 'ecole', 'b'), -1);
      expect(compareFoldedNames('ÉCOLE', 'b', 'ecole', 'a'), 1);
    });

    test('U+0130 sorts with i, not apart from it', () {
      // The reachable half of the 466-code-point lower-case gap. A browser's
      // `toLowerCase` emits i + a combining dot here, which sorts after a bare
      // i and does not even contain it; the fold strips the mark on both
      // platforms.
      expect(fold('İstanbul'), fold('Istanbul'));
      expect(compareFoldedNames('İstanbul', 'a', 'Istanbul', 'b'), -1);
    });

    test('ties break on id, so the order never depends on sort stability', () {
      expect(compareFoldedNames('Loop', 'a', 'Loop', 'b'), -1);
      expect(compareFoldedNames('Loop', 'b', 'Loop', 'a'), 1);
    });

    test('the same row compares equal to itself', () {
      expect(compareFoldedNames('Loop', 'x', 'Loop', 'x'), 0);
    });
  });
}
