// The other half of issue #666's surfaced item 3 on web: a hand-capitalised
// kind label.
//
// `/coaching/athletes/[id]` rendered a plan workout's kind by ASCII-capitalising
// the database identifier — `kind.replace(/_/g, ' ')` then upper-casing the
// first character — so a German or Japanese coach read "Marathon pace",
// "Walk run" and "Long" in English on an otherwise localized page, and
// `long` (whose real label is "Long run") lost a word. A complete
// `workoutKind.*` vocabulary already existed in all six catalogues, reached
// through `workoutKindLabel`; the call site simply did not use it.
//
// Pinned derivationally rather than by asserting a label string. Two claims:
//
//  1. The mapping is TOTAL over the database enum. That is what makes routing
//     the call site onto it safe — `workoutKindLabel` falls back to the raw
//     identifier for an unmapped kind, which is the same hardcoded-identifier
//     defect wearing a helper's name, so a kind added to the enum without a
//     key here must fail rather than silently print `marathon_pace`.
//  2. No surface hand-capitalises a kind again. Source-scanned, because the
//     defect is a shape a type cannot forbid.
//
// Invocation:
//   npx tsx --test src/lib/training/workout_labels.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { en } from '../i18n/locales/en';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC_ROOT = resolve(__dirname, '..', '..');
const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

// Read both ends out of the tree rather than restating either: the enum from
// the generated types, the key map from the module under test. A test that
// spelled its own list of kinds would pass while the two drifted.
function databaseWorkoutKinds(): string[] {
	const types = readFileSync(join(SRC_ROOT, 'lib/database.types.ts'), 'utf-8');
	const block = types.match(/\n {6}workout_kind:\n((?: {8}\| "[a-z_]+"\n)+)/);
	assert.ok(block, 'database.types.ts no longer declares the workout_kind enum in the expected shape');
	return [...block[1].matchAll(/"([a-z_]+)"/g)].map((m) => m[1]).sort();
}

function mappedWorkoutKinds(): string[] {
	const src = readFileSync(join(__dirname, 'workout_labels.ts'), 'utf-8');
	const block = src.match(/const WORKOUT_KIND_KEY[^{]*\{([^}]*)\}/);
	assert.ok(block, 'workout_labels.ts no longer declares WORKOUT_KIND_KEY');
	return [...block[1].matchAll(/^\t([a-z_]+):/gm)].map((m) => m[1]).sort();
}

test('workoutKindLabel maps every workout_kind the database can store', () => {
	const kinds = databaseWorkoutKinds();
	assert.ok(kinds.length >= 9, `read only ${kinds.length} kinds out of database.types.ts`);
	assert.deepEqual(
		mappedWorkoutKinds(),
		kinds,
		'WORKOUT_KIND_KEY and the workout_kind enum have drifted. An unmapped kind falls ' +
			'back to the raw identifier, which is the hardcoded-English defect this helper exists ' +
			'to remove.',
	);
});

test('every workoutKind key the map names exists in the catalogue', () => {
	const src = readFileSync(join(__dirname, 'workout_labels.ts'), 'utf-8');
	const keys = [...src.matchAll(/'(workoutKind\.[a-z_]+)'/g)].map((m) => m[1]);
	assert.equal(keys.length, 9, `expected 9 workoutKind keys, found ${keys.length}`);
	for (const key of keys) {
		assert.ok(key in en, `${key} is referenced by workout_labels.ts but absent from en.ts`);
	}
});

