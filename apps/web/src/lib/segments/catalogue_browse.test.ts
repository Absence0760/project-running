import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	catalogueRegions,
	catalogueSurfaces,
	compareFoldedNames,
	filterCatalogue,
	fold,
	sortCatalogue,
	type CatalogueSegment,
} from './catalogue_browse';

function seg(over: Partial<CatalogueSegment> & { id: string }): CatalogueSegment {
	return {
		name: `Segment ${over.id}`,
		surface: 'road',
		region: null,
		distance_m: 1000,
		elevation_m: 10,
		...over,
	};
}

const CATALOGUE: CatalogueSegment[] = [
	seg({
		id: 'a',
		name: 'Champs-Élysées Sprint',
		region: 'Paris, FR',
		surface: 'road',
		distance_m: 2135,
		elevation_m: 0,
	}),
	seg({
		id: 'b',
		name: 'Central Park — Harlem Hill',
		region: 'Central Park, New York',
		surface: 'road',
		distance_m: 857,
		elevation_m: 18,
	}),
	seg({
		id: 'c',
		name: 'Bondi to Bronte Coastal',
		region: 'Sydney, AU',
		surface: 'trail',
		distance_m: 1665,
		elevation_m: 16,
	}),
	seg({
		id: 'd',
		name: 'Golden Gate Bridge Span',
		region: 'San Francisco, US',
		surface: 'mixed',
		distance_m: 2520,
		elevation_m: 13,
	}),
];

const ids = (rows: readonly CatalogueSegment[]): string[] => rows.map((r) => r.id);

// ─────────── filterCatalogue ───────────

test('filterCatalogue: no filters returns everything, in input order', () => {
	assert.deepEqual(ids(filterCatalogue(CATALOGUE)), ['a', 'b', 'c', 'd']);
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, {})), ['a', 'b', 'c', 'd']);
});

test('filterCatalogue: a blank or whitespace query does not filter', () => {
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { query: '' })), ['a', 'b', 'c', 'd']);
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { query: '   ' })), ['a', 'b', 'c', 'd']);
});

test('filterCatalogue: name match is case-insensitive', () => {
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { query: 'GOLDEN gate' })), ['d']);
});

test('filterCatalogue: name match is diacritic-insensitive both ways', () => {
	// The reason the fold exists: an ASCII keyboard must reach an accented name.
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { query: 'champs-elysees' })), ['a']);
	// And folding never LOSES a match — the accented query still finds it.
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { query: 'Élysées' })), ['a']);
});

test('filterCatalogue: query also matches the region', () => {
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { query: 'sydney' })), ['c']);
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { query: 'park' })), ['b']);
});

test('filterCatalogue: a segment with no region is still searchable by name', () => {
	const rows = [seg({ id: 'x', name: 'Nameless Hill', region: null })];
	assert.deepEqual(ids(filterCatalogue(rows, { query: 'hill' })), ['x']);
	assert.deepEqual(ids(filterCatalogue(rows, { query: 'paris' })), []);
});

test('filterCatalogue: region filter is a whole-value match, not a substring', () => {
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { region: 'Paris, FR' })), ['a']);
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { region: 'Paris' })), []);
});

test('filterCatalogue: the region filter returns every row its own dropdown option covers', () => {
	// The defect this pins: catalogueRegions dedupes case/accent variants onto
	// ONE offered spelling, so an exact unfolded comparison here returned only
	// the rows spelled that way — the filter silently lost matches the list it
	// was built from asserts exist.
	const rows = [
		seg({ id: 'a', region: 'Zürich, CH' }),
		seg({ id: 'b', region: 'zurich, ch' }),
		seg({ id: 'c', region: 'Oslo, NO' }),
	];
	const offered = catalogueRegions(rows);
	assert.deepEqual(offered, ['Oslo, NO', 'Zürich, CH'], 'the two spellings collapse to one option');
	assert.deepEqual(ids(filterCatalogue(rows, { region: 'Zürich, CH' })), ['a', 'b']);
	// And every offered option finds at least the row it was derived from.
	for (const region of offered) {
		assert.ok(filterCatalogue(rows, { region }).length > 0, `${region} matched nothing`);
	}
});

