import 'package:flutter_test/flutter_test.dart';

import '../lib/catalogue_browse.dart';

/// Mirror suite for `apps/web/src/lib/segments/catalogue_browse.test.ts`.
/// 27 tests here against web's 28: the extra web case pins the PostgREST
/// stringly-`numeric` coercion, which `GlobalSegmentRow.fromJson` already
/// performs at this side's own boundary, so the Dart helper never sees a
/// string. Its sibling — a value that does not resolve to a finite number —
/// is covered below.

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
}