// `x.charAt(0).toUpperCase() + x.slice(1)` and the `x[0]` spelling of it.
//
// Deliberately NOT scoped to identifiers containing "kind": the defect this
// closed was written `const k = (w.kind ?? 'run').replace(/_/g, ' ')` and then
// capitalised `k`, so a name-keyed matcher would have spared the very line it
// exists for. The shape is scanned everywhere instead and the legitimate uses
// are named, which makes the list complete rather than merely plausible — the
// same bargain the hex register makes.
const HAND_CAPITALISED = /([A-Za-z_$][\w.$?[\]']*)\s*(?:\.charAt\(0\)|\[0\])\.toUpperCase\(\)\s*\+/g;

const SCAN_FIXTURES: Array<[flagged: boolean, line: string]> = [
	// The exact line this round removed, one-letter alias and all.
	[true, 'return k.charAt(0).toUpperCase() + k.slice(1);'],
	[true, 'const s = w.kind.charAt(0).toUpperCase() + w.kind.slice(1);'],
	[true, 'const s = kind[0].toUpperCase() + kind.slice(1);'],
	[true, 'const cap = entity[0].toUpperCase() + entity.slice(1);'],
	// Spared: an initial for an avatar capitalises nothing back on, so the
	// trailing `+` never appears.
	[false, "return parts.map((p) => p.charAt(0).toUpperCase()).join('');"],
	[false, 'const initial = name.charAt(0).toUpperCase();'],
	// Spared: the localized route, which is the whole point.
	[false, 'return workoutKindLabel(w.kind);'],
];

test('the hand-capitalisation scan flags the shape and spares a bare initial', () => {
	for (const [flagged, line] of SCAN_FIXTURES) {
		assert.equal(
			[...line.matchAll(HAND_CAPITALISED)].length > 0,
			flagged,
			`the scan must ${flagged ? 'flag' : 'spare'} ${JSON.stringify(line)}`,
		);
	}
});

// file -> exact number of hand-capitalisation sites, each named. Count-pinned
// so the list can only shrink and a new one fails wherever it lands.
const HAND_CAPITALISED_ALLOWED: Record<string, number> = {
	// Not UI: a test building the capitalised entity name it then asserts on.
	'lib/share/share_entity_dispatch_guard.test.ts': 1,
	// `sub_sport` off a FIT file — a third party's free-text discipline string,
	// not an enum this app owns, so there is no vocabulary to route it onto and
	// inventing one would mean translating values we do not control.
	'routes/runs/[id]/+page.svelte': 1,
};

test('every hand-capitalisation site is named, and no workout kind is among them', () => {
	const byFile: Record<string, string[]> = {};
	let scanned = 0;
	const self = fileURLToPath(import.meta.url);
	(function walk(dir: string): void {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const path = join(dir, entry.name);
			if (entry.isDirectory()) {
				if (!SKIP_DIRS.has(entry.name)) walk(path);
				continue;
			}
			if (!/\.(svelte|ts)$/.test(entry.name)) continue;
			if (path === self) continue;
			scanned++;
			const rel = relative(SRC_ROOT, path).split(sep).join('/');
			readFileSync(path, 'utf-8')
				.split('\n')
				.forEach((line, i) => {
					for (const match of line.matchAll(HAND_CAPITALISED)) {
						(byFile[rel] ??= []).push(`${rel}:${i + 1}  ${match[0].trim()}`);
					}
				});
		}
	})(SRC_ROOT);
	// Assert the population: a walker that reached nothing would pass below.
	assert.ok(scanned > 300, `the scan reached only ${scanned} files`);
	const unlisted = Object.keys(byFile).filter((f) => !(f in HAND_CAPITALISED_ALLOWED));
	assert.deepEqual(
		unlisted.flatMap((f) => byFile[f]),
		[],
		'Hand-capitalising a database identifier prints English on a localized page and loses ' +
			'the words the catalogue adds ("long" is "Long run"). A workout kind goes through ' +
			'`workoutKindLabel`; anything else needs an entry here saying why it cannot.',
	);
	for (const [file, expected] of Object.entries(HAND_CAPITALISED_ALLOWED)) {
		assert.equal(
			(byFile[file] ?? []).length,
			expected,
			`${file} carries ${(byFile[file] ?? []).length} hand-capitalisation site(s), expected ` +
				`${expected}. If one was localized, drop the entry; if one was ADDED, localize it ` +
				`instead:\n${(byFile[file] ?? []).join('\n')}`,
		);
	}
});
