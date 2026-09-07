import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { cataloguePickerView, type CatalogueEntry } from './exercise_catalogue_picker';

// The behavioural pin § 1278 said the tree had nowhere to put. Every case
// below was mutation-tested against the code it describes: reverting the fold
// to `trim().toLowerCase()`, dropping `hiddenExact`, or narrowing `canCreate`
// to the visible set each fails at least one of them.

const entry = (id: string, name: string, category: string): CatalogueEntry => ({
	id,
	name,
	category,
});

const BENCH = entry('e1', 'Bench Press', 'chest');
const SQUAT = entry('e2', 'Back Squat', 'legs');
const LUNGE = entry('e3', 'Walking Lunge', 'legs');
const CATALOGUE = [BENCH, SQUAT, LUNGE];

test('a blank query lists the whole catalogue and offers no create', () => {
	const view = cataloguePickerView(CATALOGUE, { query: '', category: 'all' });
	assert.deepEqual(
		view.matches.map((e) => e.name),
		['Back Squat', 'Bench Press', 'Walking Lunge'],
	);
	assert.equal(view.canCreate, false);
	assert.equal(view.hiddenExact, null);
});

test('a blank query under a category lists only that category', () => {
	const view = cataloguePickerView(CATALOGUE, { query: '', category: 'legs' });
	assert.deepEqual(
		view.matches.map((e) => e.id),
		['e2', 'e3'],
	);
});

test('the search folds both sides through the canonical key', () => {
	// U+00A0 is a whitespace character the exercise key collapses and
	// `trim().toLowerCase()` does not: the entry that trapped § 1276.
	const nbsp = [entry('e9', 'Bench\u00A0Press', 'chest')];
	const view = cataloguePickerView(nbsp, { query: 'bench press', category: 'all' });
	assert.deepEqual(
		view.matches.map((e) => e.id),
		['e9'],
	);
	assert.equal(view.canCreate, false, 'the entry exists, so nothing may be created under its key');
});

test('an unmatched query offers the create affordance', () => {
	const view = cataloguePickerView(CATALOGUE, { query: 'Farmer Carry', category: 'all' });
	assert.deepEqual(view.matches, []);
	assert.equal(view.canCreate, true);
	assert.equal(view.hiddenExact, null);
});

test('a partial match lists the entries and still offers to create', () => {
	const view = cataloguePickerView(CATALOGUE, { query: 'squat', category: 'all' });
	assert.deepEqual(
		view.matches.map((e) => e.id),
		['e2'],
	);
	assert.equal(view.canCreate, true, '"squat" is not the name of any entry');
});

test('an exact name hidden by the category filter is reported, not silently dropped', () => {
	const view = cataloguePickerView(CATALOGUE, { query: 'bench press', category: 'legs' });
	assert.deepEqual(view.matches, [], 'no leg exercise matches');
	assert.equal(view.canCreate, false, 'the name is taken, whatever category is selected');
	assert.equal(view.hiddenExact?.id, BENCH.id, 'the state that had no rendering before');
});

test('the hidden-exact report folds too', () => {
	const nbsp = [entry('e9', 'Bench\u00A0Press', 'chest'), SQUAT];
	const view = cataloguePickerView(nbsp, { query: 'BENCH PRESS', category: 'legs' });
	assert.equal(view.hiddenExact?.id, 'e9');
});

test('an exact match the filter does not hide is not reported as hidden', () => {
	const view = cataloguePickerView(CATALOGUE, { query: 'bench press', category: 'chest' });
	assert.deepEqual(
		view.matches.map((e) => e.id),
		['e1'],
	);
	assert.equal(view.hiddenExact, null);
	assert.equal(view.canCreate, false);
});

test('under "all" an exact match is always visible, so nothing is ever hidden', () => {
	// § 1276's structural claim: a key EQUAL to the query necessarily
	// CONTAINS it, so the only thing that can remove an exact match from the
	// list is the category filter.
	for (const e of CATALOGUE) {
		const view = cataloguePickerView(CATALOGUE, { query: e.name, category: 'all' });
		assert.equal(view.hiddenExact, null, e.name);
		assert.ok(
			view.matches.some((m) => m.id === e.id),
			e.name,
		);
	}
});

test('a whitespace-only query is treated as blank', () => {
	const view = cataloguePickerView(CATALOGUE, { query: '   ', category: 'all' });
	assert.equal(view.canCreate, false);
	assert.equal(view.matches.length, CATALOGUE.length);
});

test('the list is ordered by collation, so an accented name is not filed after z', () => {
	// The divergence § 1276 measured: a code-unit compare over folded keys
	// puts every accented name after "Zercher Squat"; a collation does not.
	const accented = [
		entry('a', 'Zercher Squat', 'legs'),
		entry('b', 'Élévation latérale', 'shoulders'),
		entry('c', 'Ab Wheel', 'core'),
	];
	const names = cataloguePickerView(accented, { query: '', category: 'all' }).matches.map(
		(e) => e.name,
	);
	assert.equal(names[0], 'Ab Wheel');
	assert.ok(
		names.indexOf('Élévation latérale') < names.indexOf('Zercher Squat'),
		`accented name filed after z: ${names.join(', ')}`,
	);
});

test('names a collation calls equal are ordered by id, not by input order', () => {
	const dupes = [entry('z', 'Row', 'back'), entry('a', 'Row', 'back')];
	const forward = cataloguePickerView(dupes, { query: '', category: 'all' });
	const reversed = cataloguePickerView([...dupes].reverse(), { query: '', category: 'all' });
	assert.deepEqual(
		forward.matches.map((e) => e.id),
		['a', 'z'],
	);
	assert.deepEqual(
		reversed.matches.map((e) => e.id),
		forward.matches.map((e) => e.id),
	);
});

test('the input array is not reordered in place', () => {
	const input = [...CATALOGUE];
	cataloguePickerView(input, { query: '', category: 'all' });
	assert.deepEqual(
		input.map((e) => e.id),
		['e1', 'e2', 'e3'],
	);
});