test('filterCatalogue: surrounding whitespace on a region filter is not a different region', () => {
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { region: '  Paris, FR  ' })), ['a']);
});

test('filterCatalogue: the surface filter stays verbatim — a token is not free text', () => {
	// Deliberate asymmetry with region: `surface` is a CHECK-constrained
	// identifier, and catalogueSurfaces does not fold-dedupe, so nothing offers
	// a spelling the database does not hold. Folding it would invent an
	// equivalence the schema does not have.
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { surface: 'ROAD' })), []);
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { surface: 'road' })), ['a', 'b']);
});

test('filterCatalogue: surface filter is an exact match', () => {
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { surface: 'road' })), ['a', 'b']);
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { surface: 'trail' })), ['c']);
});

test('filterCatalogue: null / empty filter values mean "all", not "match empty"', () => {
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { region: null, surface: '' })), [
		'a',
		'b',
		'c',
		'd',
	]);
});

test('filterCatalogue: filters combine (AND), and a contradiction is empty', () => {
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { query: 'park', surface: 'road' })), ['b']);
	assert.deepEqual(ids(filterCatalogue(CATALOGUE, { query: 'park', surface: 'trail' })), []);
});

test('filterCatalogue: does not mutate its input', () => {
	const before = ids(CATALOGUE);
	filterCatalogue(CATALOGUE, { query: 'park' });
	assert.deepEqual(ids(CATALOGUE), before);
});

// ─────────── catalogueRegions ───────────

test('catalogueRegions: distinct, blank-free, and ordered', () => {
	assert.deepEqual(catalogueRegions(CATALOGUE), [
		'Central Park, New York',
		'Paris, FR',
		'San Francisco, US',
		'Sydney, AU',
	]);
});

test('catalogueRegions: drops null and whitespace-only regions', () => {
	const rows = [
		seg({ id: 'a', region: null }),
		seg({ id: 'b', region: '   ' }),
		seg({ id: 'c', region: 'Oslo, NO' }),
	];
	assert.deepEqual(catalogueRegions(rows), ['Oslo, NO']);
});

test('catalogueRegions: dedupes case- and accent-variants onto the first spelling', () => {
	// Two curators typing the same place differently must not produce two
	// dropdown rows that each filter out half the segments.
	const rows = [
		seg({ id: 'a', region: 'Zürich, CH' }),
		seg({ id: 'b', region: 'zurich, ch' }),
	];
	assert.deepEqual(catalogueRegions(rows), ['Zürich, CH']);
});

// ─────────── catalogueSurfaces ───────────

test('catalogueSurfaces: canonical RouteSurface order, not alphabetical', () => {
	assert.deepEqual(catalogueSurfaces(CATALOGUE), ['road', 'trail', 'mixed']);
});

test('catalogueSurfaces: only offers surfaces the catalogue actually has', () => {
	const rows = [seg({ id: 'a', surface: 'trail' }), seg({ id: 'b', surface: 'trail' })];
	assert.deepEqual(catalogueSurfaces(rows), ['trail']);
});

test('catalogueSurfaces: an unknown surface stays selectable, after the known ones', () => {
	const rows = [
		seg({ id: 'a', surface: 'gravel' }),
		seg({ id: 'b', surface: 'road' }),
		seg({ id: 'c', surface: 'beach' }),
	];
	assert.deepEqual(catalogueSurfaces(rows), ['road', 'beach', 'gravel']);
});

// ─────────── sortCatalogue ───────────

test('sortCatalogue: by name, accent-folded', () => {
	assert.deepEqual(ids(sortCatalogue(CATALOGUE, 'name')), ['c', 'b', 'a', 'd']);
});

test('sortCatalogue: shortest and longest are exact reverses on distinct lengths', () => {
	assert.deepEqual(ids(sortCatalogue(CATALOGUE, 'shortest')), ['b', 'c', 'a', 'd']);
	assert.deepEqual(ids(sortCatalogue(CATALOGUE, 'longest')), ['d', 'a', 'c', 'b']);
});

