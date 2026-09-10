import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';

import { stripComments } from '../core/strip_comments';
import {
	cataloguePickerView,
	shadowsSeededGlobal,
	type CatalogueEntry,
} from './exercise_catalogue_picker';

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

test('a shadowed name reports the same entry whichever order the fetch returned', () => {
	// `exercises` allows an owner custom to shadow a seeded global under one
	// folded key, so two rows can match exactly. `fetchExerciseCatalogue`
	// orders by `name` with no id tiebreak, so their relative order is an
	// unspecified tie — without the sort here the sentence names a different
	// category on the next reload.
	const global = entry('e1', 'Bench Press', 'chest');
	const custom = entry('e9', 'Bench Press', 'arms');
	const forward = cataloguePickerView([global, custom, SQUAT], {
		query: 'bench press',
		category: 'legs',
	});
	const reversed = cataloguePickerView([custom, global, SQUAT], {
		query: 'bench press',
		category: 'legs',
	});
	assert.equal(forward.hiddenExact?.id, 'e1');
	assert.equal(reversed.hiddenExact?.id, forward.hiddenExact?.id);
	assert.equal(forward.canCreate, false, 'the key is taken twice over');
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

test('an accented name is not filed after z', () => {
	// The divergence § 1276 measured: a code-unit compare over folded keys
	// puts every accented name after "Zercher Squat". The fold does not —
	// which is the whole reason § 1334 could put the phone on it.
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

test('the order is the phone\'s order, not the host collation\'s', () => {
	// The case that separates the two instruments. `Æ` has no canonical
	// decomposition, so the fold leaves it at U+00E6 and files it after `z`;
	// ICU interleaves it with `A` and puts it FIRST. Both are defensible
	// orderings of one name; what is not defensible is the browser answering
	// one and the phone the other, because `GymEditor`'s `catalogueByKey`
	// resolves a shadowed name to an `exercises.id` by walking this list.
	//
	// Mutation: restoring `a.name.localeCompare(b.name)` fails this case and
	// only this one — measured, the two agree on all 43 seeded globals and on
	// § 1334's eight-name list, and part only once a custom carries a letter
	// outside ASCII.
	const mixed = [
		entry('a', 'Æbleplukning', 'other'),
		entry('b', 'Back Squat', 'legs'),
		entry('c', 'Øvre ryg', 'back'),
	];
	assert.deepEqual(
		cataloguePickerView(mixed, { query: '', category: 'all' }).matches.map((e) => e.name),
		['Back Squat', 'Æbleplukning', 'Øvre ryg'],
	);
});

test('§ 1334\'s measured list orders identically on both platforms', () => {
	// The eight names the mobile twin's widget test asserts, verbatim. The
	// two suites now pin one order rather than two that happen to agree.
	const names = [
		'Zercher Squat',
		'Überzug',
		'źcisk',
		'Row',
		'Overhead Press',
		'Élévation latérale',
		'Bench Press',
		'Ab Wheel',
	];
	const view = cataloguePickerView(
		names.map((n, i) => entry(`e${i}`, n, 'other')),
		{ query: '', category: 'all' },
	);
	assert.deepEqual(view.matches.map((e) => e.name), [
		'Ab Wheel',
		'Bench Press',
		'Élévation latérale',
		'Overhead Press',
		'Row',
		'Überzug',
		'źcisk',
		'Zercher Squat',
	]);
});

test('names the fold calls equal are ordered by id, not by input order', () => {
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

test('an unavailable catalogue offers no create, whatever the query says', () => {
	// The whole point of the third state: `canCreate` is a claim about what the
	// catalogue does NOT hold, and a list that failed to load supports no such
	// claim. Against the same catalogue and the same query, the only difference
	// is whether the read answered.
	const known = cataloguePickerView(CATALOGUE, { query: 'Front Squat', category: 'all' });
	assert.equal(known.canCreate, true);
	assert.equal(known.unavailable, false);

	const unknown = cataloguePickerView(CATALOGUE, {
		query: 'Front Squat',
		category: 'all',
		unavailable: true,
	});
	assert.equal(unknown.canCreate, false, 'a name cannot be proved free against a list that failed');
	assert.equal(unknown.unavailable, true);
});

test('an unavailable catalogue still lists what it has', () => {
	// A stale entry binds its id correctly, so hiding the rows would be a second
	// untruth on top of the first — the notice is what carries the caveat.
	const view = cataloguePickerView(CATALOGUE, {
		query: 'squat',
		category: 'all',
		unavailable: true,
	});
	assert.deepEqual(
		view.matches.map((e) => e.id),
		['e2'],
	);
});

test('an unavailable catalogue reports itself even on a blank query', () => {
	// The blank-query branch returns early, so it needs the flag explicitly or
	// the notice disappears the moment the search box is cleared.
	const view = cataloguePickerView(CATALOGUE, { query: '', category: 'all', unavailable: true });
	assert.equal(view.unavailable, true);
	assert.equal(view.canCreate, false);
});

test('an absent unavailable flag reads as available', () => {
	const view = cataloguePickerView(CATALOGUE, { query: 'Front Squat', category: 'all' });
	assert.equal(view.unavailable, false);
	assert.equal(view.canCreate, true);
});

/**
 * The picker must TRACK its catalogue prop, not snapshot it — and the pin for
 * that is source-level.
 *
 * § 1481 fixed a reactivity property of a Svelte component, and § 1278 records
 * why nothing here could hold it: `apps/web` runs its unit suite under
 * `tsx --test`, which cannot compile a component. § 1958 asked for a Playwright
 * case instead and three rounds running were not permitted to execute one, so
 * the fix sat unpinned; the tree's own answer to exactly this shape is
 * `gym_execution_band_seeding.test.ts`, which reads a component's source
 * because the seeding it pins lives in an `$effect` a DOM-free test cannot
 * drive. The objection § 1958 raised was to a BLANKET ban — seeding local state
 * from a prop with `untrack` is correct in five other components in this tree —
 * and these read one file, so no correct component is in their reach.
 *
 * They are anchored on the reactive graph rather than on spelling: the picker's
 * decisions must be taken over a `$derived` that READS the prop, and no local
 * `$state` may be initialised from it. Both are properties a regression breaks
 * and neither is satisfiable by a component that snapshots.
 */
const PICKER = readFileSync(
	new URL('./ExerciseCataloguePicker.svelte', import.meta.url),
	'utf8',
);

/// The component's `<script>` body with comments blanked, so a rune named in
/// prose is not read as a declaration.
///
/// Through the shared stripper rather than a pair of regexes: it is the only
/// copy that survives a `/*` inside a line comment, a string or a regex
/// literal, and `source_scanner_guards.test.ts` fails a scanner that spells
/// its own.
function pickerScript(source: string): string {
	const open = source.indexOf('<script');
	const start = source.indexOf('>', open) + 1;
	const body = source.slice(start, source.indexOf('</script>', start));
	return stripComments(body);
}

/// Every `$state` / `$derived` declaration in a Svelte 5 script, as the rune it
/// uses, the name it binds, and the initialiser it is given.
function runeDeclarations(
	script: string,
): { rune: string; name: string; init: string }[] {
	const out: { rune: string; name: string; init: string }[] = [];
	const re =
		/\b(?:let|const)\s+([A-Za-z_$][\w$]*)(?:\s*:\s*[^=]+?)?\s*=\s*(\$state|\$derived)(?:\.by)?\s*(?:<[^=<>]*>)?\s*\(/g;
	for (let m = re.exec(script); m !== null; m = re.exec(script)) {
		let depth = 1;
		let i = re.lastIndex;
		for (; i < script.length && depth > 0; i++) {
			if (script[i] === '(') depth++;
			else if (script[i] === ')') depth--;
		}
		out.push({ rune: m[2], name: m[1], init: script.slice(re.lastIndex, i - 1) });
	}
	return out;
}

/// The picker's own declarations, and the two shapes a regression wears: the
/// merged snapshot the component had before § 1481, and a snapshot held beside
/// the prop rather than derived from it.
const SNAPSHOT_FORMS: [string, string][] = [
	[
		'the merged snapshot § 1481 replaced',
		PICKER.replace(
			'let created = $state<Exercise[]>([]);',
			'let created = $state<Exercise[]>([...catalogue]);',
		),
	],
	[
		'the derived downgraded to a snapshot',
		PICKER.replace(
			'const entries = $derived(dedupeShadowedExercises([...catalogue, ...created]));',
			'let entries = $state(dedupeShadowedExercises([...catalogue, ...created]));',
		),
	],
];

function tracksTheProp(source: string): boolean {
	const decls = runeDeclarations(pickerScript(source));
	const entries = decls.find((d) => d.name === 'entries');
	if (entries === undefined || entries.rune !== '$derived') return false;
	if (!/\bcatalogue\b/.test(entries.init)) return false;
	return !decls.some((d) => d.rune === '$state' && /\bcatalogue\b/.test(d.init));
}

test('the picker derives its entries from the catalogue prop, and snapshots nothing', () => {
	const decls = runeDeclarations(pickerScript(PICKER));
	assert.ok(decls.length >= 3, 'no rune declarations parsed — has the script moved?');

	const entries = decls.find((d) => d.name === 'entries');
	assert.ok(entries, 'the picker no longer names the value its decisions are taken over');
	assert.equal(
		entries.rune,
		'$derived',
		'a snapshot cannot see a catalogue read that answers after the picker mounts, ' +
			'and an empty list makes every name look free',
	);
	assert.match(
		entries.init,
		/\bcatalogue\b/,
		'the derived must read the prop itself, not a copy of it',
	);

	const seeded = decls.filter((d) => d.rune === '$state' && /\bcatalogue\b/.test(d.init));
	assert.deepEqual(
		seeded.map((d) => d.name),
		[],
		'local state seeded from the catalogue prop is the snapshot § 1481 removed',
	);
});

test('the picker decides over the derived value, never over the raw prop', () => {
	const script = pickerScript(PICKER);
	const at = script.indexOf('cataloguePickerView(');
	assert.ok(at >= 0, 'the picker no longer calls cataloguePickerView — re-anchor this guard');
	assert.match(
		script.slice(at, script.indexOf(')', at)),
		/cataloguePickerView\(\s*entries\b/,
		'the view must be taken over the derived entries, or the merge is bypassed',
	);
});

test('the tracking pin fails against each snapshot form it replaced', () => {
	assert.equal(tracksTheProp(PICKER), true, 'the picker as it stands must pass');
	for (const [label, broken] of SNAPSHOT_FORMS) {
		assert.notEqual(broken, PICKER, `${label}: the anchor moved — re-anchor this guard`);
		assert.equal(tracksTheProp(broken), false, `${label} must fail the tracking pin`);
	}
});

test('a created custom carrying a seeded global key is reported as a shadow', () => {
	const global = { name_key: 'bench press', author_id: null };
	const mine = { name_key: 'bench press', author_id: 'me' };
	assert.equal(shadowsSeededGlobal([global], mine), true);
});

test('a created custom under a free name shadows nothing', () => {
	assert.equal(
		shadowsSeededGlobal(
			[{ name_key: 'bench press', author_id: null }],
			{ name_key: 'farmer carry', author_id: 'me' },
		),
		false,
	);
});

test('a custom sitting beside another custom of the same key is not a shadow', () => {
	// Only the GLOBAL disappears from the reader's list. Two customs under one
	// key cannot both exist — the author's partial unique forbids it — but a
	// list carrying someone else's row must not be read as a built-in.
	assert.equal(
		shadowsSeededGlobal(
			[{ name_key: 'bench press', author_id: 'someone' }],
			{ name_key: 'bench press', author_id: 'me' },
		),
		false,
	);
});

test('a seeded global is never reported as shadowing anything', () => {
	// The insert RLS forbids it, and reporting it would tell a reader their own
	// row replaced a built-in when nothing of theirs was created at all.
	assert.equal(
		shadowsSeededGlobal(
			[{ name_key: 'bench press', author_id: null }],
			{ name_key: 'bench press', author_id: null },
		),
		false,
	);
});

test('the shadow test reads the stored key, not the display spelling', () => {
	// The two part in the window a regenerated fold table opens (§ 1176), and
	// the index is the authority on what a shadow is.
	assert.equal(
		shadowsSeededGlobal(
			[{ name_key: 'bench press', author_id: null }],
			{ name_key: 'Bench Press', author_id: 'me' },
		),
		false,
	);
});