test('sortCatalogue: most climb first', () => {
	assert.deepEqual(ids(sortCatalogue(CATALOGUE, 'climb')), ['b', 'c', 'd', 'a']);
});

test('sortCatalogue: equal values break the tie on name, so the order is stable', () => {
	const rows = [
		seg({ id: 'z', name: 'Zoo Loop', distance_m: 1000 }),
		seg({ id: 'a', name: 'Abbey Climb', distance_m: 1000 }),
	];
	assert.deepEqual(ids(sortCatalogue(rows, 'shortest')), ['a', 'z']);
	assert.deepEqual(ids(sortCatalogue(rows, 'longest')), ['a', 'z']);
});

test('sortCatalogue: an unknown elevation sorts last, never first, under most-climb', () => {
	const rows = [
		seg({ id: 'null', elevation_m: null }),
		seg({ id: 'small', elevation_m: 5 }),
		seg({ id: 'big', elevation_m: 400 }),
	];
	assert.deepEqual(ids(sortCatalogue(rows, 'climb')), ['big', 'small', 'null']);
});

test('sortCatalogue: an unparseable numeric sorts last under every numeric order', () => {
	const rows = [
		seg({ id: 'bad', distance_m: 'not-a-number' }),
		seg({ id: 'good', distance_m: 900 }),
	];
	assert.deepEqual(ids(sortCatalogue(rows, 'shortest')), ['good', 'bad']);
	assert.deepEqual(ids(sortCatalogue(rows, 'longest')), ['good', 'bad']);
});

test('sortCatalogue: PostgREST stringly numerics order numerically, not lexicographically', () => {
	// `numeric` arrives over the wire as a JSON string; "857" < "2135" as text
	// but not as a distance. The coercion lives inside sortCatalogue so no
	// caller has to remember it.
	const rows = [
		seg({ id: 'long', distance_m: '2135' }),
		seg({ id: 'short', distance_m: '857' }),
	];
	assert.deepEqual(ids(sortCatalogue(rows, 'shortest')), ['short', 'long']);
});

test('sortCatalogue: does not mutate its input', () => {
	const before = ids(CATALOGUE);
	sortCatalogue(CATALOGUE, 'longest');
	assert.deepEqual(ids(CATALOGUE), before);
});

// The `fold` block below is the mirror half of the Dart suite's `fold` group.
// Every vector in it is one the Dart twin's hand-written table answered
// differently until decisions § 852 replaced it with a generated one; keeping
// the two vector sets identical is what makes the pair's agreement visible.
// What ties the generated table to THIS implementation is
// `catalogue_fold_table.test.ts`, which runs this `fold` against it.

test('fold: Vietnamese tone marks fold, the barred D does not', () => {
	assert.equal(fold('Đèo Hải Vân'), 'đeo hai van');
	assert.equal(fold('Ơn Ưu'), 'on uu');
});

test('fold: Greek breathings, accents and both sigmas fold onto the letter', () => {
	assert.equal(fold('Ἀθήνα'), 'αθηνα');
	assert.equal(fold('Ῥόδος'), 'ροδοσ');
});

test('fold: the two sigmas fold together, so the search key is sigma-blind', () => {
	// toLowerCase applies Unicode's Final_Sigma rule, so ΟΔΟΣ used to fold to a
	// key the query "οδοσ" could not reach — the only context-dependent step in
	// the fold, and the one thing standing between it and a per-code-point port
	// (decisions § 853).
	assert.equal(fold('ΟΔΟΣ'), fold('οδος'));
	assert.equal(fold('οδοσ'), fold('οδος'));
});

test('fold: pinyin tone letters fold to the bare vowel', () => {
	assert.equal(fold('Huángshān Lǎodào'), 'huangshan laodao');
	assert.equal(fold('ǎǐǒǔ'), 'aiou');
});

test('fold: Cyrillic accents fold', () => {
	assert.equal(fold('Ё'), 'е');
	assert.equal(fold('Ї'), 'і');
});

test('fold: a spacing diacritic is deleted, not kept', () => {
	assert.equal(fold('a´b'), 'ab');
	assert.equal(fold('¨¯¸·`^'), '');
});

test('fold: a combining mark is dropped wherever it sits', () => {
	assert.equal(fold('Xī̌ān'), 'xian');
});

test('fold: a case mapping outside the older Unicode tables still folds', () => {
	// Georgian Mtavruli. Trivial here and load-bearing on the Dart side, where
	// the runtime's own case tables leave 466 code points uppercase — which is
	// why the generated table carries the case mapping rather than composing
	// with String.toLowerCase.
	assert.equal(fold('Ⴧ'), 'ⴧ');
});

test('fold: a CJK compatibility ideograph folds to its unified form', () => {
	assert.equal(fold('\u{F900}'), '\u{8C48}');
});

test('fold: a Hangul syllable decomposes to its jamo', () => {
	assert.equal(
		fold('북한산'),
		String.fromCharCode(0x1107, 0x116e, 0x11a8, 0x1112, 0x1161, 0x11ab, 0x1109, 0x1161, 0x11ab),
	);
});

test('fold: letters with no canonical decomposition stay unfolded', () => {
	// Folding these would invent an equivalence Unicode does not have.
	assert.equal(fold('Øst Đông Straße'), 'øst đong straße');
	assert.equal(fold('ħŧæœðþı'), 'ħŧæœðþı');
});

test('fold: folding only ever widens — an ASCII query reaches every variant', () => {
	for (const name of ['Đèo Hải Vân', 'Champs-Élysées', 'Huángshān', 'Ἀθήνα']) {
		assert.ok(fold(name.toUpperCase()).includes(fold(name)));
	}
	assert.ok(fold('Đèo Hải Vân').includes(fold('hai')));
	assert.ok(fold('Huángshān').includes(fold('huangshan')));
});

test('fold: a name outside the table passes through untouched', () => {
	assert.equal(fold(''), '');
	assert.equal(fold('central park - harlem hill'), 'central park - harlem hill');
	assert.equal(fold('東京 5K'), '東京 5k');
});

// ── compareFoldedNames ───────────────────────────────────────────────────
//
// The shared name order. Exported because the routes list sorts through it
// too: it used to call `localeCompare` here and `toLowerCase().compareTo()`
// on the phone, two orderings that disagree about 31.75 % of all pairs of
// Unicode letters (decisions § 1337).

test('compareFoldedNames: orders on the folded name, not on a collation or a code-unit order', () => {
	// `localeCompare` sorts Å beside A; a raw code-unit order sorts it after Z,
	// because U+00C5 > U+005A. The fold answers the same as the collation here
	// without depending on the host's ICU data.
	assert.equal(compareFoldedNames('Åre', 'a', 'Zaragoza', 'b'), -1);
	assert.equal(compareFoldedNames('Zaragoza', 'b', 'Åre', 'a'), 1);
	// Pin the order it is NOT: raw code units put Zaragoza first.
	assert.ok('Åre' > 'Zaragoza');
});

test('compareFoldedNames: case and accent do not decide the order', () => {
	// Folds equal, so the id breaks the tie rather than the spelling.
	assert.equal(compareFoldedNames('ÉCOLE', 'a', 'ecole', 'b'), -1);
	assert.equal(compareFoldedNames('ÉCOLE', 'b', 'ecole', 'a'), 1);
});

test('compareFoldedNames: U+0130 sorts with i, not apart from it', () => {
	// The reachable half of the 466-code-point lower-case gap. A browser's
	// `toLowerCase` emits i + a combining dot here, which sorts after a bare i
	// and does not even contain it; the fold strips the mark on both platforms.
	assert.equal(fold('İstanbul'), fold('Istanbul'));
	assert.equal(compareFoldedNames('İstanbul', 'a', 'Istanbul', 'b'), -1);
});

test('compareFoldedNames: ties break on id, so the order never depends on sort stability', () => {
	assert.equal(compareFoldedNames('Loop', 'a', 'Loop', 'b'), -1);
	assert.equal(compareFoldedNames('Loop', 'b', 'Loop', 'a'), 1);
});

test('compareFoldedNames: the same row compares equal to itself', () => {
	assert.equal(compareFoldedNames('Loop', 'x', 'Loop', 'x'), 0);
});
